//! Error parsing and classification

mod classifier;
mod error;

pub use classifier::{classify_error, ErrorClassification, ErrorSeverity};
pub use error::ParsedError;
