//! Parse various Proxmox VE configuration and status strings.

use std::collections::HashMap;
use std::iter;

use anyhow::Context;
use itertools;
use nom::{
    character::complete::{char, none_of, one_of},
    combinator::all_consuming,
    error::Error as NomError,
    multi::many0,
    sequence::{preceded, separated_pair, tuple},
    Err as NomErr, IResult,
};

use crate::defs::{Error, Result};

/// Parse a Proxmox VE general object identifier string.
fn p_proxmox_id(input: &str) -> IResult<&str, String> {
    let (r_input, (first, rest)) = tuple((
        one_of("abcdefghijklmnopqrstuvwxyz0123456789"),
        many0(one_of("abcdefghijklmnopqrstuvwxyz0123456789_-")),
    ))(input)?;
    Ok((
        r_input,
        itertools::chain(iter::once(first), rest.into_iter()).collect(),
    ))
}

/// Parse a Proxmox VE storage-specific volume ID string.
fn p_vol_id(input: &str) -> IResult<&str, String> {
    let (r_input, chars) = many0(none_of(":,"))(input)?;
    Ok((r_input, chars.into_iter().collect()))
}

/// Parse a comma-separated list of disk options into a map.
fn p_disk_options(input: &str) -> IResult<&str, HashMap<String, String>> {
    let (r_input, pairs) = many0(preceded(
        char(','),
        separated_pair(p_proxmox_id, char('='), many0(none_of(","))),
    ))(input)?;
    Ok((
        r_input,
        pairs
            .into_iter()
            .map(|(name, value)| (name, value.into_iter().collect()))
            .collect(),
    ))
}

/// Parse a Proxmox VE disk description as found in the VM configuration.
fn p_disk(input: &str) -> IResult<&str, (String, String, HashMap<String, String>)> {
    let (r_input, ((storage, volid), options)) = all_consuming(tuple((
        separated_pair(p_proxmox_id, char(':'), p_vol_id),
        p_disk_options,
    )))(input)?;
    Ok((r_input, (storage, volid, options)))
}

/// Parse a Proxmox VE disk description as found in the VM configuration.
///
/// # Errors
///
/// [`Error::Api`] on parse failure.
#[inline]
pub fn disk(input: &str) -> Result<(String, String, HashMap<String, String>)> {
    let (_, (storage, volid, options)) = p_disk(input)
        .map_err(NomErr::<NomError<&str>>::to_owned)
        .with_context(|| format!("Could not parse the {input:?} disk definition"))
        .map_err(Error::Api)?;
    Ok((storage, volid, options))
}
