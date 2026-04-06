//! Installer test runner module

mod container;
mod executor;
mod installer;
mod parallel;
mod retry;

pub use container::{ContainerConfig, ContainerGuard, ContainerManager, PullPolicy};
pub use executor::{ExecutionBackend, InstallerTestRunner, RunnerConfig};
pub use installer::{ChecksumResult, InstallerTest, TestResult, TestStatus};
pub use parallel::ParallelRunner;
pub use retry::{RetryConfig, RetryStrategy};
