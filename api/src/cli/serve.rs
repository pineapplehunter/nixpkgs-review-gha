use std::path::{Path, PathBuf};

use anyhow::Context;
use clap::Args;
use tracing::info;

use crate::{
    api::{self, State},
    github::{get_self, oidc::IdTokenVerifier},
    nixpkgs_review::ReportMarkdownRenderer,
};

#[derive(Debug, Args)]
pub struct ServeCommand {
    #[arg(long)]
    oidc_client_id: String,

    #[arg(long)]
    github_token_file: PathBuf,
}

impl ServeCommand {
    pub async fn invoke(self) -> anyhow::Result<()> {
        let github_token = read_secret("github token", &self.github_token_file)?;

        let user = get_self(&github_token)
            .await
            .context("failed to get logged in github user")?;
        info!("Logged in as {} ({})", user.login, user.id);

        let id_token_verifier = IdTokenVerifier::new(self.oidc_client_id.clone())
            .await
            .context("failed to create IdTokenVerifier")?;
        let report_markdown_renderer = ReportMarkdownRenderer::new();

        let state = State {
            oidc_client_id: self.oidc_client_id,
            id_token_verifier,
            report_markdown_renderer,
            github_token,
        };

        info!("Starting HTTP server");
        api::serve(state)
            .await
            .context("failed to start HTTP server")
    }
}

fn read_secret(name: &str, path: &Path) -> anyhow::Result<String> {
    std::fs::read_to_string(path)
        .with_context(|| format!("failed to read {name} from {}", path.display()))
}
