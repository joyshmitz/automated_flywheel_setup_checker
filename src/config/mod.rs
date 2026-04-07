//! Configuration management for the checker

mod loader;
mod schema;

pub use loader::load_config;
pub use schema::{
    Config, DockerConfig, ExecutionConfig, GeneralConfig, MonitoringConfig, NotificationsConfig,
    RemediationConfig, WatchdogConfig,
};
