//! Access the Proxmox VE API via JSON-over-HTTPS.

use anyhow::{anyhow, Context};
use itertools::Itertools;
use reqwest::header::{self, HeaderMap, HeaderValue};
use reqwest::{Client, ClientBuilder};

use crate::defs::{Auth, BackendConfig, Error, JsonValue, Result};

/// Internal state for sending HTTPS requests to the Proxmox VE API.
#[derive(Debug)]
pub struct BackendData {
    /// The authentication information.
    _auth: Auth,

    /// The HTTP client used to send the requests.
    client: Client,

    /// The base API URL to use when sending requests.
    url: String,
}

impl BackendData {
    /// Prepare to send HTTPS requests to the Proxmox VE API.
    ///
    /// Create an HTTP client and prepare its authentication header.
    ///
    /// # Errors
    ///
    /// [`Error::Reqwest`] if the HTTP client could not be initialized.
    pub fn new(cfg: BackendConfig) -> Result<Self> {
        let client = {
            let headers = {
                let mut headers = HeaderMap::new();
                match cfg.auth {
                    Auth::Token(ref id, ref value) => {
                        let mut auth_hdr =
                            HeaderValue::try_from(format!("PVEAPIToken={id}={value}"))
                                .context("Could not build the HTTPS Authorization header")
                                .map_err(Error::Reqwest)?;
                        auth_hdr.set_sensitive(true);
                        headers.insert(header::AUTHORIZATION, auth_hdr);
                    }
                };
                headers
            };
            ClientBuilder::new()
                .danger_accept_invalid_certs(true)
                .default_headers(headers)
                .build()
                .context("Could not build the HTTPS client")
                .map_err(Error::Reqwest)?
        };
        Ok(Self {
            _auth: cfg.auth,
            client,
            url: cfg.url,
        })
    }

    /// Send an HTTPS GET request, return a JSON structure.
    ///
    /// # Errors
    ///
    /// [`Error::Reqwest`] if the request could not be built or sent at all.
    /// [`Error::Api`] if the API responds with an error or something unexpected.
    pub async fn get(&self, path: &str) -> Result<JsonValue> {
        let url = format!("{url}/api2/json/{path}", url = self.url);
        let req = self
            .client
            .get(&url)
            .build()
            .with_context(|| format!("Could not build a GET request for {url}"))
            .map_err(Error::Reqwest)?;
        let resp = self
            .client
            .execute(req)
            .await
            .with_context(|| format!("The GET request for {url} failed"))
            .map_err(Error::Reqwest)?
            .error_for_status()
            .with_context(|| format!("The GET request for {url} returned an error"))
            .map_err(Error::Api)?;

        let ctype = String::from_utf8(
            resp.headers()
                .get(header::CONTENT_TYPE)
                .with_context(|| {
                    format!("The GET request for {url} did not return a Content-Type header")
                })
                .map_err(Error::Api)?
                .as_ref()
                .to_vec(),
        )
        .with_context(|| {
            format!("The GET request for {url} did not return a parseable Content-Type header")
        })
        .map_err(Error::Api)?;
        if ctype != "application/json" && ctype != "application/json;charset=UTF-8" {
            return Err(Error::Api(anyhow!(
                "The GET request for {url} returned an unexpected Content-Type header: {ctype}"
            )));
        }

        let raw_bytes = resp
            .bytes()
            .await
            .with_context(|| {
                format!("Could not receive the full response to the GET request for {url}")
            })
            .map_err(Error::Api)?;
        let raw = serde_json::from_slice(&raw_bytes)
            .with_context(|| {
                format!("Could not decode the response to the GET request for {url} as valid JSON")
            })
            .map_err(Error::Api)?;
        #[allow(clippy::wildcard_enum_match_arm)]
        match raw {
            JsonValue::Object(mut top) => {
                let keys = top.keys().sorted().collect::<Vec<_>>();
                // if keys.len() != 1 || keys[0] != "data" {
                if *keys != ["data"] {
                    return Err(Error::Api(anyhow!(
                        "The GET request for {url} returned a weird object: {top:?}"
                    )));
                }
                top.remove("data")
                    .ok_or_else(|| Error::Internal(format!("'data' should be in {top:?}")))
            }
            other => Err(Error::Api(anyhow!(
                "The GET request for {url} returned something weird: {other:?}"
            ))),
        }
    }
}
