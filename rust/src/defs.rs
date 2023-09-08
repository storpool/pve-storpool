//! Common definitions for the proxmoxy API bindings.
// SPDX-FileCopyrightText: StorPool <support@storpool.com>
// SPDX-License-Identifier: BSD-2-Clause

#![allow(clippy::pub_use)]

use core::fmt::Debug;
use std::result::Result as StdResult;

use anyhow::Error as AnyError;
use thiserror::Error;

pub use serde_json::Value as JsonValue;

/// An error that occurred while accessing the Proxmox VE API.
#[derive(Debug, Error)]
#[non_exhaustive]
pub enum Error {
    /// The Proxmox VE API returned an error.
    #[error("The Proxmox VE API returned an error")]
    Api(#[source] AnyError),

    /// Something went really, really wrong...
    #[error("proxmoxy internal error: {0}")]
    Internal(String),

    /// Could not send an HTTPS request.
    #[error("Could not send an HTTPS request to the Proxmox VE API")]
    Reqwest(#[source] AnyError),
}

/// A helper type for functions that may return an [`enum@Error`] value.
pub type Result<T> = StdResult<T, Error>;

/// How do we authenticate to the Proxmox VE API?
#[derive(Debug)]
#[non_exhaustive]
pub enum Auth {
    /// Token authentication: name (id), value.
    Token(String, String),
}

/// Configuration for the specified backend.
///
/// Note: any changes to this structure shall be considered breaking.
#[derive(Debug)]
#[allow(clippy::exhaustive_structs)]
pub struct BackendConfig {
    /// The authentication information for the Proxmox VE API.
    pub auth: Auth,

    /// The URL specifying where to send API requests.
    pub url: String,
}
