//! Configuration schema definitions

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Root configuration structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub general: GeneralConfig,
    pub docker: DockerConfig,
    pub execution: ExecutionConfig,
    pub remediation: RemediationConfig,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            general: GeneralConfig::default(),
            docker: DockerConfig::default(),
            execution: ExecutionConfig::default(),
            remediation: RemediationConfig::default(),
        }
    }
}

/// General configuration settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GeneralConfig {
    /// Path to the ACFS repository
    pub acfs_repo: PathBuf,
    /// Log level (trace, debug, info, warn, error)
    pub log_level: String,
}

impl Default for GeneralConfig {
    fn default() -> Self {
        Self {
            acfs_repo: PathBuf::from("/data/projects/agentic_coding_flywheel_setup"),
            log_level: "info".to_string(),
        }
    }
}

/// Docker-related configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DockerConfig {
    /// Base Docker image to use
    pub image: String,
    /// Memory limit for containers
    pub memory_limit: String,
    /// CPU quota (1.0 = 1 CPU)
    pub cpu_quota: f64,
    /// Timeout in seconds per installer test
    pub timeout_seconds: u64,
    /// Image pull policy: always, if-not-present, never
    pub pull_policy: String,
}

impl Default for DockerConfig {
    fn default() -> Self {
        Self {
            image: "ubuntu:22.04".to_string(),
            memory_limit: "2G".to_string(),
            cpu_quota: 1.0,
            timeout_seconds: 300,
            pull_policy: "if-not-present".to_string(),
        }
    }
}

/// Execution configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionConfig {
    /// Number of parallel installer tests
    pub parallel: usize,
    /// Number of retries for transient failures
    pub retry_transient: u32,
    /// Stop on first failure
    pub fail_fast: bool,
}

impl Default for ExecutionConfig {
    fn default() -> Self {
        Self { parallel: 1, retry_transient: 3, fail_fast: false }
    }
}

/// Remediation configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemediationConfig {
    /// Enable auto-remediation
    pub enabled: bool,
    /// Auto-commit fixes
    pub auto_commit: bool,
    /// Create PRs for fixes
    pub create_pr: bool,
    /// Maximum remediation attempts
    pub max_attempts: u32,
}

impl Default for RemediationConfig {
    fn default() -> Self {
        Self { enabled: false, auto_commit: false, create_pr: true, max_attempts: 3 }
    }
}
