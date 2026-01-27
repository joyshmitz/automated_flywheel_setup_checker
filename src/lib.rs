//! Automated ACFS installer verification system
//!
//! This crate provides tools for testing and verifying ACFS installer scripts
//! against various configurations and detecting failures early.

pub mod checksums;
pub mod config;
pub mod logging;
pub mod parser;
pub mod remediation;
pub mod reporting;
pub mod runner;
pub mod watchdog;

pub use config::Config;
pub use watchdog::SystemdWatchdog;
