//! Command safety checks

use regex::Regex;
use serde::{Deserialize, Serialize};

/// Result of a safety check
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SafetyCheck {
    pub safe: bool,
    pub reason: Option<String>,
    pub risk_level: RiskLevel,
}

/// Risk level for a command
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RiskLevel {
    Safe,
    Low,
    Medium,
    High,
    Critical,
}

/// Check if a command is safe to execute
pub fn is_command_safe(command: &str) -> SafetyCheck {
    // Critical patterns that should never be auto-executed
    let critical_patterns = [
        r"rm\s+-rf\s+/",
        r"rm\s+-rf\s+\*",
        r"mkfs",
        r"dd\s+if=.+of=/dev",
        r":(){ :|:& };:", // fork bomb
        r">\s*/dev/sd",
        r"chmod\s+-R\s+777\s+/",
    ];

    for pattern in &critical_patterns {
        if let Ok(re) = Regex::new(pattern) {
            if re.is_match(command) {
                return SafetyCheck {
                    safe: false,
                    reason: Some(format!("Matches critical pattern: {}", pattern)),
                    risk_level: RiskLevel::Critical,
                };
            }
        }
    }

    // High risk patterns
    let high_risk_patterns = [
        r"sudo\s+rm",
        r"sudo\s+chmod",
        r"sudo\s+chown",
        r"git\s+push\s+--force",
        r"git\s+reset\s+--hard",
    ];

    for pattern in &high_risk_patterns {
        if let Ok(re) = Regex::new(pattern) {
            if re.is_match(command) {
                return SafetyCheck {
                    safe: false,
                    reason: Some(format!("Matches high-risk pattern: {}", pattern)),
                    risk_level: RiskLevel::High,
                };
            }
        }
    }

    // Medium risk - sudo in general
    if command.contains("sudo") {
        return SafetyCheck {
            safe: true, // Allow but flag
            reason: Some("Command uses sudo".to_string()),
            risk_level: RiskLevel::Medium,
        };
    }

    SafetyCheck { safe: true, reason: None, risk_level: RiskLevel::Safe }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_safe_command() {
        let check = is_command_safe("ls -la");
        assert!(check.safe);
        assert_eq!(check.risk_level, RiskLevel::Safe);
    }

    #[test]
    fn test_critical_command() {
        let check = is_command_safe("rm -rf /");
        assert!(!check.safe);
        assert_eq!(check.risk_level, RiskLevel::Critical);
    }

    #[test]
    fn test_high_risk_command() {
        let check = is_command_safe("git push --force origin main");
        assert!(!check.safe);
        assert_eq!(check.risk_level, RiskLevel::High);
    }

    #[test]
    fn test_medium_risk_command() {
        let check = is_command_safe("sudo apt install vim");
        assert!(check.safe);
        assert_eq!(check.risk_level, RiskLevel::Medium);
    }
}
