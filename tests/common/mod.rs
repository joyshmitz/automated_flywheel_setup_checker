//! Shared test utilities for unit tests

use std::fs;
use std::io::Write;
use std::path::Path;
use tempfile::{NamedTempFile, TempDir};

/// Load a test fixture file by name
pub fn load_fixture(name: &str) -> String {
    let path = format!("tests/unit/fixtures/{}", name);
    fs::read_to_string(&path).unwrap_or_else(|_| panic!("Failed to load fixture: {}", path))
}

/// Load an error output fixture
pub fn load_error_fixture(name: &str) -> String {
    load_fixture(&format!("error_outputs/{}", name))
}

/// Load a remediation response fixture
pub fn load_remediation_fixture(name: &str) -> String {
    load_fixture(&format!("remediation_responses/{}", name))
}

/// Create a temporary YAML file with the given content
pub fn create_temp_yaml(content: &str) -> NamedTempFile {
    let mut file = NamedTempFile::with_suffix(".yaml").unwrap();
    writeln!(file, "{}", content).unwrap();
    file
}

/// Create a temporary TOML file with the given content
pub fn create_temp_toml(content: &str) -> NamedTempFile {
    let mut file = NamedTempFile::with_suffix(".toml").unwrap();
    writeln!(file, "{}", content).unwrap();
    file
}

/// Create a temporary directory with optional files
pub fn create_temp_dir_with_files(files: &[(&str, &str)]) -> TempDir {
    let dir = TempDir::new().unwrap();
    for (name, content) in files {
        let path = dir.path().join(name);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).unwrap();
        }
        fs::write(path, content).unwrap();
    }
    dir
}

/// Assert that a duration is within expected bounds
pub fn assert_duration_reasonable(millis: u64, min_ms: u64, max_ms: u64) {
    assert!(
        millis >= min_ms && millis <= max_ms,
        "Duration {}ms not in range [{}, {}]",
        millis,
        min_ms,
        max_ms
    );
}

/// Helper macro for asserting error types
#[macro_export]
macro_rules! assert_error_type {
    ($result:expr, $error_type:pat) => {
        match $result {
            Err($error_type) => (),
            other => panic!("Expected error type {}, got: {:?}", stringify!($error_type), other),
        }
    };
}

/// Helper macro for asserting classification severity
#[macro_export]
macro_rules! assert_severity {
    ($classification:expr, $severity:expr) => {
        assert_eq!(
            $classification.severity, $severity,
            "Expected severity {:?}, got {:?}",
            $severity, $classification.severity
        );
    };
}
