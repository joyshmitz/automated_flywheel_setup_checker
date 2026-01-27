//! Error type definitions

use serde::{Deserialize, Serialize};

/// A parsed error from installer output
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParsedError {
    /// Original error message
    pub message: String,
    /// Exit code if available
    pub exit_code: Option<i32>,
    /// Source file if identified
    pub source_file: Option<String>,
    /// Line number if identified
    pub line_number: Option<u32>,
    /// Extracted command that failed
    pub failed_command: Option<String>,
}

impl ParsedError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            exit_code: None,
            source_file: None,
            line_number: None,
            failed_command: None,
        }
    }

    pub fn with_exit_code(mut self, code: i32) -> Self {
        self.exit_code = Some(code);
        self
    }

    pub fn with_source(mut self, file: impl Into<String>, line: u32) -> Self {
        self.source_file = Some(file.into());
        self.line_number = Some(line);
        self
    }

    pub fn with_command(mut self, cmd: impl Into<String>) -> Self {
        self.failed_command = Some(cmd.into());
        self
    }
}
