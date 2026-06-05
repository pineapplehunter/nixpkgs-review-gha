use clap::{Parser, Subcommand};
use tracing::level_filters::LevelFilter;
use tracing_subscriber::EnvFilter;

use crate::cli::{check_id_token::CheckIdTokenCommand, serve::ServeCommand};

mod check_id_token;
mod serve;

pub async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::builder()
                .with_default_directive(LevelFilter::INFO.into())
                .from_env_lossy(),
        )
        .init();

    match cli.command {
        Command::Serve(cmd) => cmd.invoke().await,
        Command::CheckIdToken(cmd) => cmd.invoke().await,
    }
}

#[derive(Debug, Parser)]
#[command(version)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Start the HTTP API server
    Serve(ServeCommand),
    /// Verify a GitHub Actions OIDC ID token and print its claims.
    CheckIdToken(CheckIdTokenCommand),
}
