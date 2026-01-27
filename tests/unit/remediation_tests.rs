//! Tests for the remediation module
//!
//! Tests cover:
//! - Command safety checking
//! - Fallback suggestion generation
//! - Circuit breaker logic
//! - Rate limiter behavior
//! - Retry configuration
//! - ClaudeRemediation configuration and cost tracking

use automated_flywheel_setup_checker::parser::{ErrorClassification, ErrorSeverity};
use automated_flywheel_setup_checker::remediation::{
    is_command_safe, ChangeType, CircuitState, ClaudeRemediation, ClaudeRemediationConfig,
    FallbackSuggestion, FileChange, RemediationMethod, RemediationResult, RetryConfig, SafetyCheck,
};
use std::path::PathBuf;
use std::time::Duration;

// ============================================================================
// Command Safety Tests
// ============================================================================

#[test]
fn test_safe_command_ls() {
    let check = is_command_safe("ls -la");
    assert!(check.safe);
    assert_eq!(check.risk_level, automated_flywheel_setup_checker::remediation::RiskLevel::Safe);
    assert!(check.reason.is_none());
}

#[test]
fn test_safe_command_echo() {
    let check = is_command_safe("echo 'hello world'");
    assert!(check.safe);
}

#[test]
fn test_safe_command_cat() {
    let check = is_command_safe("cat /etc/passwd");
    assert!(check.safe);
}

#[test]
fn test_safe_command_grep() {
    let check = is_command_safe("grep -r 'pattern' .");
    assert!(check.safe);
}

#[test]
fn test_critical_rm_rf_root() {
    let check = is_command_safe("rm -rf /");
    assert!(!check.safe);
    assert_eq!(
        check.risk_level,
        automated_flywheel_setup_checker::remediation::RiskLevel::Critical
    );
    assert!(check.reason.is_some());
}

#[test]
fn test_critical_rm_rf_star() {
    let check = is_command_safe("rm -rf *");
    assert!(!check.safe);
    assert_eq!(
        check.risk_level,
        automated_flywheel_setup_checker::remediation::RiskLevel::Critical
    );
}

#[test]
fn test_critical_mkfs() {
    let check = is_command_safe("mkfs.ext4 /dev/sda1");
    assert!(!check.safe);
    assert_eq!(
        check.risk_level,
        automated_flywheel_setup_checker::remediation::RiskLevel::Critical
    );
}

#[test]
fn test_critical_dd_device() {
    let check = is_command_safe("dd if=/dev/zero of=/dev/sda bs=1M");
    assert!(!check.safe);
    assert_eq!(
        check.risk_level,
        automated_flywheel_setup_checker::remediation::RiskLevel::Critical
    );
}

#[test]
fn test_critical_chmod_777_root() {
    let check = is_command_safe("chmod -R 777 /");
    assert!(!check.safe);
    assert_eq!(
        check.risk_level,
        automated_flywheel_setup_checker::remediation::RiskLevel::Critical
    );
}

#[test]
fn test_high_risk_sudo_rm() {
    let check = is_command_safe("sudo rm important_file");
    assert!(!check.safe);
    assert_eq!(check.risk_level, automated_flywheel_setup_checker::remediation::RiskLevel::High);
}

#[test]
fn test_high_risk_sudo_chmod() {
    let check = is_command_safe("sudo chmod 755 /etc/file");
    assert!(!check.safe);
    assert_eq!(check.risk_level, automated_flywheel_setup_checker::remediation::RiskLevel::High);
}

#[test]
fn test_high_risk_git_push_force() {
    let check = is_command_safe("git push --force origin main");
    assert!(!check.safe);
    assert_eq!(check.risk_level, automated_flywheel_setup_checker::remediation::RiskLevel::High);
}

#[test]
fn test_high_risk_git_reset_hard() {
    let check = is_command_safe("git reset --hard HEAD~5");
    assert!(!check.safe);
    assert_eq!(check.risk_level, automated_flywheel_setup_checker::remediation::RiskLevel::High);
}

#[test]
fn test_medium_risk_sudo_apt() {
    let check = is_command_safe("sudo apt install vim");
    assert!(check.safe); // Allowed but flagged
    assert_eq!(check.risk_level, automated_flywheel_setup_checker::remediation::RiskLevel::Medium);
    assert!(check.reason.is_some());
}

#[test]
fn test_medium_risk_sudo_systemctl() {
    let check = is_command_safe("sudo systemctl restart nginx");
    assert!(check.safe);
    assert_eq!(check.risk_level, automated_flywheel_setup_checker::remediation::RiskLevel::Medium);
}

// ============================================================================
// Fallback Suggestion Tests
// ============================================================================

