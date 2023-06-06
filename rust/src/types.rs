//! Various structures returned by the Proxmox VE API.

use std::collections::HashMap;
use std::fmt::{Formatter, Result as FmtResult};
use std::result::Result as StdResult;
use std::str::FromStr;

use anyhow::anyhow;
use regex::Regex;
use serde::de::{Deserializer, Error as DeError, MapAccess, Visitor};
use serde::Deserialize;

use crate::defs::{Error, JsonValue, Result};
use crate::parse;

/// Recognize disk drives and network interfaces in a VM configuration.
const RE_PERIPH_PATTERN: &str = r#"(?x)
    ^
    (?P<type> ide | net | sata | scsi | virtio )
    (?P<idx> 0 | [1-9][0-9]* )
    $
"#;

/// A lower-level subdirectory in the configuration tree.
#[derive(Debug, Deserialize)]
pub struct Subdir {
    /// The name of the subdirectory.
    subdir: String,
}

impl Subdir {
    #[inline]
    #[must_use]
    pub fn subdir(&self) -> &str {
        &self.subdir
    }
}

/// A lower-level subdirectory in the configuration tree identified by name.
#[derive(Debug, Deserialize)]
pub struct NameSubdir {
    /// The name of the subdirectory.
    name: String,
}

impl NameSubdir {
    #[inline]
    #[must_use]
    pub fn name(&self) -> &str {
        &self.name
    }
}

/// A storage defined for the Proxmox VE cluster.
///
/// Maybe we should turn this into an enum...
#[derive(Debug, Deserialize)]
pub struct Storage {
    /// A comma-separated list of content types that may be placed on this type of storage.
    content: String,

    /// The checksum of the current version of this storage definition.
    digest: String,

    /// Additional tags to set for StorPool volumes and snapshots.
    extra_tags: Option<String>,

    /// The name of the Proxmox VE storage.
    storage: String,

    /// The name of the StorPool template, if not the same as the storage name.
    template: Option<String>,

    /// The Proxmox VE driver that handles this type of storage.
    #[serde(rename = "type")]
    storage_type: String,
}

impl Storage {
    #[inline]
    #[must_use]
    pub fn content(&self) -> &str {
        &self.content
    }

    #[inline]
    #[must_use]
    pub fn digest(&self) -> &str {
        &self.digest
    }

    #[inline]
    #[must_use]
    pub fn extra_tags(&self) -> Option<&str> {
        self.extra_tags.as_deref()
    }

    #[inline]
    #[must_use]
    pub fn storage(&self) -> &str {
        &self.storage
    }

    #[inline]
    #[must_use]
    pub fn template(&self) -> Option<&str> {
        self.template.as_deref()
    }

    #[inline]
    #[must_use]
    pub fn storage_type(&self) -> &str {
        &self.storage_type
    }
}

/// The status reported for a single node.
///
/// Note: any changes to this enum shall be considered breaking.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[allow(clippy::exhaustive_enums)]
pub enum NodeStatus {
    /// The node is offline.
    #[serde(rename = "offline")]
    Offline,

    /// The node is online.
    #[serde(rename = "online")]
    Online,

    /// There is no information about the node's status.
    #[serde(rename = "unknown")]
    Unknown,
}

/// General information about a Proxmox VE node.
#[derive(Debug, Deserialize)]
pub struct NodeSummary {
    /// The node type (usually the constant string "node").
    #[serde(rename = "type")]
    node_type: String,

    /// The node name.
    node: String,

    /// The node status in the Proxmox VE cluster.
    status: NodeStatus,

    /// A qualified object identifier for this node.
    id: String,

    /// CPU utilization.
    cpu: Option<f64>,

    /// Disk usage.
    disk: Option<u64>,

    /// Support level.
    level: Option<String>,

    /// Number of available CPUs.
    maxcpu: Option<u32>,

    /// Available disk space.
    maxdisk: Option<u64>,

    /// Available memory in bytes.
    maxmem: Option<u64>,

    /// Used memory in bytes.
    mem: Option<u64>,

    /// The SSL fingerprint of the node certificate.
    ssl_fingerprint: Option<String>,

    /// Node uptime in seconds.
    uptime: Option<u64>,
}

impl NodeSummary {
    #[inline]
    #[must_use]
    pub fn node(&self) -> &str {
        &self.node
    }

    #[inline]
    #[must_use]
    pub const fn status(&self) -> NodeStatus {
        self.status
    }

    #[inline]
    #[must_use]
    pub const fn cpu(&self) -> Option<f64> {
        self.cpu
    }

    #[inline]
    #[must_use]
    pub const fn disk(&self) -> Option<u64> {
        self.disk
    }

    #[inline]
    #[must_use]
    pub fn id(&self) -> &str {
        &self.id
    }

    #[inline]
    #[must_use]
    pub fn level(&self) -> Option<&str> {
        self.level.as_deref()
    }

