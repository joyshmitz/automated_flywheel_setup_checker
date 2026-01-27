//! Parser for checksums.yaml file format

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;

/// Root structure of checksums.yaml
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChecksumsFile {
    /// Schema version
    #[serde(default)]
    pub version: Option<String>,
    /// Map of installer name to entry
    #[serde(flatten)]
    pub installers: HashMap<String, InstallerEntry>,
}

/// Entry for a single installer/tool
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstallerEntry {
    /// Tool version
    pub version: Option<String>,
    /// Download URL
    pub url: Option<String>,
    /// Expected checksum
    pub checksum: Option<Checksum>,
    /// Whether the installer is enabled
    #[serde(default = "default_enabled")]
    pub enabled: bool,
    /// Tags for categorization
    #[serde(default)]
    pub tags: Vec<String>,
    /// Additional metadata
    #[serde(flatten)]
    pub extra: HashMap<String, serde_yaml::Value>,
}

fn default_enabled() -> bool {
    true
}

/// Checksum specification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Checksum {
    /// Algorithm (sha256, sha512, etc.)
    pub algorithm: String,
    /// Expected hash value
    pub value: String,
}

/// Parse a checksums.yaml file
pub fn parse_checksums(path: &Path) -> Result<ChecksumsFile> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read checksums file: {}", path.display()))?;

    let checksums: ChecksumsFile = serde_yaml::from_str(&content)
        .with_context(|| format!("Failed to parse checksums YAML: {}", path.display()))?;

    Ok(checksums)
}

/// Get list of enabled installers
pub fn get_enabled_installers(checksums: &ChecksumsFile) -> Vec<(&String, &InstallerEntry)> {
    checksums.installers.iter().filter(|(_, entry)| entry.enabled).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;

    #[test]
    fn test_parse_simple_checksums() {
        let mut file = NamedTempFile::new().unwrap();
        writeln!(
            file,
            r#"
version: "1.0"
rust:
  version: "1.75.0"
  url: "https://sh.rustup.rs"
  enabled: true
  tags:
    - language
    - essential
nodejs:
  version: "20.10.0"
  url: "https://nodejs.org/dist/v20.10.0/node-v20.10.0-linux-x64.tar.xz"
  enabled: false
"#
        )
        .unwrap();

        let checksums = parse_checksums(file.path()).unwrap();
        assert!(checksums.installers.contains_key("rust"));
        assert!(checksums.installers.contains_key("nodejs"));

        let rust = &checksums.installers["rust"];
        assert!(rust.enabled);
        assert_eq!(rust.version, Some("1.75.0".to_string()));

        let nodejs = &checksums.installers["nodejs"];
        assert!(!nodejs.enabled);
    }
}
