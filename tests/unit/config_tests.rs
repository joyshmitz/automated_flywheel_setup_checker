//! Tests for the configuration module
//!
//! Tests cover:
//! - Loading config from file
//! - Default value handling
//! - Config structure validation
//! - All config sections (general, docker, execution, remediation)

use automated_flywheel_setup_checker::config::{
    load_config, Config, DockerConfig, ExecutionConfig, GeneralConfig, RemediationConfig,
};
use std::io::Write;
use std::path::PathBuf;
use tempfile::NamedTempFile;

// ============================================================================
// Default Config Tests
// ============================================================================

#[test]
fn test_load_default_config() {
    let config = load_config(None).unwrap();

    // Check docker defaults
    assert_eq!(config.docker.image, "ubuntu:22.04");
    assert_eq!(config.docker.memory_limit, "2G");
    assert_eq!(config.docker.cpu_quota, 1.0);
    assert_eq!(config.docker.timeout_seconds, 300);
    assert_eq!(config.docker.pull_policy, "if-not-present");

    // Check execution defaults
    assert_eq!(config.execution.parallel, 1);
    assert_eq!(config.execution.retry_transient, 3);
    assert!(!config.execution.fail_fast);

    // Check remediation defaults
    assert!(!config.remediation.enabled);
    assert!(!config.remediation.auto_commit);
    assert!(config.remediation.create_pr);
    assert_eq!(config.remediation.max_attempts, 3);
}

#[test]
fn test_config_default_trait() {
    let config = Config::default();
    assert_eq!(config.docker.image, "ubuntu:22.04");
    assert_eq!(config.execution.parallel, 1);
}

#[test]
fn test_general_config_default() {
    let general = GeneralConfig::default();
    assert_eq!(general.acfs_repo, PathBuf::from("/data/projects/agentic_coding_flywheel_setup"));
    assert_eq!(general.log_level, "info");
}

#[test]
fn test_docker_config_default() {
    let docker = DockerConfig::default();
    assert_eq!(docker.image, "ubuntu:22.04");
    assert_eq!(docker.memory_limit, "2G");
    assert_eq!(docker.cpu_quota, 1.0);
    assert_eq!(docker.timeout_seconds, 300);
    assert_eq!(docker.pull_policy, "if-not-present");
}

#[test]
fn test_execution_config_default() {
    let execution = ExecutionConfig::default();
    assert_eq!(execution.parallel, 1);
    assert_eq!(execution.retry_transient, 3);
    assert!(!execution.fail_fast);
}

#[test]
fn test_remediation_config_default() {
    let remediation = RemediationConfig::default();
    assert!(!remediation.enabled);
    assert!(!remediation.auto_commit);
    assert!(remediation.create_pr);
    assert_eq!(remediation.max_attempts, 3);
}

// ============================================================================
// File Loading Tests
// ============================================================================

#[test]
fn test_load_config_from_file() {
    let mut file = NamedTempFile::with_suffix(".toml").unwrap();
    writeln!(
        file,
        r#"
[general]
acfs_repo = "/custom/path"
log_level = "debug"

[docker]
image = "ubuntu:24.04"
memory_limit = "4G"
cpu_quota = 2.0
timeout_seconds = 600
pull_policy = "always"

[execution]
parallel = 4
retry_transient = 5
fail_fast = true

[remediation]
enabled = true
auto_commit = false
create_pr = true
max_attempts = 5
"#
    )
    .unwrap();

    let config = load_config(Some(file.path())).unwrap();

    // General
    assert_eq!(config.general.acfs_repo, PathBuf::from("/custom/path"));
    assert_eq!(config.general.log_level, "debug");

    // Docker
    assert_eq!(config.docker.image, "ubuntu:24.04");
    assert_eq!(config.docker.memory_limit, "4G");
    assert_eq!(config.docker.cpu_quota, 2.0);
    assert_eq!(config.docker.timeout_seconds, 600);
    assert_eq!(config.docker.pull_policy, "always");

    // Execution
    assert_eq!(config.execution.parallel, 4);
    assert_eq!(config.execution.retry_transient, 5);
    assert!(config.execution.fail_fast);

    // Remediation
    assert!(config.remediation.enabled);
    assert!(!config.remediation.auto_commit);
    assert!(config.remediation.create_pr);
    assert_eq!(config.remediation.max_attempts, 5);
}

#[test]
fn test_load_partial_config() {
    // Only specify some values, rest should use defaults
    let mut file = NamedTempFile::with_suffix(".toml").unwrap();
    writeln!(
        file,
        r#"
[general]
acfs_repo = "/my/repo"
log_level = "warn"

[docker]
image = "debian:latest"
memory_limit = "2G"
cpu_quota = 1.0
timeout_seconds = 300
pull_policy = "if-not-present"

[execution]
parallel = 2
retry_transient = 3
fail_fast = false

[remediation]
enabled = false
auto_commit = false
create_pr = true
max_attempts = 3
"#
    )
    .unwrap();

    let config = load_config(Some(file.path())).unwrap();

    // Specified values
    assert_eq!(config.general.acfs_repo, PathBuf::from("/my/repo"));
    assert_eq!(config.general.log_level, "warn");
    assert_eq!(config.docker.image, "debian:latest");
    assert_eq!(config.execution.parallel, 2);
}

