//! A woefully incomplete set of API bindings for Proxmox VE.
//!
//! ```
//! # use std::error::Error;
//! #
//! # use proxmoxy::defs::{Auth, BackendConfig};
//! # use proxmoxy::Proxmoxy;
//! #
//! # async fn send_req() -> Result<(), Box<dyn Error>> {
//! let api_token = Auth::Token("jrl@pam".to_owned(), "mellon".to_owned());
//! let api_cfg = BackendConfig {
//!     auth: api_token,
//!     url: "https://example.com:8006".to_owned(),
//! };
//! let api = Proxmoxy::get_https_api(api_cfg)?;
//! let vm_cfg = api.get(api.path().nodes().id("example").qemu().id(616).config()).await?;
//! # Ok(())
//! # }
//! ```

#![allow(clippy::pub_use)]

use core::fmt::Debug;

use tracing::{debug, trace};

mod backend;

#[cfg(test)]
mod tests;

use crate::backend::https::BackendData as HttpsBackendData;
use crate::path::{PathStop, PathStopPure, PathTop};

pub mod defs;
pub mod parse;
pub mod path;
pub mod types;

pub use defs::{Auth, BackendConfig, Error, JsonValue, Result};

/// Backend-specific data (e.g. an HTTP client or SSH connection or something).
#[derive(Debug)]
enum BackendData {
    /// Use the JSON-over-HTTPS API.
    Https(HttpsBackendData),
}

/// Send requests to the Proxmox VE API.
///
/// This structure is supposed to mimic the hierarchy of the Proxmox VE API by
/// using members that correspond to the API's JSON schema.
#[derive(Debug)]
pub struct Proxmoxy {
    /// The selected backend for accessing the API.
    pm_backend: BackendData,
}

impl Proxmoxy {
    /// Prepare to access the Proxmox VE API using the JSON-over-HTTPS interface.
    ///
    /// # Errors
    ///
    /// Propagates [`Error::Reqwest`] and [`Error::Api`] errors from
    /// the HTTPS backend's initialization function.
    #[inline]
    pub fn get_https_api(cfg: BackendConfig) -> Result<Self> {
        Ok(Self {
            pm_backend: BackendData::Https(HttpsBackendData::new(cfg)?),
        })
    }

    /// Start building a query path for a Proxmox VE API request.
    #[inline]
    #[must_use]
    pub fn path(&self) -> PathTop {
        PathTop::from_parts(Vec::new())
    }

    /// Query the Proxmox VE API for a value.
    ///
    /// # Errors
    ///
    /// Propagates errors from the backend's `get()` method.
    /// Propagates errors from the query path's `from_json()` method.
    #[inline]
    pub async fn get<PS: PathStop + Send + Sync>(&self, path: PS) -> Result<PS::ResultType> {
        let query = path.parts().join("/");
        debug!(query);
        let raw = match self.pm_backend {
            BackendData::Https(ref data) => data.get(&query).await?,
        };
        trace!("{raw:?}");
        PS::from_json(raw)
    }
}
