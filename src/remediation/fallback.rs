//! Fallback manual remediation suggestions

use crate::parser::{ErrorClassification, ErrorSeverity};
use serde::{Deserialize, Serialize};

/// A suggestion for manual remediation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FallbackSuggestion {
    pub title: String,
    pub description: String,
    pub commands: Vec<String>,
    pub documentation_url: Option<String>,
}

/// Generate fallback suggestions based on error classification
pub fn generate_suggestions(classification: &ErrorClassification) -> Vec<FallbackSuggestion> {
    match classification.severity {
        ErrorSeverity::Transient => vec![FallbackSuggestion {
            title: "Retry the operation".to_string(),
            description: "This appears to be a transient error. Try again in a few moments."
                .to_string(),
            commands: vec![],
            documentation_url: None,
        }],
        ErrorSeverity::Permission => vec![FallbackSuggestion {
            title: "Check permissions".to_string(),
            description: "The operation was denied due to insufficient permissions.".to_string(),
            commands: vec![
                "sudo chown -R $USER:$USER ~/.local".to_string(),
                "chmod +x <script>".to_string(),
            ],
            documentation_url: None,
        }],
        ErrorSeverity::Dependency => vec![FallbackSuggestion {
            title: "Install missing dependencies".to_string(),
            description: "Required software is not installed.".to_string(),
            commands: vec!["sudo apt update && sudo apt install -y <package>".to_string()],
            documentation_url: None,
        }],
        ErrorSeverity::Resource => vec![FallbackSuggestion {
            title: "Free up resources".to_string(),
            description: "The system is low on resources (disk space or memory).".to_string(),
            commands: vec![
                "df -h".to_string(),
                "free -h".to_string(),
                "sudo apt autoremove".to_string(),
            ],
            documentation_url: None,
        }],
        ErrorSeverity::Configuration | ErrorSeverity::Unknown => vec![FallbackSuggestion {
            title: "Check configuration".to_string(),
            description: "Review the error message and configuration files.".to_string(),
            commands: vec![],
            documentation_url: Some(
                "https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup".to_string(),
            ),
        }],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_permission_suggestions() {
        let classification = ErrorClassification {
            severity: ErrorSeverity::Permission,
            category: "permission".to_string(),
            suggestion: None,
            retryable: false,
            confidence: 0.9,
        };

        let suggestions = generate_suggestions(&classification);
        assert!(!suggestions.is_empty());
        assert!(suggestions[0].title.contains("permission"));
    }
}