#[test]
fn test_fallback_transient_error() {
    let classification = ErrorClassification {
        severity: ErrorSeverity::Transient,
        category: "network".to_string(),
        suggestion: None,
        retryable: true,
        confidence: 0.9,
    };

    let suggestions =
        automated_flywheel_setup_checker::remediation::fallback::generate_suggestions(
            &classification,
        );
    assert!(!suggestions.is_empty());
    assert!(suggestions[0].title.to_lowercase().contains("retry"));
}

#[test]
fn test_fallback_permission_error() {
    let classification = ErrorClassification {
        severity: ErrorSeverity::Permission,
        category: "permission".to_string(),
        suggestion: None,
        retryable: false,
        confidence: 0.9,
    };

    let suggestions =
        automated_flywheel_setup_checker::remediation::fallback::generate_suggestions(
            &classification,
        );
    assert!(!suggestions.is_empty());
    assert!(suggestions[0].title.to_lowercase().contains("permission"));
    assert!(!suggestions[0].commands.is_empty());
}

#[test]
fn test_fallback_dependency_error() {
    let classification = ErrorClassification {
        severity: ErrorSeverity::Dependency,
        category: "dependency".to_string(),
        suggestion: None,
        retryable: false,
        confidence: 0.8,
    };

    let suggestions =
        automated_flywheel_setup_checker::remediation::fallback::generate_suggestions(
            &classification,
        );
    assert!(!suggestions.is_empty());
    assert!(suggestions[0].title.to_lowercase().contains("dependenc"));
}

#[test]
fn test_fallback_resource_error() {
    let classification = ErrorClassification {
        severity: ErrorSeverity::Resource,
        category: "resource".to_string(),
        suggestion: None,
        retryable: false,
        confidence: 0.75,
    };

    let suggestions =
        automated_flywheel_setup_checker::remediation::fallback::generate_suggestions(
            &classification,
        );
    assert!(!suggestions.is_empty());
    assert!(suggestions[0].title.to_lowercase().contains("resource"));
    // Should suggest commands like df -h, free -h
    let commands: Vec<&str> = suggestions[0].commands.iter().map(|s| s.as_str()).collect();
    assert!(commands.iter().any(|c| c.contains("df") || c.contains("free")));
}

#[test]
fn test_fallback_unknown_error() {
    let classification = ErrorClassification {
        severity: ErrorSeverity::Unknown,
        category: "unknown".to_string(),
        suggestion: None,
        retryable: false,
        confidence: 0.0,
    };

    let suggestions =
        automated_flywheel_setup_checker::remediation::fallback::generate_suggestions(
            &classification,
        );
    assert!(!suggestions.is_empty());
    // Should provide a documentation URL
    assert!(suggestions[0].documentation_url.is_some());
}

// ============================================================================
// ClaudeRemediationConfig Tests
// ============================================================================

#[test]
fn test_claude_config_default() {
    let config = ClaudeRemediationConfig::default();
    assert!(!config.enabled);
    assert!(!config.auto_commit);
    assert!(config.create_pr);
    assert!(config.require_approval);
    assert_eq!(config.max_attempts, 3);
    assert_eq!(config.timeout_seconds, 300);
    assert_eq!(config.cost_limit_usd, 10.0);
}

#[test]
fn test_claude_config_custom() {
    let config = ClaudeRemediationConfig {
        enabled: true,
        auto_commit: true,
        create_pr: false,
        require_approval: false,
        max_attempts: 5,
        timeout_seconds: 600,
        cost_limit_usd: 25.0,
    };

    assert!(config.enabled);
    assert!(config.auto_commit);
    assert!(!config.create_pr);
    assert!(!config.require_approval);
    assert_eq!(config.max_attempts, 5);
    assert_eq!(config.timeout_seconds, 600);
    assert_eq!(config.cost_limit_usd, 25.0);
}

// ============================================================================
// ClaudeRemediation Tests
// ============================================================================

#[test]
fn test_claude_remediation_new() {
    let config = ClaudeRemediationConfig::default();
    let remediation = ClaudeRemediation::new(PathBuf::from("/tmp/test"), config);
    assert!(!remediation.is_enabled());
    assert_eq!(remediation.get_total_cost_usd(), 0.0);
}

#[test]
fn test_claude_remediation_cost_tracking() {
    let config = ClaudeRemediationConfig::default();
    let remediation = ClaudeRemediation::new(PathBuf::from("/tmp"), config);

    assert_eq!(remediation.get_total_cost_usd(), 0.0);
}

#[test]
fn test_claude_remediation_is_enabled() {
    let mut config = ClaudeRemediationConfig::default();
    config.enabled = true;
    let remediation = ClaudeRemediation::new(PathBuf::from("/tmp"), config);
    assert!(remediation.is_enabled());
}

// ============================================================================
// RetryConfig Tests
// ============================================================================

