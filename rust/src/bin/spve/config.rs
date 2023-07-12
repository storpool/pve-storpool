//! Parse the configuration files for the spve tool.

use std::collections::HashMap;
use std::fs;
use std::path::Path;

use anyhow::{anyhow, Context};
use serde::Deserialize;
use xdg::BaseDirectories;

use proxmoxy::{Auth as PmAuth, BackendConfig, Proxmoxy};

use crate::defs::{Error, Result};

/// Token authentication data for the Proxmox VE API.
#[derive(Debug, Clone, Deserialize)]
pub struct AuthToken {
    /// The token name.
    pub id: String,

    /// The token value.
    pub value: String,
}

/// Cluster authentication data for the Proxmox VE API.
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "auth_type")]
pub enum AuthCluster {
    /// Authenticate using an API token.
    #[serde(rename = "token")]
    Token(AuthToken),
}

/// Authentication data for the Proxmox VE clusters.
#[derive(Debug, Deserialize)]
pub struct AuthSnippet {
    /// Authentication data for each cluster.
    pub clusters: HashMap<String, AuthCluster>,
}

/// Default settings if not overridden at each invocation.
#[derive(Debug, Deserialize)]
pub struct SpveDefaults {
    /// The cluster name to manage.
    pub cluster: String,
}

/// The way in which to connect to the Proxmox VE API.
#[derive(Debug, Clone, Deserialize)]
pub enum ApiMode {
    /// Use the JSON-over-HTTPS interface.
    #[serde(rename = "https")]
    Https,
}

/// General configuration settings for a Proxmox VE cluster managed by the spve tool.
#[derive(Debug, Clone, Deserialize)]
pub struct SpveClusterSnippet {
    /// How to connect to the cluster's API.
    api_mode: ApiMode,

    /// Where the cluster's API is located.
    url: String,
}

/// General configuration settings for the spve tool.
#[derive(Debug, Deserialize)]
pub struct SpveSnippet {
    /// Some default values.
    pub defaults: SpveDefaults,

    /// Per-cluster configuration settings.
    pub clusters: HashMap<String, SpveClusterSnippet>,
}

/// The format of the `spve.toml` global configuration file.
#[derive(Debug, Deserialize)]
pub struct GlobalSnippet {
    /// General settings for the spve tool.
    pub spve: SpveSnippet,
}

/// The aggregated information about the Proxmox VE cluster to manage.
#[derive(Debug)]
pub struct Cluster {
    /// The name of the cluster.
    pub name: String,

    /// The authentication information for the cluster.
    pub auth: AuthCluster,

    /// The API endpoint information for the cluster.
    pub spve: SpveClusterSnippet,
}

/// Runtime configuration for the `spve` tool.
#[derive(Debug)]
pub struct Config {
    /// How to authenticate to the various clusters' APIs.
    pub auth: AuthSnippet,

    /// The general configuration settings.
    pub global: SpveSnippet,

    /// The selected cluster.
    pub cluster: Cluster,
}

impl Config {
    /// Build a proxy for sending requests to the Proxmox VE API using this cluster configuration.
    ///
    /// # Errors
    ///
    /// [`Error::Api`] if the `proxmoxy` crate's methods failed.
    pub fn get_proxmox_api(&self) -> Result<Proxmoxy> {
        match self.cluster.spve.api_mode {
            ApiMode::Https => match self.cluster.auth {
                AuthCluster::Token(ref token) => {
                    let cfg = BackendConfig {
                        auth: PmAuth::Token(token.id.clone(), token.value.clone()),
                        url: self.cluster.spve.url.clone(),
                    };
                    Proxmoxy::get_https_api(cfg).map_err(Error::Api)
                }
            },
        }
    }
}

/// Parse a single configuration file with format version 0.1.
///
/// # Errors
///
/// [`Error::ConfigRead`] if the configuration file could not be read.
/// [`Error::ConfigParse`] if the configuration file's contents could not be parsed.
fn read_format_version(path: &Path) -> Result<String> {
    let contents = fs::read_to_string(path).map_err(Error::ConfigRead)?;
    let fver = typed_format_version::get_version_from_str(&contents, toml::from_str)
        .with_context(|| {
            format!(
                "Could not parse the format version of the {path} file",
                path = path.display()
            )
        })
        .map_err(Error::ConfigParse)?;
    if fver.major() != 0 {
        return Err(Error::ConfigParse(anyhow!(
            "Unsupported format version {major}.{minor} for the {path} file",
            major = fver.major(),
            minor = fver.minor(),
            path = path.display(),
        )));
    }
    Ok(contents)
}

/// Find the spve configuration files in the XDG directories, parse them.
///
/// # Errors
///
/// [`Error::ConfigEnv`] if something goes wrong during initialization.
/// [`Error::ConfigFileMissing`] if any of the config files could not be found.
pub fn parse(cluster: Option<&str>) -> Result<Config> {
    let dirs = BaseDirectories::new()
        .context("Could not initialize the XDG base directories parser")
        .map_err(Error::ConfigEnv)?;

    let global_path = dirs
        .find_config_file("spve/spve.toml")
        .ok_or_else(|| Error::ConfigFileMissing("spve/spve.toml".to_owned()))?;
    let global: GlobalSnippet =
        toml::from_str::<GlobalSnippet>(&read_format_version(&global_path)?)
            .with_context(|| {
                format!(
                    "Could not parse the {global_path} file",
                    global_path = global_path.display()
                )
            })
            .map_err(Error::ConfigParse)?;

    let cl_name = cluster.unwrap_or(&global.spve.defaults.cluster).to_owned();
    let cl_global = (*(global.spve.clusters.get(&cl_name).ok_or_else(|| {
        Error::ConfigParse(anyhow!(
            "No {cl_name} in the {global_path} config file",
            global_path = global_path.display()
        ))
    })?))
    .clone();

    let auth_path = dirs
        .find_config_file("spve/auth.toml")
        .ok_or_else(|| Error::ConfigFileMissing("spve/auth.toml".to_owned()))?;
    let auth: AuthSnippet = toml::from_str::<AuthSnippet>(&read_format_version(&auth_path)?)
        .with_context(|| {
            format!(
                "Could not parse the {auth_path} file",
                auth_path = auth_path.display()
            )
        })
        .map_err(Error::ConfigParse)?;

    let cl_auth = (*(auth.clusters.get(&cl_name).ok_or_else(|| {
        Error::ConfigParse(anyhow!(
            "No {cl_name} in the {auth_path} config file",
            auth_path = auth_path.display()
        ))
    })?))
    .clone();

    Ok(Config {
        auth,
        global: global.spve,
        cluster: Cluster {
            name: cl_name,
            auth: cl_auth,
            spve: cl_global,
        },
    })
}
