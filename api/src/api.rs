use std::{fmt::Display, sync::Arc};

use anyhow::{Context, anyhow};
use axum::{
    Json, Router,
    response::{IntoResponse, Redirect, Response},
    routing,
};
use axum_extra::{
    TypedHeader,
    headers::{Authorization, authorization::Bearer},
};
use listenfd::ListenFd;
use reqwest::StatusCode;
use tokio::net::UnixListener;
use tracing::debug;

use crate::{
    github::{oidc::IdTokenVerifier, post_nixpkgs_comment},
    nixpkgs_review::{Report, ReportMarkdownRenderer},
};

pub struct State {
    pub oidc_client_id: String,
    pub id_token_verifier: IdTokenVerifier,
    pub report_markdown_renderer: ReportMarkdownRenderer,
    pub github_token: String,
}

pub async fn serve(state: State) -> anyhow::Result<()> {
    let mut listenfd = ListenFd::from_env();
    let listener = listenfd
        .take_unix_listener(0)?
        .ok_or_else(|| anyhow!("Expected to be passed a unix socket"))?;
    listener.set_nonblocking(true)?;
    let listener = UnixListener::from_std(listener)?;

    let router = Router::new()
        .route("/", routing::get(index))
        .route("/oidc_client_id", routing::get(get_client_id))
        .route("/submit_report", routing::post(submit_report))
        .with_state(Arc::new(state));

    axum::serve(listener, router.into_make_service()).await?;

    Ok(())
}

async fn index() -> Redirect {
    Redirect::temporary("https://github.com/Defelo/nixpkgs-review-gha")
}

async fn get_client_id(state: axum::extract::State<Arc<State>>) -> String {
    state.oidc_client_id.clone()
}

async fn submit_report(
    state: axum::extract::State<Arc<State>>,
    auth: TypedHeader<Authorization<Bearer>>,
    report: Json<Report>,
) -> Result<Response, Response> {
    let claims = state
        .id_token_verifier
        .verify(auth.token())
        .map_err(|err| (StatusCode::UNAUTHORIZED, format!("invalid token: {err}")).into_response())
        .inspect_err(|_| debug!(token = auth.token(), "unauthorized report submit request"))?;

    debug!(?claims, "report submitted");

    let rendered = state.report_markdown_renderer.render(&report, &claims);

    let comment_url = post_nixpkgs_comment(&state.github_token, &report.pr, &rendered)
        .await
        .with_context(|| format!("failed to post comment on pr #{}", report.pr))
        .map_err(internal_server_error)?;

    debug!(comment_url, "comment created");

    Ok(comment_url.into_response())
}

fn internal_server_error(err: impl Display) -> Response {
    tracing::error!("{err}");
    (StatusCode::INTERNAL_SERVER_ERROR, "internal server error").into_response()
}
