//! Unit-style tests for the Proxmox VE API bindings.

use std::collections::HashMap;
use std::env::{self, VarError as EnvError};
use std::fs;

use anyhow::{bail, Context, Result};
use serde::Deserialize;
use tracing::info;
use tracing_test::traced_test;

use crate::defs::{Auth, BackendConfig};
use crate::path::PathStop;
use crate::Proxmoxy;

#[derive(Debug, Deserialize)]
struct AuthFileToken {
    id: String,
    value: String,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "auth_type")]
enum AuthFileCluster {
    #[serde(rename = "token")]
    Token(AuthFileToken),
}

#[derive(Debug, Deserialize)]
struct AuthFileTop {
    clusters: HashMap<String, AuthFileCluster>,
}

#[derive(Debug, Deserialize)]
struct CfgFileDefaults {
    cluster: String,
}

#[derive(Debug, Deserialize)]
struct CfgFileCluster {
    api_mode: String,
    url: String,
}

#[derive(Debug, Deserialize)]
struct CfgFileSpve {
    defaults: CfgFileDefaults,
    clusters: HashMap<String, CfgFileCluster>,
}

#[derive(Debug, Deserialize)]
struct CfgFileTop {
    spve: CfgFileSpve,
}

#[traced_test]
#[test]
fn test_create_paths() -> Result<()> {
    println!();

    let api_token = Auth::Token("username".to_owned(), "password".to_owned());
    let api_cfg = BackendConfig {
        auth: api_token,
        url: "http://127.0.0.1:6".to_owned(),
    };
    let api = Proxmoxy::get_https_api(api_cfg)?;

    info!("{}", api.path().parts().join("/"));

    info!("{}", api.path().nodes().parts().join("/"));
    info!("{}", api.path().nodes().id("local").parts().join("/"));
    info!(
        "{}",
        api.path().nodes().id("local").qemu().parts().join("/")
    );
    info!(
        "{}",
        api.path()
            .nodes()
            .id("local")
            .qemu()
            .id(616)
            .parts()
            .join("/")
    );
    info!(
        "{}",
        api.path()
            .nodes()
            .id("local")
            .qemu()
            .id(616)
            .config()
            .parts()
            .join("/")
    );

    info!("{}", api.path().storage().parts().join("/"));

    Ok(())
}

#[traced_test]
#[tokio::test]
async fn test_api_queries() -> Result<()> {
    println!();

    let (cl_name, cl_url) = {
        let cfg_path = match env::var("TEST_PROXMOX_CFG") {
            Ok(value) => value,
            Err(EnvError::NotPresent) => {
                info!("skipped: no TEST_PROXMOX_CFG");
                return Ok(());
            }
            Err(err) => {
                bail!("Could not parse the TEST_PROXMOX_CFG environment variable: {err}");
            }
        };
        info!(cfg_path);
        let contents =
            fs::read_to_string(&cfg_path).with_context(|| format!("Could not read {cfg_path}"))?;
        let mut cfg_top = toml::from_str::<CfgFileTop>(&contents)
            .with_context(|| format!("Could not parse {cfg_path}"))?;

        let cl_name = cfg_top.spve.defaults.cluster;
        let cl_data = cfg_top
            .spve
            .clusters
            .remove(&cl_name)
            .with_context(|| format!("No '{cl_name}' entry in {cfg_path}"))?;
        if cl_data.api_mode != "https" {
            bail!(
                "Expected api_mode = 'https' for '{cl_name}' in {cfg_path}, got {api_mode}",
                api_mode = cl_data.api_mode
            );
        }
        (cl_name, cl_data.url)
    };

    let auth_token = {
        let auth_path = match env::var("TEST_PROXMOX_AUTH") {
            Ok(value) => value,
            Err(EnvError::NotPresent) => {
                info!("skipped: no TEST_PROXMOX_AUTH");
                return Ok(());
            }
            Err(err) => {
                bail!("Could not parse TEST_PROXMOX_AUTH: {err}");
            }
        };
        info!(auth_path);
        let contents = fs::read_to_string(&auth_path)
            .with_context(|| format!("Could not read {auth_path}"))?;
        let mut auth_top = toml::from_str::<AuthFileTop>(&contents)
            .with_context(|| format!("Could not parse {auth_path}"))?;
        let cl_data = auth_top
            .clusters
            .remove(&cl_name)
            .with_context(|| format!("No '{cl_name}' entry in {auth_path}"))?;
        match cl_data {
            AuthFileCluster::Token(AuthFileToken { id, value }) => {
                Auth::Token(id.to_owned(), value.to_owned())
            }
        }
    };

    let api = Proxmoxy::get_https_api(BackendConfig {
        auth: auth_token,
        url: cl_url,
    })?;

    info!(
        "top-level subdirs count: {count}",
        count = api.get(api.path()).await.context("get /")?.len()
    );

    info!(
        "storage count: {count}",
        count = api
            .get(api.path().storage())
            .await
            .context("get storage")?
            .len()
    );

    let nodes = api.get(api.path().nodes()).await.context("get nodes")?;
    info!("nodes count: {count}", count = nodes.len());

    for node in nodes.into_iter() {
        let node_name = node.node();
        let node_path = api.path().nodes().id(node_name);
        info!(
            "node {node_name} subdirs count: {count}",
            count = api
                .get(node_path.clone())
                .await
                .with_context(|| format!("get node {node_name}"))?
                .len()
        );

        let qemu_path = node_path.qemu();
        let vms = api
            .get(qemu_path.clone())
            .await
            .with_context(|| format!("get node {node_name} qemu"))?;
        info!("node {node_name}: VMs count: {count}", count = vms.len());

        for vm in vms.into_iter() {
            let vmid = vm.vmid();
            let vm_path = qemu_path.clone().id(vmid);
            info!(
                "node {node_name}: vm {vmid} subdirs count: {count}",
                count = api
                    .get(vm_path.clone())
                    .await
                    .with_context(|| format!("get node {node_name} vm {vmid}"))?
                    .len()
            );

            let vm_cfg = api
                .get(vm_path.config())
                .await
                .with_context(|| format!("get node {node_name} vm {vmid} config"))?;
            info!(
                "node {node_name}: vm {vmid}: disks count: {count}",
                count = vm_cfg.disks().len()
            );
        }
    }

    Ok(())
}
