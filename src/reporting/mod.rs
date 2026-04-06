//! Reporting and notification module

mod jsonl;
mod metrics;
mod notify;
mod summary;

pub use jsonl::{
    JsonlReporter, JsonlWriter, LogEntry, LogLevel, LogRotation, ResultEntry, ResultPersister,
    RunSummaryEntry,
};
pub use metrics::{MetricsExporter, MetricsSnapshot};
pub use notify::{GitHubConfig, NotificationConfig, Notifier, SlackConfig};
pub use summary::{FailureSummary, RunSummary, SummaryGenerator};
