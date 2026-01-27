//! Run summary generation

use crate::runner::{TestResult, TestStatus};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::time::Duration;

/// Summary of a test run
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunSummary {
    pub run_id: String,
    pub started_at: DateTime<Utc>,
    pub finished_at: DateTime<Utc>,
    pub total_duration: Duration,
    pub total_tests: usize,
    pub passed: usize,
    pub failed: usize,
    pub skipped: usize,
    pub timed_out: usize,
    pub success_rate: f64,
    pub failures: Vec<FailureSummary>,
}

/// Summary of a single failure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FailureSummary {
    pub installer_name: String,
    pub error_category: String,
    pub error_message: String,
    pub duration: Duration,
    pub retries: u32,
}

/// Generates run summaries from test results
pub struct SummaryGenerator {
    run_id: String,
    started_at: DateTime<Utc>,
}

impl SummaryGenerator {
    pub fn new(run_id: impl Into<String>) -> Self {
        Self { run_id: run_id.into(), started_at: Utc::now() }
    }

    /// Generate a summary from test results
    pub fn generate(&self, results: &[TestResult]) -> RunSummary {
        let finished_at = Utc::now();
        let total_duration = (finished_at - self.started_at).to_std().unwrap_or(Duration::ZERO);

        let total_tests = results.len();
        let passed = results.iter().filter(|r| r.status == TestStatus::Passed).count();
        let failed = results.iter().filter(|r| r.status == TestStatus::Failed).count();
        let skipped = results.iter().filter(|r| r.status == TestStatus::Skipped).count();
        let timed_out = results.iter().filter(|r| r.status == TestStatus::TimedOut).count();

        let success_rate =
            if total_tests > 0 { passed as f64 / total_tests as f64 * 100.0 } else { 0.0 };

        let failures: Vec<FailureSummary> = results
            .iter()
            .filter(|r| r.status == TestStatus::Failed || r.status == TestStatus::TimedOut)
            .map(|r| FailureSummary {
                installer_name: r.installer_name.clone(),
                error_category: r
                    .error
                    .as_ref()
                    .map(|e| e.category.clone())
                    .unwrap_or_else(|| "unknown".to_string()),
                error_message: r.stderr.clone(),
                duration: r.duration,
                retries: r.retry_count(),
            })
            .collect();

        RunSummary {
            run_id: self.run_id.clone(),
            started_at: self.started_at,
            finished_at,
            total_duration,
            total_tests,
            passed,
            failed,
            skipped,
            timed_out,
            success_rate,
            failures,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_summary_generation() {
        let generator = SummaryGenerator::new("test-run-1");

        let results = vec![
            TestResult::new("installer1").passed(),
            TestResult::new("installer2").passed(),
            TestResult::new("installer3").failed(1, "error"),
        ];

        let summary = generator.generate(&results);

        assert_eq!(summary.total_tests, 3);
        assert_eq!(summary.passed, 2);
        assert_eq!(summary.failed, 1);
        assert!((summary.success_rate - 66.66666).abs() < 1.0);
    }
}