    #[inline]
    #[must_use]
    pub const fn maxcpu(&self) -> Option<u32> {
        self.maxcpu
    }

    #[inline]
    #[must_use]
    pub const fn maxdisk(&self) -> Option<u64> {
        self.maxdisk
    }

    #[inline]
    #[must_use]
    pub const fn maxmem(&self) -> Option<u64> {
        self.maxmem
    }

    #[inline]
    #[must_use]
    pub const fn mem(&self) -> Option<u64> {
        self.mem
    }

    #[inline]
    #[must_use]
    pub fn node_type(&self) -> &str {
        &self.node_type
    }

    #[inline]
    #[must_use]
    pub fn ssl_fingerprint(&self) -> Option<&str> {
        self.ssl_fingerprint.as_deref()
    }

    #[inline]
    #[must_use]
    pub const fn uptime(&self) -> Option<u64> {
        self.uptime
    }
}

/// The status reported for a single virtual machine.
///
/// Note: any changes to this enum shall be considered breaking.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[allow(clippy::exhaustive_enums)]
pub enum VmStatus {
    /// The VM is running.
    #[serde(rename = "running")]
    Running,

    /// The VM is stopped.
    #[serde(rename = "stopped")]
    Stopped,
}

/// Summary information about a Proxmox VE virtual machine.
#[derive(Debug, Deserialize)]
pub struct VmSummary {
    /// The ID of the VM.
    vmid: u32,

    /// QEMU process status.
    status: VmStatus,

    /// Maximum usable CPUs.
    cpus: Option<u32>,

    /// The current config lock, if any.
    lock: Option<String>,
}

impl VmSummary {
    #[inline]
    #[must_use]
    pub const fn vmid(&self) -> u32 {
        self.vmid
    }

    #[inline]
    #[must_use]
    pub const fn status(&self) -> VmStatus {
        self.status
    }

    #[inline]
    #[must_use]
    pub const fn cpus(&self) -> Option<u32> {
        self.cpus
    }

    #[inline]
    #[must_use]
    pub fn lock(&self) -> Option<&str> {
        self.lock.as_deref()
    }
}

#[derive(Debug)]
#[allow(clippy::exhaustive_enums)]
pub enum VmNetIface {
    Virtio(u32, String),
}

/// The type of the disk as seen by the virtual machine (IDE, SCSI, etc.).
#[derive(Debug, Clone, Copy)]
#[allow(clippy::exhaustive_enums)]
pub enum VmDiskType {
    /// A simulated IDE disk.
    Ide,

    /// A simulated serial ATA disk.
    Sata,

    /// A simulated SCSI disk.
    Scsi,

    /// A disk using qemu's "virtio" emulation protocol.
    Virtio,
}

impl VmDiskType {
    /// The identifier for IDE disks.
    const IDE: &str = "ide";

    /// The identifier for SATA disks.
    const SATA: &str = "sata";

    /// The identifier for SCSI disks.
    const SCSI: &str = "scsi";

    /// The identifier for virtio disks.
    const VIRTIO: &str = "virtio";
}

impl AsRef<str> for VmDiskType {
    #[inline]
    fn as_ref(&self) -> &str {
        match *self {
            Self::Ide => Self::IDE,
            Self::Sata => Self::SATA,
            Self::Scsi => Self::SCSI,
            Self::Virtio => Self::VIRTIO,
        }
    }
}

impl FromStr for VmDiskType {
    type Err = Error;

    #[inline]
    fn from_str(value: &str) -> Result<Self> {
        match value {
            Self::IDE => Ok(Self::Ide),
            Self::SATA => Ok(Self::Sata),
            Self::SCSI => Ok(Self::Scsi),
            Self::VIRTIO => Ok(Self::Virtio),
            other => Err(Error::Api(anyhow!("Invalid disk type '{other}'"))),
        }
    }
}

/// A single disk attached to a Proxmox VE virtual machine.
#[derive(Debug)]
pub struct VmDisk {
    /// The disk type as seen by the VM.
    disk_type: VmDiskType,

    /// The per-disk-type index of the disk within the VM (e.g. 2 for `scsi2`).
    idx: u32,

    /// The identifier of the Proxmox VE storage where the disk data is stored.
    storage: String,

    /// The storage-specific ID of the volume where the disk data is stored.
    volid: String,

    /// Any additional options configured for the disk (`size`, `discard`, `iothread`, etc.).
    options: HashMap<String, String>,
}

impl VmDisk {
    #[inline]
    #[must_use]
    pub const fn disk_type(&self) -> VmDiskType {
        self.disk_type
    }
    #[inline]
    #[must_use]
    pub const fn idx(&self) -> u32 {
        self.idx
    }
    #[inline]
    #[must_use]
    pub fn storage(&self) -> &str {
        &self.storage
    }
    #[inline]
    #[must_use]
    pub fn volid(&self) -> &str {
        &self.volid
    }
    #[inline]
    #[must_use]
    pub const fn options(&self) -> &HashMap<String, String> {
        &self.options
    }
}

