//! Parse the spve command-line - subcommands, options, etc.
// SPDX-FileCopyrightText: StorPool <support@storpool.com>
// SPDX-License-Identifier: BSD-2-Clause

use std::io;

use anyhow::Context;
use clap::{Parser, Subcommand};
use tracing::Level;
use tracing_subscriber::FmtSubscriber;

use crate::defs::{Error, Result};

/// The action requested by the command-line subcommands.
#[derive(Debug)]
pub enum Mode {
    /// Check the configuration of `StorPool`-backed VM disks.
    CheckVms {
        /// Which cluster to connect to, if not the default one.
        cluster: Option<String>,
    },
}

/// Subcommands for the `check` top-level command.
#[derive(Debug, Subcommand)]
enum CliCheckCommand {
    /// Check the configuration of `StorPool`-backed VM disks.
    Vms,
}

/// Top-level commands.
#[derive(Debug, Subcommand)]
enum CliCommand {
    /// Check various Proxmox VE and StorPool configuration settings.
    Check {
        /// What to check, exactly.
        #[clap(subcommand)]
        subc: CliCheckCommand,
    },
}

/// The top-level command-line parser.
#[derive(Debug, Parser)]
#[clap(about("manage StorPool-backed Proxmox VE storage"), author, version)]
struct Cli {
    /// Which cluster to connect to, if not the default one.
    #[clap(short, long)]
    cluster: Option<String>,

    /// Verbose operation; display diagnostic output.
    #[clap(short, long)]
    verbose: bool,

    /// Display even more diagnostic output; implies "--verbose".
    #[clap(long)]
    debug: bool,

    /// What to do, what to do...
    #[clap(subcommand)]
    command: CliCommand,
}

/// Initialize the `tracing` crate's facilities.
///
/// Create a tracing subscriber, set the level according to the "--verbose" and
/// "--debug" command-line options.
///
/// # Errors
///
/// [`Error::ConfigEnv`] if something goes wrong.
fn setup_tracing(cli: &Cli) -> Result<()> {
    let formatter = FmtSubscriber::builder()
        .with_max_level(if cli.debug {
            Level::TRACE
        } else if cli.verbose {
            Level::DEBUG
        } else {
            Level::INFO
        })
        .with_writer(io::stderr)
        .finish();
    tracing::subscriber::set_global_default(formatter)
        .context("Could not initialize the tracing subscriber")
        .map_err(Error::ConfigEnv)?;
    Ok(())
}

/// Parse the command-line arguments: subcommands, options, etc.
///
/// # Errors
///
/// [`Error::Internal`] is all we can do for the present.
pub fn parse() -> Result<Mode> {
    let cli = Cli::try_parse()
        .context("Could not parse the command-line parameters")
        .map_err(Error::Invoke)?;
    setup_tracing(&cli)?;
    match cli.command {
        CliCommand::Check { subc } => match subc {
            CliCheckCommand::Vms => Ok(Mode::CheckVms {
                cluster: cli.cluster,
            }),
        },
    }
}
