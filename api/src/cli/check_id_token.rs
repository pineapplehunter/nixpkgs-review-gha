use anyhow::{Context, anyhow};
use clap::Args;

use crate::github::oidc::IdTokenVerifier;

#[derive(Debug, Args)]
pub struct CheckIdTokenCommand {
    #[arg(long)]
    oidc_client_id: String,

    token: String,
}

impl CheckIdTokenCommand {
    pub async fn invoke(self) -> anyhow::Result<()> {
        let id_token_verifier = IdTokenVerifier::new(self.oidc_client_id.clone())
            .await
            .context("failed to create IdTokenVerifier")?;

        let claims = id_token_verifier
            .verify(&self.token)
            .map_err(|err| anyhow!("invalid token: {err}"))?;

        serde_json::to_writer_pretty(std::io::stdout(), &claims)?;

        Ok(())
    }
}
