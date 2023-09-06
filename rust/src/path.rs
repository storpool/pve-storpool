//! Build a query path for a Proxmox VE API request.
// SPDX-FileCopyrightText: StorPool <support@storpool.com>
// SPDX-License-Identifier: BSD-2-Clause

use std::fmt::Debug;

use anyhow::Context;
use serde::Deserialize;

use crate::defs::{Error, JsonValue, Result};
use crate::types::{NameSubdir, NodeSummary, Storage, Subdir, VmConfig, VmSummary};

/// An API request's query path built incrementally.
#[allow(clippy::module_name_repetitions)]
pub trait PathStop: Debug {
    /// The type returned by the API request.
    type ResultType;

    /// A short human-readable name for the API endpoint.
    fn desc() -> &'static str;

    /// Get the strings to be joined by slash characters to build the query path.
    fn parts(&self) -> &[String];

    /// Parse the raw JSON data returned by Proxmox VE into a Rust object.
    ///
    /// # Errors
    ///
    /// [`Error::Api`] on parse failure.
    fn from_json(raw: JsonValue) -> Result<Self::ResultType>;
}

/// A query path builder that does not have its own identifier.
#[allow(clippy::module_name_repetitions)]
pub trait PathStopPure: PathStop {
    /// Build our query path based on the one of the parent.
    fn from_parts(parts: Vec<String>) -> Self;
}

/// A query path builder that has its own identifier (usually a string).
#[allow(clippy::module_name_repetitions)]
pub trait PathStopId<T>: PathStop {
    /// Build our query path based on the one of the parent and a value for the identifier.
    fn from_parts_with_id(parts: Vec<String>, id: T) -> Self;
}

/// A generic JSON-to-Rust-object deserializer for objects returned by the API.
///
/// # Errors
///
/// [`Error::Api`] if the JSON data cannot be deserialized.
fn gen_from_json<PS>(raw: JsonValue) -> Result<PS::ResultType>
where
    PS: PathStop,
    for<'de> <PS as PathStop>::ResultType: Deserialize<'de>,
{
    serde_json::from_value(raw)
        .with_context(|| format!("Could not parse deserialize the {desc}", desc = PS::desc()))
        .map_err(Error::Api)
}

/// Generate the base [`PathStop`] implementation for a class.
macro_rules! path_stop_base {
    ( $class:ident, $result_type:ty, $desc:literal ) => {
        impl PathStop for $class {
            type ResultType = $result_type;

            #[inline]
            #[must_use]
            fn desc() -> &'static str {
                $desc
            }

            #[inline]
            #[must_use]
            fn parts(&self) -> &[String] {
                &self.parts
            }

            /// Deserialize a JSON raw value into a Rust object.
            ///
            /// # Errors
            ///
            /// Propagates an [`Error::Api`] result from `gen_from_json()` on deserialization failure.
            #[inline]
            fn from_json(raw: JsonValue) -> Result<Self::ResultType> {
                gen_from_json::<Self>(raw)
            }
        }
    };
}

/// Generate the [`PathStopPure`] implementation for a class.
macro_rules! path_stop {
    ( $class:ident, $result_type:ty, $desc:literal, $part:literal ) => {
        path_stop_base!($class, $result_type, $desc);

        impl PathStopPure for $class {
            #[inline]
            #[must_use]
            fn from_parts(mut parts: Vec<String>) -> Self {
                parts.push($part.to_owned());
                Self { parts }
            }
        }
    };

    ( $class:ident, $result_type:ty, $desc:literal ) => {
        path_stop_base!($class, $result_type, $desc);

        impl PathStopPure for $class {
            #[inline]
            #[must_use]
            fn from_parts(parts: Vec<String>) -> Self {
                Self { parts }
            }
        }
    };
}

/// Generate a class that implements [`PathStopPure`] along with its definition.
macro_rules! path_stop_impl {
    ( $class:ident, $result_type:ty, $desc:literal, $part:literal ) => {
        #[derive(Debug, Clone)]
        pub struct $class {
            parts: Vec<String>,
        }

        path_stop!($class, $result_type, $desc, $part);
    };

    ( $class:ident, $result_type:ty, $desc:literal ) => {
        #[derive(Debug, Clone)]
        pub struct $class {
            parts: Vec<String>,
        }

        path_stop!($class, $result_type, $desc);
    };
}

