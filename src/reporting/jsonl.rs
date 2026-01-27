//! Structured JSONL logging

use anyhow::Result;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fs::{File, OpenOptions};
use std::io::{BufWriter, Write};
use std::path::Path;

/// Log level for structured entries
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

impl Default for LogLevel {
    fn default() -> Self {
        LogLevel::Info
    }
}

/// Structured log entry for JSONL output
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogEntry {
    pub timestamp: DateTime<Utc>,
    pub level: LogLevel,
    pub component: String,
    pub event: String,
    pub data: serde_json::Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration_ms: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub correlation_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub installer: Option<String>,
}

impl LogEntry {
    /// Create a new log entry with the given level and event
    pub fn new(level: LogLevel, component: impl Into<String>, event: impl Into<String>) -> Self {
        Self {
            timestamp: Utc::now(),
            level,
            component: component.into(),
            event: event.into(),
            data: serde_json::Value::Null,
            duration_ms: None,
            error: None,
            correlation_id: None,
            installer: None,
        }
    }

    pub fn info(component: impl Into<String>, event: impl Into<String>) -> Self {
        Self::new(LogLevel::Info, component, event)
    }

    pub fn error(component: impl Into<String>, event: impl Into<String>) -> Self {
        Self::new(LogLevel::Error, component, event)
    }

    pub fn warn(component: impl Into<String>, event: impl Into<String>) -> Self {
        Self::new(LogLevel::Warn, component, event)
    }

    pub fn debug(component: impl Into<String>, event: impl Into<String>) -> Self {
        Self::new(LogLevel::Debug, component, event)
    }

    pub fn with_data(mut self, data: serde_json::Value) -> Self {
        self.data = data;
        self
    }

    pub fn with_duration_ms(mut self, ms: u64) -> Self {
        self.duration_ms = Some(ms);
        self
    }

    pub fn with_error(mut self, error: impl Into<String>) -> Self {
        self.error = Some(error.into());
        self
    }

    pub fn with_correlation_id(mut self, id: impl Into<String>) -> Self {
        self.correlation_id = Some(id.into());
        self
    }

    pub fn with_installer(mut self, installer: impl Into<String>) -> Self {
        self.installer = Some(installer.into());
        self
    }
}

/// Simple writer for JSONL (JSON Lines) format logs
pub struct JsonlWriter {
    writer: BufWriter<File>,
}

impl JsonlWriter {
    /// Create a new JSONL writer
    pub fn new(path: &Path) -> Result<Self> {
        let file = OpenOptions::new().create(true).append(true).open(path)?;

        Ok(Self { writer: BufWriter::new(file) })
    }

    /// Write a record to the JSONL file
    pub fn write<T: Serialize>(&mut self, record: &T) -> Result<()> {
        let json = serde_json::to_string(record)?;
        writeln!(self.writer, "{}", json)?;
        self.writer.flush()?;
        Ok(())
    }

    /// Flush the writer
    pub fn flush(&mut self) -> Result<()> {
        self.writer.flush()?;
        Ok(())
    }
}

/// Reporter for structured JSONL logs with batching and level filtering
pub struct JsonlReporter {
    writer: BufWriter<File>,
    min_level: LogLevel,
    buffer_size: usize,
    pending_entries: Vec<LogEntry>,
    fsync_enabled: bool,
}

impl JsonlReporter {
    /// Create a new JSONL reporter
    pub fn new(path: &Path, min_level: LogLevel) -> Result<Self> {
        let file = OpenOptions::new().create(true).append(true).open(path)?;

        Ok(Self {
            writer: BufWriter::new(file),
            min_level,
            buffer_size: 100,
            pending_entries: Vec::new(),
            fsync_enabled: false,
        })
    }

    /// Enable fsync after each write (for durability)
    pub fn with_fsync(mut self, enabled: bool) -> Self {
        self.fsync_enabled = enabled;
        self
    }

    /// Set buffer size for batch writes
    pub fn with_buffer_size(mut self, size: usize) -> Self {
        self.buffer_size = size;
        self
    }

    /// Log an entry if it meets the minimum level
    pub fn log(&mut self, entry: LogEntry) -> Result<()> {
        if entry.level >= self.min_level {
            self.pending_entries.push(entry);

            if self.pending_entries.len() >= self.buffer_size {
                self.flush()?;
            }
        }
        Ok(())
    }

    /// Log an entry only if the condition is true
    pub fn log_if(&mut self, condition: bool, entry: LogEntry) -> Result<()> {
        if condition {
            self.log(entry)?;
        }
        Ok(())
    }

    /// Log a batch of entries
    pub fn log_batch(&mut self, entries: Vec<LogEntry>) -> Result<()> {
        for entry in entries {
            self.log(entry)?;
        }
        Ok(())
    }

    /// Flush pending entries to disk
    pub fn flush(&mut self) -> Result<()> {
        for entry in self.pending_entries.drain(..) {
            let json = serde_json::to_string(&entry)?;
            writeln!(self.writer, "{}", json)?;
        }
        self.writer.flush()?;

        if self.fsync_enabled {
            self.writer.get_ref().sync_all()?;
        }

        Ok(())
    }

    /// Get the current minimum log level
    pub fn min_level(&self) -> LogLevel {
        self.min_level
    }
}

impl Drop for JsonlReporter {
    fn drop(&mut self) {
        let _ = self.flush();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;
    use tempfile::NamedTempFile;

    #[derive(Serialize, Deserialize, PartialEq, Debug)]
    struct TestRecord {
        name: String,
        value: i32,
    }

    #[test]
    fn test_jsonl_writer() {
        let file = NamedTempFile::new().unwrap();
        let mut writer = JsonlWriter::new(file.path()).unwrap();

        let record = TestRecord { name: "test".to_string(), value: 42 };
        writer.write(&record).unwrap();

        let content = std::fs::read_to_string(file.path()).unwrap();
        assert!(content.contains("\"name\":\"test\""));
        assert!(content.contains("\"value\":42"));
    }

    #[test]
    fn test_log_entry_builder() {
        let entry = LogEntry::info("runner", "test_started")
            .with_installer("nodejs")
            .with_correlation_id("run-123")
            .with_data(serde_json::json!({"version": "20.0"}));

        assert_eq!(entry.level, LogLevel::Info);
        assert_eq!(entry.component, "runner");
        assert_eq!(entry.event, "test_started");
        assert_eq!(entry.installer, Some("nodejs".to_string()));
        assert_eq!(entry.correlation_id, Some("run-123".to_string()));
    }

    #[test]
    fn test_jsonl_reporter_filtering() {
        let file = NamedTempFile::new().unwrap();
        let mut reporter = JsonlReporter::new(file.path(), LogLevel::Warn).unwrap();

        // Debug should be filtered out
        reporter.log(LogEntry::debug("test", "debug_event")).unwrap();
        // Warn should be included
        reporter.log(LogEntry::warn("test", "warn_event")).unwrap();
        // Error should be included
        reporter.log(LogEntry::error("test", "error_event")).unwrap();

        reporter.flush().unwrap();

        let content = std::fs::read_to_string(file.path()).unwrap();
        assert!(!content.contains("debug_event"));
        assert!(content.contains("warn_event"));
        assert!(content.contains("error_event"));
    }

    #[test]
    fn test_log_level_ordering() {
        assert!(LogLevel::Error > LogLevel::Warn);
        assert!(LogLevel::Warn > LogLevel::Info);
        assert!(LogLevel::Info > LogLevel::Debug);
        assert!(LogLevel::Debug > LogLevel::Trace);
    }
}
