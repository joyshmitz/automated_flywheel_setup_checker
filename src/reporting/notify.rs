//! Notification handlers (GitHub, Slack)

use anyhow::Result;
use reqwest::header::{ACCEPT, AUTHORIZATION, CONTENT_TYPE, USER_AGENT};
use serde::{Deserialize, Serialize};
use serde_json::json;
use tracing::{info, warn};

/// Notification configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationConfig {
    pub enabled: bool,
    pub github: Option<GitHubConfig>,
    pub slack: Option<SlackConfig>,
}

/// GitHub notification config
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitHubConfig {
    pub repo: String,
    pub token_env: String,
    pub create_issues: bool,
    pub add_comments: bool,
}

/// Slack notification config
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SlackConfig {
    pub webhook_url_env: String,
    pub channel: String,
    pub notify_on_failure: bool,
    pub notify_on_success: bool,
}

/// Notification sender
pub struct Notifier {
    config: NotificationConfig,
}

impl Notifier {
    pub fn new(config: NotificationConfig) -> Self {
        Self { config }
    }

    /// Send a notification about test results
    pub async fn notify(&self, title: &str, message: &str, is_failure: bool) -> Result<()> {
        if !self.config.enabled {
            return Ok(());
        }

        if let Some(github) = &self.config.github {
            if github.create_issues && is_failure {
                self.create_github_issue(title, message).await?;
            }
        }

        if let Some(slack) = &self.config.slack {
            let should_notify =
                (is_failure && slack.notify_on_failure) || (!is_failure && slack.notify_on_success);

            if should_notify {
                self.send_slack_message(title, message, is_failure).await?;
            }
        }

        Ok(())
    }

    async fn create_github_issue(&self, title: &str, body: &str) -> Result<()> {
        let Some(github) = &self.config.github else {
            return Ok(());
        };

        if github.repo.trim().is_empty() {
            info!("Skipping GitHub notification: repo not configured");
            return Ok(());
        }
        if github.token_env.trim().is_empty() {
            info!("Skipping GitHub notification: token env var name not configured");
            return Ok(());
        }

        let token = match std::env::var(&github.token_env) {
            Ok(value) if !value.trim().is_empty() => value,
            _ => {
                info!(
                    env_var = %github.token_env,
                    "Skipping GitHub notification: token env var not set"
                );
                return Ok(());
            }
        };

        let Some((owner, repo)) = github.repo.split_once('/') else {
            warn!(repo = %github.repo, "Skipping GitHub notification: invalid repo format");
            return Ok(());
        };

        let url = format!("https://api.github.com/repos/{owner}/{repo}/issues");
        let client = reqwest::Client::new();
        let response = client
            .post(&url)
            .header(AUTHORIZATION, format!("Bearer {}", token))
            .header(ACCEPT, "application/vnd.github+json")
            .header(USER_AGENT, "afsc/0.1")
            .json(&json!({
                "title": title,
                "body": body,
                "labels": ["afsc-automated"],
            }))
            .send()
            .await;

        match response {
            Ok(response) => {
                let status = response.status();
                let response_body = response.text().await.unwrap_or_default();
                if status == reqwest::StatusCode::CREATED {
                    let issue_url = serde_json::from_str::<serde_json::Value>(&response_body)
                        .ok()
                        .and_then(|value| {
                            value.get("html_url").and_then(|url| url.as_str()).map(str::to_string)
                        });
                    if let Some(issue_url) = issue_url {
                        info!(repo = %github.repo, issue_url = %issue_url, "Created GitHub issue");
                    } else {
                        info!(repo = %github.repo, "Created GitHub issue");
                    }
                } else {
                    warn!(
                        repo = %github.repo,
                        status = %status,
                        body = %excerpt(&response_body),
                        "GitHub notification failed"
                    );
                }
            }
            Err(error) => {
                warn!(repo = %github.repo, error = %error, "GitHub notification request failed");
            }
        }

        Ok(())
    }

    async fn send_slack_message(&self, title: &str, message: &str, is_failure: bool) -> Result<()> {
        let Some(slack) = &self.config.slack else {
            return Ok(());
        };

        if slack.webhook_url_env.trim().is_empty() {
            info!("Skipping Slack notification: webhook env var name not configured");
            return Ok(());
        }

        let webhook_url = match std::env::var(&slack.webhook_url_env) {
            Ok(value) if !value.trim().is_empty() => value,
            _ => {
                info!(
                    env_var = %slack.webhook_url_env,
                    "Skipping Slack notification: webhook env var not set"
                );
                return Ok(());
            }
        };

        let color = if is_failure { "#ff0000" } else { "#36a64f" };
        let attachment = json!({
            "color": color,
            "title": title,
            "text": message,
        });
        let payload = if slack.channel.trim().is_empty() {
            json!({
                "text": title,
                "attachments": [attachment],
            })
        } else {
            json!({
                "channel": slack.channel,
                "text": title,
                "attachments": [attachment],
            })
        };

        let client = reqwest::Client::new();
        let response = client
            .post(&webhook_url)
            .header(CONTENT_TYPE, "application/json")
            .json(&payload)
            .send()
            .await;

        match response {
            Ok(response) => {
                let status = response.status();
                let response_body = response.text().await.unwrap_or_default();
                if status.is_success() {
                    info!("Sent Slack notification");
                } else {
                    warn!(
                        status = %status,
                        body = %excerpt(&response_body),
                        "Slack notification failed"
                    );
                }
            }
            Err(error) => {
                warn!(error = %error, "Slack notification request failed");
            }
        }

        Ok(())
    }

    pub fn config(&self) -> &NotificationConfig {
        &self.config
    }
}

fn excerpt(input: &str) -> String {
    const MAX_LEN: usize = 200;

    if input.chars().count() <= MAX_LEN {
        input.to_string()
    } else {
        let mut shortened: String = input.chars().take(MAX_LEN).collect();
        shortened.push_str("...");
        shortened
    }
}
