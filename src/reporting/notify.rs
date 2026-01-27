//! Notification handlers (GitHub, Slack)

use anyhow::Result;
use serde::{Deserialize, Serialize};

/// Notification configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationConfig {
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
        if let Some(github) = &self.config.github {
            if github.create_issues && is_failure {
                self.create_github_issue(title, message).await?;
            }
        }

        if let Some(slack) = &self.config.slack {
            let should_notify =
                (is_failure && slack.notify_on_failure) || (!is_failure && slack.notify_on_success);

            if should_notify {
                self.send_slack_message(title, message).await?;
            }
        }

        Ok(())
    }

    async fn create_github_issue(&self, _title: &str, _body: &str) -> Result<()> {
        // Placeholder - would use GitHub API
        tracing::info!("Would create GitHub issue");
        Ok(())
    }

    async fn send_slack_message(&self, _title: &str, _message: &str) -> Result<()> {
        // Placeholder - would use Slack webhook
        tracing::info!("Would send Slack message");
        Ok(())
    }

    pub fn config(&self) -> &NotificationConfig {
        &self.config
    }
}