#[test]
fn test_retry_config_default() {
    let config = RetryConfig::default();
    assert_eq!(config.max_retries, 3);
    assert_eq!(config.initial_delay, Duration::from_secs(1));
    assert_eq!(config.max_delay, Duration::from_secs(60));
    assert_eq!(config.multiplier, 2.0);
    assert!((config.jitter - 0.1).abs() < 0.01);
}

#[test]
fn test_retry_config_exponential_backoff() {
    let config = RetryConfig {
        max_retries: 5,
        initial_delay: Duration::from_secs(1),
        max_delay: Duration::from_secs(30),
        multiplier: 2.0,
        jitter: 0.0, // No jitter for deterministic test
    };

    // 1 * 2^0 = 1s
    let d0 = config.get_delay(0);
    assert_eq!(d0, Duration::from_secs(1));

    // 1 * 2^1 = 2s
    let d1 = config.get_delay(1);
    assert_eq!(d1, Duration::from_secs(2));

    // 1 * 2^2 = 4s
    let d2 = config.get_delay(2);
    assert_eq!(d2, Duration::from_secs(4));
}

#[test]
fn test_retry_config_capped_at_max() {
    let config = RetryConfig {
        max_retries: 10,
        initial_delay: Duration::from_secs(1),
        max_delay: Duration::from_secs(10),
        multiplier: 2.0,
        jitter: 0.0,
    };

    // 1 * 2^5 = 32s, but capped at 10s
    let delay = config.get_delay(5);
    assert_eq!(delay, Duration::from_secs(10));
}

#[test]
fn test_retry_config_with_jitter() {
    let config = RetryConfig {
        max_retries: 3,
        initial_delay: Duration::from_secs(10),
        max_delay: Duration::from_secs(60),
        multiplier: 2.0,
        jitter: 0.2, // 20% jitter
    };

    // Run multiple times to see jitter effect
    let delays: Vec<Duration> = (0..10).map(|_| config.get_delay(0)).collect();

    // All delays should be around 10s ± 2s (20% of 10s)
    for delay in delays {
        let secs = delay.as_secs_f64();
        assert!(secs >= 8.0 && secs <= 12.0, "Delay {} not in expected range", secs);
    }
}

// ============================================================================
// CircuitState Tests
// ============================================================================

#[test]
fn test_circuit_state_variants() {
    let closed = CircuitState::Closed;
    let open = CircuitState::Open;
    let half_open = CircuitState::HalfOpen;

    assert_eq!(closed, CircuitState::Closed);
    assert_eq!(open, CircuitState::Open);
    assert_eq!(half_open, CircuitState::HalfOpen);

    assert_ne!(closed, open);
    assert_ne!(open, half_open);
}

#[test]
fn test_circuit_state_copy() {
    let state = CircuitState::Closed;
    let copied = state;
    assert_eq!(state, copied);
}

// ============================================================================
// RemediationMethod Tests
// ============================================================================

#[test]
fn test_remediation_method_variants() {
    let auto = RemediationMethod::ClaudeAuto;
    let assisted = RemediationMethod::ClaudeAssisted;
    let manual = RemediationMethod::ManualRequired;
    let skipped = RemediationMethod::Skipped;

    // Just verify they can be created
    let _ = (auto, assisted, manual, skipped);
}

// ============================================================================
// ChangeType Tests
// ============================================================================

#[test]
fn test_change_type_variants() {
    let created = ChangeType::Created;
    let modified = ChangeType::Modified;
    let deleted = ChangeType::Deleted;

    // Just verify they can be created
    let _ = (created, modified, deleted);
}

// ============================================================================
// FileChange Tests
// ============================================================================

#[test]
fn test_file_change_created() {
    let change = FileChange {
        path: PathBuf::from("src/new_file.rs"),
        change_type: ChangeType::Created,
        diff: Some("+fn new_function() {}".to_string()),
        size_bytes: 100,
    };

    assert_eq!(change.path, PathBuf::from("src/new_file.rs"));
    assert!(matches!(change.change_type, ChangeType::Created));
    assert!(change.diff.is_some());
    assert_eq!(change.size_bytes, 100);
}

#[test]
fn test_file_change_modified() {
    let change = FileChange {
        path: PathBuf::from("src/existing.rs"),
        change_type: ChangeType::Modified,
        diff: Some("@@ -10,3 +10,5 @@\n+added line".to_string()),
        size_bytes: 500,
    };

    assert!(matches!(change.change_type, ChangeType::Modified));
}

#[test]
fn test_file_change_deleted() {
    let change = FileChange {
        path: PathBuf::from("src/old_file.rs"),
        change_type: ChangeType::Deleted,
        diff: None,
        size_bytes: 0,
    };

    assert!(matches!(change.change_type, ChangeType::Deleted));
    assert!(change.diff.is_none());
}

