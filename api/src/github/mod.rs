use serde::{Deserialize, Serialize};

pub mod oidc;

const USER_AGENT: &str = concat!(
    env!("CARGO_PKG_NAME"),
    " ",
    env!("CARGO_PKG_VERSION"),
    " (https://github.com/Defelo/nixpkgs-review-gha)"
);

pub async fn post_nixpkgs_comment(token: &str, pr: &str, body: &str) -> anyhow::Result<String> {
    #[derive(Serialize)]
    struct Request<'a> {
        body: &'a str,
    }

    #[derive(Deserialize)]
    struct Response {
        html_url: String,
    }

    Ok(make_http_client()
        .post(format!(
            "https://api.github.com/repos/NixOS/nixpkgs/issues/{pr}/comments"
        ))
        .bearer_auth(token)
        .json(&Request { body })
        .send()
        .await?
        .error_for_status()?
        .json::<Response>()
        .await?
        .html_url)
}

#[derive(Debug, Deserialize)]
pub struct User {
    pub login: String,
    pub id: u64,
}

pub async fn get_self(token: &str) -> anyhow::Result<User> {
    Ok(make_http_client()
        .get("https://api.github.com/user")
        .bearer_auth(token)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?)
}

fn make_http_client() -> reqwest::Client {
    reqwest::Client::builder()
        .user_agent(USER_AGENT)
        .build()
        .unwrap()
}

#[cfg(test)]
mod tests {
    #[test]
    fn make_http_client() {
        super::make_http_client();
    }
}