#[test]
fn test_load_minimal_config() {
    let mut file = NamedTempFile::with_suffix(".toml").unwrap();
    writeln!(
        file,
        r#"
[general]
acfs_repo = "/tmp"
log_level = "info"

[docker]
image = "ubuntu:22.04"
memory_limit = "2G"
cpu_quota = 1.0
timeout_seconds = 300
pull_policy = "if-not-present"

[execution]
parallel = 1
retry_transient = 3
fail_fast = false

[remediation]
enabled = false
auto_commit = false
create_pr = true
max_attempts = 3
"#
    )
    .unwrap();

    let result = load_config(Some(file.path()));
    assert!(result.is_ok());
}

// ============================================================================
// Error Handling Tests
// ============================================================================

#[test]
fn test_load_nonexistent_file() {
    let result = load_config(Some(std::path::Path::new("/nonexistent/config.toml")));
    assert!(result.is_err());
}

#[test]
fn test_load_invalid_toml() {
    let mut file = NamedTempFile::with_suffix(".toml").unwrap();
    writeln!(
        file,
        r#"
this is not valid toml
[broken
"#
    )
    .unwrap();

    let result = load_config(Some(file.path()));
    assert!(result.is_err());
}

#[test]
fn test_load_wrong_types() {
    let mut file = NamedTempFile::with_suffix(".toml").unwrap();
    writeln!(
        file,
        r#"
[general]
acfs_repo = 12345
log_level = true

[docker]
image = "ubuntu"
memory_limit = "2G"
cpu_quota = 1.0
timeout_seconds = 300
pull_policy = "if-not-present"

[execution]
parallel = 1
retry_transient = 3
fail_fast = false

[remediation]
enabled = false
auto_commit = false
create_pr = true
max_attempts = 3
"#
    )
    .unwrap();

    let result = load_config(Some(file.path()));
    assert!(result.is_err());
}

// ============================================================================
// Config Section Tests
// ============================================================================

#[test]
fn test_docker_config_values() {
    let docker = DockerConfig {
        image: "custom:latest".to_string(),
        memory_limit: "8G".to_string(),
        cpu_quota: 4.0,
        timeout_seconds: 1200,
        pull_policy: "never".to_string(),
    };

    assert_eq!(docker.image, "custom:latest");
    assert_eq!(docker.memory_limit, "8G");
    assert_eq!(docker.cpu_quota, 4.0);
    assert_eq!(docker.timeout_seconds, 1200);
    assert_eq!(docker.pull_policy, "never");
}

#[test]
fn test_execution_config_values() {
    let execution = ExecutionConfig { parallel: 8, retry_transient: 10, fail_fast: true };

    assert_eq!(execution.parallel, 8);
    assert_eq!(execution.retry_transient, 10);
    assert!(execution.fail_fast);
}

#[test]
fn test_remediation_config_values() {
    let remediation =
        RemediationConfig { enabled: true, auto_commit: true, create_pr: false, max_attempts: 10 };

    assert!(remediation.enabled);
    assert!(remediation.auto_commit);
    assert!(!remediation.create_pr);
    assert_eq!(remediation.max_attempts, 10);
}

// ============================================================================
// Edge Cases
// ============================================================================

#[test]
fn test_empty_file() {
    let file = NamedTempFile::with_suffix(".toml").unwrap();
    // Empty file should fail since required sections are missing
    let result = load_config(Some(file.path()));
    assert!(result.is_err());
}

#[test]
fn test_config_clone() {
    let config = Config::default();
    let cloned = config.clone();
    assert_eq!(config.docker.image, cloned.docker.image);
    assert_eq!(config.execution.parallel, cloned.execution.parallel);
}

#[test]
fn test_config_debug() {
    let config = Config::default();
    let debug_str = format!("{:?}", config);
    assert!(debug_str.contains("ubuntu:22.04"));
}

// ============================================================================
// Serialization Tests
// ============================================================================

#[test]
fn test_config_serializable() {
    let config = Config::default();
    let serialized = toml::to_string(&config).unwrap();
    assert!(serialized.contains("ubuntu:22.04"));
    assert!(serialized.contains("[docker]"));
    assert!(serialized.contains("[execution]"));
}

#[test]
fn test_config_roundtrip() {
    let original = Config::default();
    let serialized = toml::to_string(&original).unwrap();
    let deserialized: Config = toml::from_str(&serialized).unwrap();

    assert_eq!(original.docker.image, deserialized.docker.image);
    assert_eq!(original.execution.parallel, deserialized.execution.parallel);
    assert_eq!(original.remediation.enabled, deserialized.remediation.enabled);
}
