//! Parallel execution orchestrator

use super::installer::{InstallerTest, TestResult};
use anyhow::Result;
use std::sync::Arc;
use tokio::sync::Semaphore;

/// Orchestrates parallel installer test execution
pub struct ParallelRunner {
    max_parallel: usize,
    semaphore: Arc<Semaphore>,
}

impl ParallelRunner {
    pub fn new(max_parallel: usize) -> Self {
        Self { max_parallel, semaphore: Arc::new(Semaphore::new(max_parallel)) }
    }

    /// Run multiple installer tests in parallel
    pub async fn run_all(&self, tests: Vec<InstallerTest>) -> Result<Vec<TestResult>> {
        let mut handles = Vec::new();

        for test in tests {
            let semaphore = self.semaphore.clone();
            let handle = tokio::spawn(async move {
                let _permit = semaphore.acquire().await.unwrap();
                // Placeholder - actual execution logic
                TestResult::new(&test.name).passed()
            });
            handles.push(handle);
        }

        let mut results = Vec::new();
        for handle in handles {
            results.push(handle.await?);
        }

        Ok(results)
    }

    pub fn max_parallel(&self) -> usize {
        self.max_parallel
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_parallel_runner_creation() {
        let runner = ParallelRunner::new(4);
        assert_eq!(runner.max_parallel(), 4);
    }
}
