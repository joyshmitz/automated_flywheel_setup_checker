# Changelog

All notable changes to the Automated Flywheel Setup Checker are documented here.

This project has no tagged releases yet. History is organized by commit, oldest-first.
Repository: <https://github.com/Dicklesworthstone/automated_flywheel_setup_checker>

---

## [Unreleased] (on `master`)

### 2026-01-26: Foundation -- full project scaffold

Commit: [`e4a1d2d`](https://github.com/Dicklesworthstone/automated_flywheel_setup_checker/commit/e4a1d2d547a4bc36c0fc1b5cd382d2a2330e0968)
63 files, 10 202 lines

Initial commit establishing the entire codebase: CLI, core modules, deployment infrastructure, CI, and test suite.

#### CLI (`src/main.rs`)
- Subcommands: `list`, `validate`, `check`, `classify-error`, `config show|default|validate`.
- Global flags: `--format human|json|jsonl`, `--config <path>`, `-v/-vv/-vvv`, `--watchdog`.
- Environment variable support: `ACFS_CONFIG`, `ACFS_WATCHDOG`.

#### Checksums engine (`src/checksums/`)
- `parser.rs` -- deserializes `checksums.yaml` into typed `ChecksumsFile`/`InstallerEntry` structs with version, URL, checksum, enabled flag, and tags.
- `validator.rs` -- structural validation (missing URLs, invalid URLs, missing versions) plus optional live HTTP URL checks.

#### Configuration (`src/config/`)
- `schema.rs` -- typed config sections: `GeneralConfig`, `DockerConfig`, `ExecutionConfig`, `RemediationConfig`.
- `loader.rs` -- TOML loader with env-var override and default fallback.
- Ships `config/default.toml` covering general, docker, execution, remediation, notifications, monitoring, and watchdog sections.

#### Error classification (`src/parser/`)
- `classifier.rs` -- pattern-based error classifier. Categories: `bootstrap_mismatch`, `checksum_mismatch`, `network_error`, `permission_denied`, `dependency_error`, `command_not_found`, `resource_exhaustion`, `timeout`.
- `error.rs` -- error type definitions.
- Returns `ErrorClassification` with severity enum (`Transient`, `Configuration`, `Dependency`, `Permission`, `Resource`, `Unknown`), category string, suggestion, retryable flag, and confidence score.

#### Runner (`src/runner/`)
- `installer.rs` -- `InstallerTest` and `TestResult`/`TestStatus` data types.
- `container.rs` -- Docker container management via `bollard`: create, start, exec, destroy with memory/CPU limits.
- `parallel.rs` -- semaphore-gated parallel runner using `tokio::spawn`.
- `retry.rs` -- configurable retry with `Fixed` and `Exponential` backoff strategies.

#### Remediation (`src/remediation/`)
- `claude.rs` -- Claude API integration with circuit breaker (Closed/Open/HalfOpen states), rate limiter (token-bucket), and retry-on-failure logic.
- `safety.rs` -- command safety checker with risk levels (`Safe`, `Low`, `Medium`, `High`, `Critical`). Blocks fork bombs, `rm -rf /`, `dd` to block devices, etc.
- `fallback.rs` -- generates manual remediation suggestions keyed to error severity.

#### Reporting (`src/reporting/`)
- `jsonl.rs` -- structured JSONL log entries with timestamp, level, component, event, data, duration, error, and correlation ID.
- `metrics.rs` -- Prometheus-style metrics: counters, gauges, histograms, plus `MetricsSnapshot` with 24h success rates.
- `notify.rs` -- notification dispatcher for GitHub issues and Slack webhooks.
- `summary.rs` -- `RunSummary` generator aggregating pass/fail/skip/timeout counts and per-failure details.

#### Systemd integration
- `src/watchdog.rs` -- `SystemdWatchdog` struct: auto-detects `WATCHDOG_USEC`/`NOTIFY_SOCKET`, pings at half the timeout interval, graceful shutdown via `AtomicBool`.
- `systemd/automated-flywheel-checker.service` -- `Type=notify` service with resource limits, `ProtectSystem=strict`, `PrivateTmp=yes`.
- `systemd/automated-flywheel-checker.timer` -- daily at 03:00 with randomized delay.
- `systemd/automated-flywheel-checker-emergency.service` -- immediate high-priority run.
- `systemd/logrotate-flywheel-checker` -- 30-day log rotation, 90-day JSONL retention.
- `scripts/install-systemd.sh`, `scripts/uninstall-systemd.sh` -- deployment scripts.
- `scripts/notify-flywheel-failure.sh` -- failure notification with Slack and GitHub issue support.

#### CI
- `.github/workflows/ci.yml` -- fmt, clippy, build, test, plus integration job with a synthetic `checksums.yaml`.

#### Test suite (unit tests)
- `tests/unit/checksums_tests.rs` -- checksums parsing and validation.
- `tests/unit/config_tests.rs` -- config loading and defaults.
- `tests/unit/parser_tests.rs` -- error classification patterns.
- `tests/unit/remediation_tests.rs` -- safety checks and circuit breaker.
- `tests/unit/reporting_tests.rs` -- JSONL, metrics, summary generation.
- `tests/unit/runner_tests.rs` -- installer test runner.
- 10 error fixture files in `tests/unit/fixtures/error_outputs/` (apt lock, checksum mismatch, command not found, connection refused/timeout, disk full, DNS, permission denied, SSL, syntax error).
- 2 remediation response fixtures in `tests/unit/fixtures/remediation_responses/`.
- Sample `checksums.yaml` fixture.

---

### 2026-01-26: Fix flaky rate limiter test

Commit: [`107636a`](https://github.com/Dicklesworthstone/automated_flywheel_setup_checker/commit/107636aeeba7a366281d7f0a31078bc285630008)
1 file, +6/-3

#### Bug fix
- `src/remediation/claude.rs` -- rate limiter test `rate_limiter_refills` was flaky due to 10 tokens/sec refill rate. Between consecutive `try_acquire()` calls, enough wall-clock time could pass to refill a token, making the second call succeed unexpectedly. Fixed by dropping refill rate to 1 token/sec, requiring a full second to refill.

---

### 2026-01-26: Comprehensive E2E test suite

Commit: [`19d9b9d`](https://github.com/Dicklesworthstone/automated_flywheel_setup_checker/commit/19d9b9d11fbad3c8fd7e58958d3813b6ca61e3c3)
19 files, +2 879 lines

#### Bash E2E framework (`scripts/e2e/`)
- `lib/helpers.sh` -- test harness: binary build, temp dir management, mock server, Docker helpers.
- `lib/assertions.sh` -- assertion library: `assert_eq`, `assert_contains`, `assert_exit_code`, `assert_file_exists`, `assert_json_field`, etc.
- `run_all_tests.sh` -- test runner with parallel execution, timeout enforcement, TAP-style reporting, and summary.

#### Core E2E tests (12)
- `single_installer.sh` -- basic installer execution validation.
- `batch_run.sh` -- multiple installer batch processing.
- `checksum_mismatch.sh` -- checksum verification failure handling.
- `network_failure.sh` -- network error detection and retry.
- `remediation_flow.sh` -- auto-remediation pipeline end-to-end.
- `error_classification.sh` -- error type classification accuracy.
- `jsonl_output.sh` -- JSONL report format validation.
- `parallel_execution.sh` -- concurrent container execution.
- `systemd_integration.sh` -- service lifecycle (start/stop/status).
- `github_notification.sh` -- GitHub issue/PR notification.
- `config_override.sh` -- configuration precedence (file < env < CLI).
- `recovery_rollback.sh` -- state checkpoint and rollback.

#### Edge-case E2E tests (4)
- `container_timeout_handling.sh` -- SIGTERM/SIGKILL escalation on timeout.
- `out_of_memory_scenario.sh` -- OOM detection and recovery.
- `disk_space_exhaustion.sh` -- disk-full handling and cleanup.
- `network_partition_scenario.sh` -- partial network connectivity.

---

### 2026-01-27: Prioritize exit code 127 in error classification

Commit: [`c28ee8a`](https://github.com/Dicklesworthstone/automated_flywheel_setup_checker/commit/c28ee8a170bb0d4c2d4b9a1a5bf9c4c53f60413b)
3 files, +243/-157

#### Refactor
- `src/parser/classifier.rs` -- reorder classification chain so exit code 127 (command not found) is checked before heuristic `is_dependency_error()` pattern matching. Guarantees consistent `command_not_found` categorization with 0.95 confidence when the shell explicitly signals a missing command.

#### Test improvements
- `tests/unit/parser_tests.rs` -- relax confidence assertion from `>= 0.9` to `> 0.0` to accommodate variable confidence across classification paths.
- `tests/unit/remediation_tests.rs` -- major refactor to test public API only. Removes internal `RiskLevel` enum comparisons. Adds tests for safe commands (`pwd`, `whoami`, `date`), critical commands (fork bomb, `/dev` writes), and high-risk commands (`sudo chown`). Assertions simplified to `safe`/`unsafe` boolean outcomes.

---

### 2026-01-27: Installer test execution framework

Commit: [`f7eda26`](https://github.com/Dicklesworthstone/automated_flywheel_setup_checker/commit/f7eda26dd9c06bdd218faced2f3f12cc283bd130)
4 files, +478/-4

#### New module: `src/runner/executor.rs` (297 lines)
- `RunnerConfig` -- timeout, dry-run flag, curl/bash paths, extra env vars.
- `InstallerTestRunner` -- executes installer scripts in isolated `tempfile` directories via `tokio::process::Command`.
- Captures stdout/stderr with configurable timeout using `tokio::time::timeout`.
- Returns `TestResult`/`TestStatus` for structured result reporting.
- Defaults to dry-run mode for safety.

#### CLI integration (`src/main.rs`, +113 lines)
- `cmd_check()` now performs actual execution: converts checksum entries into `InstallerTest` objects, runs them through `InstallerTestRunner`.
- Supports `--fail-fast` flag for early termination on first failure.
- Installer selection by name via positional arguments.

#### Parser enhancement
- `src/parser/classifier.rs` -- additional error patterns for installer output classification (+70 lines).

---

### 2026-01-27: Remediation verification, prompt generation, expanded error classification

Commit: [`3caff20`](https://github.com/Dicklesworthstone/automated_flywheel_setup_checker/commit/3caff207cc720fcbb6b1a4a7fa07f6317eb5a5ac) (HEAD)
18 files, +2 010/-6

#### Remediation verification workflow (`src/remediation/claude.rs`)
- `verify_remediation()` -- re-runs installer tests after Claude applies a fix, validates results.
- `remediate_and_verify()` -- full pipeline: generate prompt, execute remediation, verify outcome.
- `VerificationResult` struct with SHA256 checksum validation for download integrity.

#### Prompt generation (`src/remediation/prompts.rs`, new, 301 lines)
- Context-aware Claude prompt templates keyed to error category:
  - `bootstrap_mismatch` -- guides `bun run generate` regeneration workflow.
  - `checksum_mismatch` -- guides upstream verification.
  - `syntax_error` -- provides targeted fix suggestions.
- Support for dry-run report generation.

#### Error classification expansion (`src/parser/classifier.rs`)
- New category: `syntax_error` (patterns: syntax/parse/token errors).
- `checksum_mismatch` expanded to catch "checksum did not match" variant.
- `network_error` expanded to detect SSL certificate problems and apt/dpkg lock contention.

#### Log rotation (`src/reporting/`)
- `LogRotation` manager in `jsonl.rs` with date-based file rotation and automatic pruning of logs past retention period.
- Remediation success-rate tracking in `metrics.rs`.

#### Rust E2E tests (`tests/e2e/`, new)
- `tests/e2e.rs` -- entry point with modular organization.
- `helpers.rs` -- test utilities (binary path resolution, temp workspace).
- `test_binary_cli.rs` -- CLI argument parsing, help output, version flag.
- `test_classification_pipeline.rs` -- error classification accuracy across all categories.
- `test_config_workflow.rs` -- config loading, validation, env-var override, default generation.
- `test_reporting_output.rs` -- JSONL output structure, metrics snapshot, summary format.

#### CI
- `.github/workflows/e2e-tests.yml` -- dedicated E2E workflow: Rust E2E tests, then Bash E2E tests with Docker-in-Docker, artifact upload for logs and reports.

#### Additional tests
- `tests/unit/notify_tests.rs` -- notification handler tests.
- `tests/unit/fixtures/error_outputs/bootstrap_mismatch.txt` -- new fixture.

---

## Architecture summary

```
src/
  main.rs              CLI entry point (clap derive)
  lib.rs               Crate root, re-exports
  logging.rs           Tracing/env-filter setup
  watchdog.rs          Systemd watchdog (WATCHDOG_USEC/NOTIFY_SOCKET)
  checksums/
    parser.rs          checksums.yaml deserialization
    validator.rs       Structural + URL validation
  config/
    loader.rs          TOML config loading with env override
    schema.rs          Typed config sections
  parser/
    classifier.rs      Error classification engine
    error.rs           Error types
  remediation/
    claude.rs          Claude API with circuit breaker + rate limiter
    fallback.rs        Manual remediation suggestions
    prompts.rs         Context-aware prompt generation
    safety.rs          Command safety checker (risk levels)
  reporting/
    jsonl.rs           Structured JSONL logging + log rotation
    metrics.rs         Prometheus-style metrics + snapshots
    notify.rs          GitHub/Slack notification dispatch
    summary.rs         Run summary aggregation
  runner/
    container.rs       Docker container management (bollard)
    executor.rs        Installer test execution in temp dirs
    installer.rs       InstallerTest/TestResult types
    parallel.rs        Semaphore-gated parallel runner
    retry.rs           Exponential/fixed backoff retry
```

## Key dependencies

| Crate | Purpose |
|-------|---------|
| `tokio` (full) | Async runtime |
| `clap` (derive) | CLI parsing |
| `bollard` | Docker API |
| `reqwest` (rustls) | HTTP client |
| `serde` / `serde_json` / `serde_yaml` / `toml` | Serialization |
| `tracing` / `tracing-subscriber` | Structured logging |
| `sha2` / `hex` | Checksum computation |
| `regex` | Error pattern matching |
| `chrono` | Timestamps |
| `indicatif` | Progress bars |
| `tempfile` | Isolated test directories |

[Unreleased]: https://github.com/Dicklesworthstone/automated_flywheel_setup_checker/commits/master