// ============================================================================
// RemediationResult Tests
// ============================================================================

#[test]
fn test_remediation_result_success() {
    let result = RemediationResult {
        success: true,
        method: RemediationMethod::ClaudeAuto,
        changes_made: vec![FileChange {
            path: PathBuf::from("fix.sh"),
            change_type: ChangeType::Modified,
            diff: Some("fix".to_string()),
            size_bytes: 50,
        }],
        commit_sha: Some("abc123".to_string()),
        pr_url: Some("https://github.com/org/repo/pull/1".to_string()),
        duration_ms: 5000,
        claude_output: "Fixed the issue".to_string(),
        estimated_cost_usd: 0.05,
        verification_passed: true,
    };

    assert!(result.success);
    assert!(matches!(result.method, RemediationMethod::ClaudeAuto));
    assert_eq!(result.changes_made.len(), 1);
    assert!(result.commit_sha.is_some());
    assert!(result.pr_url.is_some());
    assert!(result.verification_passed);
}

#[test]
fn test_remediation_result_manual() {
    let result = RemediationResult {
        success: false,
        method: RemediationMethod::ManualRequired,
        changes_made: vec![],
        commit_sha: None,
        pr_url: None,
        duration_ms: 100,
        claude_output: "Manual intervention required".to_string(),
        estimated_cost_usd: 0.0,
        verification_passed: false,
    };

    assert!(!result.success);
    assert!(matches!(result.method, RemediationMethod::ManualRequired));
    assert!(result.changes_made.is_empty());
    assert!(result.commit_sha.is_none());
}

// ============================================================================
// FallbackSuggestion Tests
// ============================================================================

#[test]
fn test_fallback_suggestion_fields() {
    let suggestion = FallbackSuggestion {
        title: "Check permissions".to_string(),
        description: "Run chmod to fix permissions".to_string(),
        commands: vec!["chmod +x script.sh".to_string()],
        documentation_url: Some("https://docs.example.com".to_string()),
    };

    assert_eq!(suggestion.title, "Check permissions");
    assert!(!suggestion.description.is_empty());
    assert_eq!(suggestion.commands.len(), 1);
    assert!(suggestion.documentation_url.is_some());
}

#[test]
fn test_fallback_suggestion_no_url() {
    let suggestion = FallbackSuggestion {
        title: "Retry".to_string(),
        description: "Try again".to_string(),
        commands: vec![],
        documentation_url: None,
    };

    assert!(suggestion.documentation_url.is_none());
    assert!(suggestion.commands.is_empty());
}

// ============================================================================
// SafetyCheck Tests
// ============================================================================

#[test]
fn test_safety_check_safe() {
    let check = SafetyCheck {
        safe: true,
        reason: None,
        risk_level: automated_flywheel_setup_checker::remediation::RiskLevel::Safe,
    };

    assert!(check.safe);
    assert!(check.reason.is_none());
}

#[test]
fn test_safety_check_unsafe() {
    let check = SafetyCheck {
        safe: false,
        reason: Some("Dangerous command".to_string()),
        risk_level: automated_flywheel_setup_checker::remediation::RiskLevel::Critical,
    };

    assert!(!check.safe);
    assert!(check.reason.is_some());
}

// ============================================================================
// Serialization Tests
// ============================================================================

#[test]
fn test_circuit_state_serializable() {
    let state = CircuitState::Closed;
    let json = serde_json::to_string(&state).unwrap();
    assert!(json.contains("Closed"));
}

#[test]
fn test_remediation_method_serializable() {
    let method = RemediationMethod::ClaudeAuto;
    let json = serde_json::to_string(&method).unwrap();
    assert!(json.contains("ClaudeAuto"));
}

#[test]
fn test_change_type_serializable() {
    let change = ChangeType::Modified;
    let json = serde_json::to_string(&change).unwrap();
    assert!(json.contains("Modified"));
}

#[test]
fn test_file_change_serializable() {
    let change = FileChange {
        path: PathBuf::from("test.rs"),
        change_type: ChangeType::Created,
        diff: None,
        size_bytes: 0,
    };

    let json = serde_json::to_string(&change).unwrap();
    assert!(json.contains("test.rs"));
}

#[test]
fn test_remediation_result_serializable() {
    let result = RemediationResult {
        success: true,
        method: RemediationMethod::ClaudeAuto,
        changes_made: vec![],
        commit_sha: None,
        pr_url: None,
        duration_ms: 0,
        claude_output: String::new(),
        estimated_cost_usd: 0.0,
        verification_passed: false,
    };

    let json = serde_json::to_string(&result).unwrap();
    assert!(json.contains("\"success\":true"));
}
