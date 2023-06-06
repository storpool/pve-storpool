//! A command-line tool for managing StorPool-backed Proxmox VE storage.

use std::collections::HashMap;

use anyhow::{Context, Result as AnyResult};
use std::process::{ExitCode, Termination};
use tracing::{debug, warn};

use proxmoxy::types::{NodeStatus, Storage, VmDisk, VmDiskType};

mod cli;
mod config;
mod defs;

use crate::cli::Mode;
use crate::defs::{Error, Result};

/// The exit status of a main program's subcommand.
enum MainExit {
    /// Everything went fine.
    Ok,

    /// A 'check' subcommand found problems.
    CheckFailed,
}

impl Termination for MainExit {
    fn report(self) -> ExitCode {
        match self {
            Self::Ok => ExitCode::SUCCESS,
            Self::CheckFailed => ExitCode::FAILURE,
        }
    }
}

/// Check the configuration of a single disk for a VM.
fn check_vm_disk(disk_id: &str, disk: &VmDisk) -> bool {
    let mut problems: bool = false;

    #[allow(clippy::wildcard_enum_match_arm)]
    match disk.disk_type() {
        VmDiskType::Virtio => (),
        other => {
            warn!(
                "Disk type '{other}' instead of 'virtio' for {disk_id}",
                other = other.as_ref()
            );
            problems = true;
        }
    };

    match disk.options().get("cache") {
        None => (),
        Some(value) if value == "none" => (),
        Some(other) => {
            warn!("Expected 'cache=none' for {disk_id}, got '{other}'");
            problems = true;
        }
    };

    match disk.options().get("discard") {
        None => {
            warn!("No 'discard' defined for {disk_id}");
            problems = true;
        }
        Some(value) if value == "on" => (),
        Some(other) => {
            warn!("Expected 'discard=on' for {disk_id}, got '{other}'");
            problems = true;
        }
    };

    match disk.options().get("iothread") {
        None => {
            warn!("No 'iothread' defined for {disk_id}");
            problems = true;
        }
        Some(value) if value == "1" => (),
        Some(other) => {
            warn!("Expected 'iothread=1' for {disk_id}, got '{other}'");
            problems = true;
        }
    };

    problems
}
/// Check the `StorPool`-backed VM disks.
async fn cmd_check_vms(cluster: Option<String>) -> Result<MainExit> {
    let cfg = config::parse(cluster.as_deref())?;
    let api = cfg.get_proxmox_api()?;

    let storage: HashMap<String, Storage> = api
        .get(api.path().storage())
        .await
        .map_err(Error::Api)?
        .into_iter()
        .map(|store| (store.storage().to_owned(), store))
        .collect();
    debug!(
        "Got information about {count} storage(s)",
        count = storage.len()
    );
    for (name, store) in &storage {
        debug!(
            "- {name}: {storage_type}",
            storage_type = store.storage_type()
        );
    }

    let nodes = api.get(api.path().nodes()).await.map_err(Error::Api)?;
    debug!("Got information about {count} node(s)", count = nodes.len());

    let mut problems = false;
    for node in nodes {
        let name = node.node();
        if node.status() != NodeStatus::Online {
            debug!("Skipping the {name} node, not online");
            continue;
        }

        debug!("Looking for virtual machines at {name}");
        let path_vms = api.path().nodes().id(name).qemu();
        let vms = api.get(path_vms.clone()).await.map_err(Error::Api)?;
        debug!(
            "Got information about {count} VM(s) on node {name}",
            count = vms.len()
        );

        for vm in vms {
            let vmid = vm.vmid();
            if vmid < 100 {
                continue;
            }

            debug!("Looking for disks on VM {vmid}");
            let vmcfg = api
                .get(path_vms.clone().id(vmid).config())
                .await
                .map_err(Error::Api)?;
            for disk in vmcfg.disks().iter() {
                let disk_id = format!(
                    "the {disk_type}{idx} disk for VM {vmid}",
                    disk_type = disk.disk_type().as_ref(),
                    idx = disk.idx(),
                );
                match storage.get(disk.storage()) {
                    None => {
                        warn!(
                            "Invalid type {storage} for {disk_id}",
                            storage = disk.storage(),
                        );
                        problems = true;
                    }
                    Some(store) if store.storage_type() != "storpool" => {
                        continue;
                    }
                    Some(_) => {
                        problems = check_vm_disk(&disk_id, disk) || problems;
                    }
                }
            }
        }
    }

    if problems {
        Ok(MainExit::CheckFailed)
    } else {
        Ok(MainExit::Ok)
    }
}

#[tokio::main]
async fn main() -> AnyResult<MainExit> {
    match cli::parse().context("Could not parse the command-line arguments")? {
        Mode::CheckVms { cluster } => cmd_check_vms(cluster)
            .await
            .context("Could not check the VM configuration"),
    }
}