/// Generate the [`PathStopId`] implementation for a class.
macro_rules! path_stop_id {
    ( $class:ident, $result_type:ty, $desc:literal, $id_field:ident, $id_type:ty ) => {
        path_stop_base!($class, $result_type, $desc);

        impl PathStopId<$id_type> for $class {
            #[inline]
            #[must_use]
            fn from_parts_with_id(mut parts: Vec<String>, id: $id_type) -> Self {
                parts.push(id.to_string());
                Self {
                    $id_field: id,
                    parts,
                }
            }
        }
    };

    ( $class:ident, $result_type:ty, $desc:literal, $id_field:ident ) => {
        path_stop_base!($class, $result_type, $desc);

        impl PathStopId<&str> for $class {
            #[inline]
            #[must_use]
            fn from_parts_with_id(mut parts: Vec<String>, id: &str) -> Self {
                parts.push(id.to_owned());
                Self {
                    $id_field: id.to_owned(),
                    parts,
                }
            }
        }
    };
}

/// Generate a class that implements [`PathStopId`] along with its definition.
macro_rules! path_stop_id_impl {
    ( $class:ident, $result_type:ty, $desc:literal, $id_field:ident, $id_type:ty ) => {
        #[derive(Debug, Clone)]
        pub struct $class {
            $id_field: $id_type,
            parts: Vec<String>,
        }

        impl $class {
            #[inline]
            #[must_use]
            pub const fn id(&self) -> $id_type {
                self.$id_field
            }
        }

        path_stop_id!($class, $result_type, $desc, $id_field, $id_type);
    };

    ( $class:ident, $result_type:ty, $desc:literal, $id_field:ident ) => {
        #[derive(Debug, Clone)]
        pub struct $class {
            $id_field: String,
            parts: Vec<String>,
        }

        impl $class {
            #[inline]
            #[must_use]
            pub fn id(&self) -> &str {
                &self.$id_field
            }
        }

        path_stop_id!($class, $result_type, $desc, $id_field);
    };
}

path_stop_impl!(PathStorage, Vec<Storage>, "storage definitions", "storage");

path_stop_impl!(
    PathNNVVConfig,
    VmConfig,
    "configuration of a virtual machine",
    "config"
);

path_stop_id_impl!(PathNNVVm, Vec<Subdir>, "virtual machine", id, u32);

impl PathNNVVm {
    #[inline]
    #[must_use]
    pub fn config(self) -> PathNNVVConfig {
        PathNNVVConfig::from_parts(self.parts)
    }
}

path_stop_impl!(
    PathNNVms,
    Vec<VmSummary>,
    "virtual machines on a node",
    "qemu"
);

impl PathNNVms {
    #[inline]
    #[must_use]
    pub fn id(self, vmid: u32) -> PathNNVVm {
        PathNNVVm::from_parts_with_id(self.parts, vmid)
    }
}

path_stop_id_impl!(PathNNode, Vec<NameSubdir>, "single cluster node", id);

impl PathNNode {
    #[inline]
    #[must_use]
    pub fn qemu(self) -> PathNNVms {
        PathNNVms::from_parts(self.parts)
    }
}

path_stop_impl!(PathNodes, Vec<NodeSummary>, "cluster nodes", "nodes");

impl PathNodes {
    #[inline]
    #[must_use]
    pub fn id(self, name: &str) -> PathNNode {
        PathNNode::from_parts_with_id(self.parts, name)
    }
}

path_stop_impl!(PathTop, Vec<Subdir>, "top-level API data");

impl PathTop {
    #[inline]
    #[must_use]
    pub fn storage(self) -> PathStorage {
        PathStorage::from_parts(self.parts)
    }

    #[inline]
    #[must_use]
    pub fn nodes(self) -> PathNodes {
        PathNodes::from_parts(self.parts)
    }
}
