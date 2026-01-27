//! Checksums.yaml parsing and validation

mod parser;
mod validator;

pub use parser::{parse_checksums, Checksum, ChecksumsFile, InstallerEntry};
pub use validator::{validate_checksums, ValidationResult};