/// Parse the definition of a Proxmox VE disk as found in the VM configuration.
///
/// # Errors
///
/// [`Error::Api`] if the definition string cannot be parsed.
#[inline]
pub fn parse_disk(disk_type: VmDiskType, idx: u32, contents: &str) -> Result<VmDisk> {
    let (storage, volid, options) = parse::disk(contents)?;
    Ok(VmDisk {
        disk_type,
        idx,
        storage,
        volid,
        options,
    })
}

// The configuration of a Proxmox VE virtual machine.
#[derive(Debug, Default)]
pub struct VmConfig {
    /// The checksum of the current version of the virtual machine's configuration.
    digest: String,

    /// The simulated SCSI controller type.
    scsihw: Option<String>, // FIXME: this should be an enum

    /// The network interfaces attached to the virtual machine.
    net: Vec<VmNetIface>,

    /// The various disks (IDE, SATA, SCSI, Virtio) attached to the virtual machine.
    disks: Vec<VmDisk>,
}

impl VmConfig {
    #[inline]
    #[must_use]
    pub fn digest(&self) -> &str {
        &self.digest
    }
    #[inline]
    #[must_use]
    pub fn scsihw(&self) -> Option<&str> {
        self.scsihw.as_deref()
    }
    #[inline]
    #[must_use]
    pub fn net(&self) -> &[VmNetIface] {
        &self.net
    }
    #[inline]
    #[must_use]
    pub fn disks(&self) -> &[VmDisk] {
        &self.disks
    }
}

/// A helper for deserializing the [`VmConfig`] struct.
struct VmConfigVisitor;

impl<'de> Visitor<'de> for VmConfigVisitor {
    type Value = VmConfig;

    #[inline]
    fn expecting(&self, formatter: &mut Formatter<'_>) -> FmtResult {
        formatter.write_str("struct VmConfig")
    }

    #[inline]
    fn visit_map<V>(self, mut map: V) -> StdResult<VmConfig, V::Error>
    where
        V: MapAccess<'de>,
    {
        let mut res = VmConfig::default();
        let mut net: Vec<VmNetIface> = Vec::new();
        let mut disks: Vec<VmDisk> = Vec::new();

        let re_periph = Regex::new(RE_PERIPH_PATTERN).map_err(|err| {
            DeError::custom(format!(
                "Could not build the periphery regular expression: {err}"
            ))
        })?;

        while let Some(key) = map.next_key::<String>()? {
            let raw_value = map.next_value::<JsonValue>()?;

            if let Some(caps) = re_periph.captures(&key) {
                let p_type = caps
                    .name("type")
                    .ok_or_else(|| {
                        DeError::custom(format!(
                            "proxmoxy: regex_periph for {key:?}: no 'type' in {caps:?}"
                        ))
                    })?
                    .as_str();
                let p_idx = caps
                    .name("idx")
                    .ok_or_else(|| {
                        DeError::custom(format!(
                            "proxmoxy: regex_periph for {key:?}: no 'idx' in {caps:?}"
                        ))
                    })?
                    .as_str();
                let idx: u32 = p_idx.parse().map_err(|err| {
                    DeError::custom(format!(
                        "proxmoxy: regex_periph for {key:?}: bad idx {p_idx:?}: {err}"
                    ))
                })?;

                if let JsonValue::String(ref contents) = raw_value {
                    if p_type == "net" {
                        net.push(VmNetIface::Virtio(idx, contents.clone()));
                    } else {
                        disks.push(
                            parse_disk(
                                VmDiskType::from_str(p_type).map_err(|err| {
                                    DeError::custom(format!(
                                        "proxmoxy internal error: {key}: {err}"
                                    ))
                                })?,
                                idx,
                                contents,
                            )
                            .map_err(|err| {
                                DeError::custom(format!("Could not parse {key}: {err}"))
                            })?,
                        );
                    }
                } else {
                    return Err(DeError::custom(format!(
                        "The {key} element is not a string: {raw_value:?}"
                    )));
                }
            } else {
                match key.as_str() {
                    "digest" => {
                        if let JsonValue::String(value) = raw_value {
                            res = VmConfig {
                                digest: value,
                                ..res
                            };
                        } else {
                            return Err(DeError::custom(format!(
                                "unexpected 'digest' value: {raw_value:?}"
                            )));
                        }
                    }
                    _ => (),
                }
            }
        }
        Ok(VmConfig { net, disks, ..res })
    }
}

impl<'de> Deserialize<'de> for VmConfig {
    #[inline]
    fn deserialize<D>(deserializer: D) -> StdResult<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        deserializer.deserialize_map(VmConfigVisitor)
    }
}
