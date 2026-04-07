//! Configuration loading from file and environment

use super::schema::Config;
use anyhow::{Context, Result};
use std::path::Path;

/// Load configuration from a TOML file
pub fn load_config(path: Option<&Path>) -> Result<Config> {
    match path {
        Some(p) => {
            let content = std::fs::read_to_string(p)
                .with_context(|| format!("Failed to read config file: {}", p.display()))?;
            let config: Config = toml::from_str(&content)
                .with_context(|| format!("Failed to parse config file: {}", p.display()))?;
            Ok(config)
        }
        None => Ok(Config::default()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;

    #[test]
    fn test_load_default_config() {
        let config = load_config(None).unwrap();
        assert_eq!(config.docker.image, "afsc-base:latest");
        assert_eq!(config.execution.parallel, 1);
    }

    #[test]
    fn test_load_config_from_file() {
        let mut file = NamedTempFile::new().unwrap();
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
        assert_eq!(config.docker.image, "ubuntu:24.04");
        assert_eq!(config.execution.parallel, 4);
        assert!(config.remediation.enabled);
    }
}
