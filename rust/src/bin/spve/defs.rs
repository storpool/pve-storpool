//! Common definitions for the spve command-line tool.
// SPDX-FileCopyrightText: StorPool <support@storpool.com>
// SPDX-License-Identifier: BSD-2-Clause

use std::io::Error as IoError;
use std::result::Result as StdResult;

use anyhow::Error as AnyError;
use thiserror::Error;

use proxmoxy::defs::Error as PmError;

/// An error that occurred during the spve tool's operation.
#[derive(Debug, Error)]
#[non_exhaustive]
pub enum Error {
    /// A request to the Proxmox VE API failed.
    #[error("Proxmox VE API request failed")]
    Api(#[source] PmError),

    /// Something went wrong while examining the configuration.
    #[error("Could not examine the spve execution environment")]
    ConfigEnv(#[source] AnyError),

    /// A required configuration file was missing.
    #[error("Could not find the {0} spve configuration file")]
    ConfigFileMissing(String),

    /// Could not parse a configuration file's contents.
    #[error("Could not parse the spve configuration")]
    ConfigParse(#[source] AnyError),

    /// Could not read the configuration file's contents.
    #[error("Could not read a configuration file")]
    ConfigRead(#[source] IoError),

    /// Something went really, really wrong...
    #[error("spve internal error: {0}")]
    Internal(String),

    /// The spve tool was invoked incorrectly.
    #[error("spve invocation error")]
    Invoke(#[source] AnyError),
}

/// A helper type for functions that may return an [`enum@Error`] value.
pub type Result<T> = StdResult<T, Error>;
