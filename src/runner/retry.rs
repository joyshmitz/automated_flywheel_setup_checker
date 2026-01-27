//! Retry logic with backoff

use serde::{Deserialize, Serialize};
use std::time::Duration;

/// Retry strategy configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RetryStrategy {
    /// Fixed delay between retries
    Fixed { delay: Duration },
    /// Exponential backoff
    Exponential { initial_delay: Duration, max_delay: Duration, multiplier: f64 },
}

impl Default for RetryStrategy {
    fn default() -> Self {
        RetryStrategy::Exponential {
            initial_delay: Duration::from_secs(1),
            max_delay: Duration::from_secs(60),
            multiplier: 2.0,
        }
    }
}

/// Retry configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RetryConfig {
    pub max_attempts: u32,
    pub strategy: RetryStrategy,
    pub retry_transient_only: bool,
}

impl Default for RetryConfig {
    fn default() -> Self {
        Self { max_attempts: 3, strategy: RetryStrategy::default(), retry_transient_only: true }
    }
}

impl RetryConfig {
    /// Calculate delay for a given attempt number
    pub fn delay_for_attempt(&self, attempt: u32) -> Duration {
        match &self.strategy {
            RetryStrategy::Fixed { delay } => *delay,
            RetryStrategy::Exponential { initial_delay, max_delay, multiplier } => {
                let delay = initial_delay.as_secs_f64() * multiplier.powi(attempt as i32);
                Duration::from_secs_f64(delay.min(max_delay.as_secs_f64()))
            }
        }
    }

    /// Check if we should retry
    pub fn should_retry(&self, attempt: u32) -> bool {
        attempt < self.max_attempts
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fixed_strategy() {
        let config = RetryConfig {
            max_attempts: 3,
            strategy: RetryStrategy::Fixed { delay: Duration::from_secs(5) },
            retry_transient_only: true,
        };

        assert_eq!(config.delay_for_attempt(0), Duration::from_secs(5));
        assert_eq!(config.delay_for_attempt(2), Duration::from_secs(5));
    }

    #[test]
    fn test_exponential_strategy() {
        let config = RetryConfig::default();

        // First retry: 1 * 2^0 = 1s
        assert_eq!(config.delay_for_attempt(0), Duration::from_secs(1));
        // Second retry: 1 * 2^1 = 2s
        assert_eq!(config.delay_for_attempt(1), Duration::from_secs(2));
        // Third retry: 1 * 2^2 = 4s
        assert_eq!(config.delay_for_attempt(2), Duration::from_secs(4));
    }

    #[test]
    fn test_should_retry() {
        let config = RetryConfig { max_attempts: 3, ..Default::default() };

        assert!(config.should_retry(0));
        assert!(config.should_retry(2));
        assert!(!config.should_retry(3));
    }
}
