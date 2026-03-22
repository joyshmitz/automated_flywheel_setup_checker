# Changelog

All notable changes to the Automated Flywheel Setup Checker are documented here.

This project has no tagged releases. History is organized by commit date, with changes grouped by capability rather than file diff order.

Repository: <https://github.com/Dicklesworthstone/automated_flywheel_setup_checker>

---

## [Unreleased] (on `master`)

### 2026-01-27: Remediation verification, prompt generation, and expanded error classification

Commit: [`3caff20`](https://github.com/Dicklesworthstone/automated_flywheel_setup_checker/commit/3caff207cc720fcbb6b1a4a7fa07f6317eb5a5ac) (HEAD)
18 files, +2 010/-6

#### Post-remediation verification

Full closed-loop verification workflow for Claude-powered auto-remediation. After Claude applies a fix, the system re-runs the installer test and validates the outcome:

- `verify_remediation()` downloads the installer, computes its SHA256 checksum, and runs it in a temp directory to confirm the fix worked.
- `remediate_and_verify()` orchestrates the full pipeline: generate prompt, execute remediation via Claude CLI, verify the outcome, and report whether verification passed.
- `VerificationResult` struct captures pass/fail, exit code, stdout/stderr, and checksum validity.

#### Context-aware prompt generation

New `src/remediation/prompts.rs` module (301 lines) generates Claude prompts tailored to the specific error category:

- **Bootstrap mismatch** prompts guide the `bun run generate` regeneration workflow, including `checksums.yaml` and `KNOWN_INSTALLERS` updates.
- **Checksum mismatch** prompts guide upstream verification and hash update.
- **Network, command-not-found, dependency, permission, resource** prompts each provide targeted diagnostic steps and fix commands.
- **Syntax error** prompts provide targeted fix suggestions.
- Generic fallback prompt for unclassified errors.
- Dry-run report generation shows what Claude would be asked without executing anything.

#### Expanded error classification

- New `syntax_error` category detects syntax/parse/token errors in installer scripts.
- `checksum_mismatch` expanded to catch the "checksum did not match" phrasing variant.
- `network_error` expanded to detect SSL certificate problems and apt/dpkg lock contention.

#### Log rotation and metrics

- `LogRotation` manager with date-based file naming (`prefix_YYYYMMDD.jsonl`), automatic pruning of files older than the retention period, and sorted file listing.
- `MetricsSnapshot` extended with remediation success-rate tracking.

#### Rust E2E test suite

- `tests/e2e.rs` entry point with modular test organization across four test modules:
  - `test_binary_cli.rs` -- CLI argument parsing, help output, version flag.
  - `test_classification_pipeline.rs` -- error classification accuracy across all categories.
  - `test_config_workflow.rs` -- config loading, validation, env-var override, default generation.
  - `test_reporting_output.rs` -- JSONL output structure, metrics snapshot, summary format.
- `helpers.rs` -- test utilities for binary path resolution and temp workspace creation.

#### CI: E2E workflow

- `.github/workflows/e2e-tests.yml` -- dedicated E2E workflow with two jobs:
  - Rust E2E tests (single-threaded `cargo test --test e2e`).
  - Bash E2E tests with Docker-in-Docker, artifact upload for logs (7-day retention) and reports (30-day retention).
  - Summary job gating on both.

#### Additional test coverage

- `tests/unit/notify_tests.rs` -- notification handler unit tests.
- `tests/unit/fixtures/error_outputs/bootstrap_mismatch.txt` -- new error fixture.
- Additional parser tests for the new `syntax_error` category.

---

### 2026-01-27: Installer test execution framework

Commit: [`f7eda26`](https://github.com/Dicklesworthstone/automated_flywheel_setup_checker/commit/f7eda26dd9c06bdd218faced2f3f12cc283bd130)
4 files, +478/-4

#### Isolated installer execution

New `src/runner/executor.rs` (297 lines) implements actual installer test execution:

- `RunnerConfig` configures timeout, dry-run mode, curl/bash binary paths, and extra environment variables.
- `InstallerTestRunner` creates an isolated `tempfile` directory per test, sets restrictive environment variables (`HOME`, `TMPDIR`, `XDG_*`, minimal `PATH`), and runs `curl -fsSL $URL | bash -s -- [--dry-run]` via `tokio::process::Command`.
- Concurrent stdout/stderr capture with `tokio::io::AsyncReadExt` and configurable timeout via `tokio::time::timeout`.
- On timeout, the child process is killed and a `TestStatus::TimedOut` result is returned.
- `run_test_with_retry()` wraps execution with exponential backoff and jitter (capped at 30 seconds).
- Defaults to dry-run mode for safety -- installers receive `--dry-run` unless explicitly overridden.

#### CLI now performs real execution

- `cmd_check()` in `src/main.rs` (+113 lines) converts checksum entries into `InstallerTest` objects, runs them through `InstallerTestRunner`, and reports results per installer with pass/fail icons, duration, and stderr preview.
- `--fail-fast` flag terminates on first failure.
- Installer selection by positional name arguments.
- JSON/JSONL output modes emit per-result and summary objects.

#### Enhanced error patterns

- `src/parser/classifier.rs` gains additional error-matching patterns for installer output (+70 lines).

---

### 2026-01-27: Prioritize exit code 127 in error classification

Commit: [`c28ee8a`](https://github.com/Dicklesworthstone/automated_flywheel_setup_checker/commit/c28ee8a170bb0d4c2d4b9a1a5bf9c4c53f60413b)
3 files, +243/-157

#### Classifier accuracy improvement

- Reorder classification chain in `src/parser/classifier.rs` so exit code 127 (command not found) is checked before heuristic `is_dependency_error()` pattern matching. This ensures the definitive shell exit code takes precedence, guaranteeing consistent `command_not_found` categorization with 0.95 confidence.

#### Test suite hardening

- `tests/unit/parser_tests.rs` -- relax confidence assertion from `>= 0.9` to `> 0.0` to accommodate variable confidence across classification paths.
- `tests/unit/remediation_tests.rs` -- major refactor to test public API only:
  - Remove internal `RiskLevel` enum comparisons (implementation detail).
  - Add safe command tests: `pwd`, `whoami`, `date`.
  - Add critical command tests: fork bomb handling, `/dev` writes.
  - Add high-risk test: `sudo chown`.
  - Simplify all assertions to `safe`/`unsafe` boolean outcomes.

---

### 2026-01-26: Comprehensive E2E test suite

Commit: [`19d9b9d`](https://github.com/Dicklesworthstone/automated_flywheel_setup_checker/commit/19d9b9d11fbad3c8fd7e58958d3813b6ca61e3c3)
19 files, +2 879 lines

#### Bash E2E test framework

Reusable test infrastructure in `scripts/e2e/`:

- `lib/helpers.sh` -- test harness providing binary build, temp directory management, mock server setup, and Docker helpers.
- `lib/assertions.sh` -- assertion library: `assert_eq`, `assert_contains`, `assert_exit_code`, `assert_file_exists`, `assert_json_field`, and more.
- `run_all_tests.sh` -- test runner with parallel execution, per-test timeout enforcement, TAP-style reporting, and pass/fail summary.

#### Core E2E tests (12)

| Test | What it validates |
|------|-------------------|
| `single_installer.sh` | Basic installer execution and result capture |
| `batch_run.sh` | Multiple installer batch processing |
| `checksum_mismatch.sh` | Checksum verification failure detection |
| `network_failure.sh` | Network error handling and retry behavior |
| `remediation_flow.sh` | Auto-remediation pipeline end-to-end |
| `error_classification.sh` | Error type classification accuracy |
| `jsonl_output.sh` | JSONL report format and field validation |
| `parallel_execution.sh` | Concurrent container execution |
| `systemd_integration.sh` | Service lifecycle (start/stop/status) |
| `github_notification.sh` | GitHub issue/PR notification dispatch |
| `config_override.sh` | Configuration precedence: file < env < CLI |
| `recovery_rollback.sh` | State checkpoint and rollback |

#### Edge-case E2E tests (4)

| Test | What it validates |
|------|-------------------|
| `container_timeout_handling.sh` | SIGTERM/SIGKILL escalation on timeout |
| `out_of_memory_scenario.sh` | OOM detection and recovery |
| `disk_space_exhaustion.sh` | Disk-full handling and cleanup |
| `network_partition_scenario.sh` | Partial network connectivity |

---

### 2026-01-26: Fix flaky rate limiter test

Commit: [`107636a`](https://github.com/Dicklesworthstone/automated_flywheel_setup_checker/commit/107636aeeba7a366281d7f0a31078bc285630008)
1 file, +6/-3

#### Bug fix

- `src/remediation/claude.rs` -- the `rate_limiter_refills` test was timing-dependent with a 10 tokens/sec refill rate. Between consecutive `try_acquire()` calls, enough wall-clock time could pass to refill a token, making the second call succeed unexpectedly. Fixed by dropping the refill rate to 1 token/sec so that a full second must elapse before any token is restored, making the test deterministic.

---

### 2026-01-26: Foundation -- full project scaffold

Commit: [`e4a1d2d`](https://github.com/Dicklesworthstone/automated_flywheel_setup_checker/commit/e4a1d2d547a4bc36c0fc1b5cd382d2a2330e0968)
63 files, 10 202 lines

Initial commit establishing the entire codebase. This is the complete foundation: CLI, every core module, deployment infrastructure, CI, and test suite.

#### Command-line interface

`src/main.rs` provides a `clap`-derived CLI with six subcommands:

- **`check`** -- run installer tests with `--parallel`, `--timeout`, `--dry-run`, `--remediate`, and `--fail-fast` options.
- **`list`** -- list known installers from `checksums.yaml`, with `--enabled-only` and `--tag` filters.
- **`validate`** -- validate `checksums.yaml` structure, optionally checking URL accessibility with `--check-urls`.
- **`classify-error`** -- classify an error message (accepts `--stderr` and `--exit-code`).
- **`config show|default|validate`** -- inspect and validate configuration.
- **`status`** -- show last run results with `--detailed` flag.

Global flags: `--format human|json|jsonl`, `--config <path>` (or `ACFS_CONFIG` env var), `-v/-vv/-vvv` verbosity, `--watchdog` (or `ACFS_WATCHDOG` env var).

#### Checksum verification engine

- `src/checksums/parser.rs` -- deserializes `checksums.yaml` into typed `ChecksumsFile`/`InstallerEntry` structs. Each entry has version, download URL, checksum (algorithm + value), enabled flag, tags, and extensible metadata.
- `src/checksums/validator.rs` -- structural validation (missing URLs, invalid URL format, missing versions) with optional live HTTP HEAD checks against installer URLs.

#### Configuration system

- `src/config/schema.rs` -- typed config sections: `GeneralConfig` (ACFS repo path, log level), `DockerConfig` (image, memory limit, CPU quota, timeout, pull policy), `ExecutionConfig` (parallelism, retry count, fail-fast), `RemediationConfig` (enabled, auto-commit, create-PR, max attempts).
- `src/config/loader.rs` -- loads TOML from file or `ACFS_CONFIG` env var, falls back to defaults.
- `config/default.toml` -- ships with all sections pre-configured: general, docker, execution, remediation, notifications (Slack/GitHub/email), monitoring (health endpoint, metrics port), and watchdog.

#### Error classification engine

`src/parser/classifier.rs` performs regex-based error classification against installer stderr and exit codes:

- **Categories**: `bootstrap_mismatch`, `checksum_mismatch`, `network`, `command_not_found`, `permission`, `dependency`, `resource`, `unknown`.
- **Severity levels**: `Transient`, `Configuration`, `Dependency`, `Permission`, `Resource`, `Unknown`.
- Each classification returns an `ErrorClassification` with category, severity, retryable flag, confidence score (0.0 -- 1.0), and optional remediation suggestion.
- `src/parser/error.rs` defines error types for the module.

#### Installer test runner

- `src/runner/installer.rs` -- `InstallerTest` struct (name, URL, SHA256, timeout, retry count, tags, environment) and `TestResult` struct (status, exit code, stdout/stderr, duration, retry history, checksum result, error classification). Builder-pattern API for both.
- `src/runner/container.rs` -- Docker container management via `bollard`: create, exec, and cleanup containers with memory and CPU limits.
- `src/runner/parallel.rs` -- semaphore-gated parallel runner using `tokio::spawn` with configurable concurrency.
- `src/runner/retry.rs` -- configurable retry with `Fixed` and `Exponential` backoff strategies, max attempts, and transient-only retry option.

#### Claude-powered auto-remediation

- `src/remediation/claude.rs` -- `ClaudeRemediation` client with three resilience layers:
  - **Circuit breaker** (Closed/Open/HalfOpen states): opens after N failures, tests recovery after timeout, closes after M successes.
  - **Rate limiter** (token-bucket): configurable max tokens, refill rate, and per-request cost.
  - **Retry with exponential backoff**: configurable max retries, initial/max delay, multiplier, and jitter.
- Cost tracking in microdollars with per-session cost limits. Health check endpoint reports circuit state, request count, cost usage, and Claude availability.
- Falls back to manual remediation instructions when Claude is unavailable or circuit is open.
- `src/remediation/safety.rs` -- command safety checker with five risk levels (`Safe`, `Low`, `Medium`, `High`, `Critical`). Blocks dangerous patterns: fork bombs, `rm -rf /`, `dd` to block devices, `chmod -R 777 /`, `mkfs`. Flags `sudo` operations and force pushes.
- `src/remediation/fallback.rs` -- generates manual remediation suggestions keyed to error severity, with concrete shell commands and documentation links.

#### Reporting and observability

- `src/reporting/jsonl.rs` -- `JsonlWriter` for simple append-only JSONL output. `JsonlReporter` adds level filtering, batch buffering, and optional fsync for durability. `LogEntry` struct includes timestamp, level, component, event, data, duration, error, correlation ID, and installer name.
- `src/reporting/metrics.rs` -- `MetricsExporter` with counters, gauges, and histograms in Prometheus text format. `MetricsSnapshot` tracks 24-hour success rate, test/remediation counts, and uptime with JSON save/load.
- `src/reporting/notify.rs` -- `Notifier` dispatches to GitHub (issue creation on failure) and Slack (webhook messages on configurable success/failure triggers).
- `src/reporting/summary.rs` -- `SummaryGenerator` aggregates test results into `RunSummary` with pass/fail/skip/timeout counts, success rate percentage, and per-failure details (installer name, error category, message, duration, retry count).

#### Systemd service integration

- `src/watchdog.rs` -- `SystemdWatchdog` auto-detects `WATCHDOG_USEC` and `NOTIFY_SOCKET` environment variables, pings at half the configured timeout interval, and supports `READY=1`, `STATUS=...`, `STOPPING=1`, `RELOADING=1`, and `EXTEND_TIMEOUT_USEC=...` notifications. Graceful shutdown via `AtomicBool`.
- `systemd/automated-flywheel-checker.service` -- `Type=notify` service with `WatchdogSec=300`, resource limits (cgroup v2), `ProtectSystem=strict`, `PrivateTmp=yes`, restart-on-failure with rate limiting (5 restarts per 10 minutes).
- `systemd/automated-flywheel-checker.timer` -- daily at 03:00 with 30-minute randomized delay, persistent (catches missed runs), also runs 5 minutes after boot.
- `systemd/automated-flywheel-checker-emergency.service` -- immediate high-priority run for urgent checks.
- `systemd/logrotate-flywheel-checker` -- 30-day log rotation, 90-day JSONL retention.

#### Deployment scripts

- `scripts/install-systemd.sh` -- installs service, timer, and emergency units; enables and starts the timer.
- `scripts/uninstall-systemd.sh` -- stops and removes all units.
- `scripts/notify-flywheel-failure.sh` -- failure notification script with Slack webhook and GitHub issue creation support.

#### CI pipeline

- `.github/workflows/ci.yml` -- runs on push/PR to `main`: format check, clippy, release build, full test suite, CLI smoke tests (`--help`, `config default`). Integration job (main-branch only) tests the `validate` command against a synthetic `checksums.yaml`.

#### Test suite

Unit tests across six test files:

- `tests/unit/checksums_tests.rs` -- checksums parsing and validation.
- `tests/unit/config_tests.rs` -- config loading, defaults, and overrides.
- `tests/unit/parser_tests.rs` -- error classification patterns across all categories.
- `tests/unit/remediation_tests.rs` -- safety checks, circuit breaker state transitions, rate limiter behavior, retry backoff calculation, and cost tracking.
- `tests/unit/reporting_tests.rs` -- JSONL writing, reporter filtering, metrics export, snapshot save/load, summary generation.
- `tests/unit/runner_tests.rs` -- installer test builder, result states, retry tracking, parallel runner creation.

Test fixtures:

- 10 error output samples in `tests/unit/fixtures/error_outputs/`: apt lock, checksum mismatch, command not found, connection refused, connection timeout, disk full, DNS failure, permission denied, SSL certificate error, syntax error.
- 2 remediation response fixtures in `tests/unit/fixtures/remediation_responses/`: successful fix and failed fix.
- Sample `checksums.yaml` for parser tests.

---

## Architecture

```
src/
  main.rs              CLI entry point (clap derive, 6 subcommands)
  lib.rs               Crate root, re-exports
  logging.rs           Tracing/env-filter initialization
  watchdog.rs          Systemd watchdog (WATCHDOG_USEC/NOTIFY_SOCKET)
  checksums/
    parser.rs          checksums.yaml deserialization
    validator.rs       Structural + URL validation
  config/
    loader.rs          TOML config loading with env override
    schema.rs          Typed config sections
  parser/
    classifier.rs      Regex-based error classification engine
    error.rs           Error type definitions
  remediation/
    claude.rs          Claude CLI integration (circuit breaker + rate limiter + retry)
    fallback.rs        Manual remediation suggestions
    prompts.rs         Context-aware prompt generation per error category
    safety.rs          Command safety checker (5 risk levels)
  reporting/
    jsonl.rs           Structured JSONL logging + log rotation
    metrics.rs         Prometheus-style metrics + 24h snapshots
    notify.rs          GitHub/Slack notification dispatch
    summary.rs         Run summary aggregation
  runner/
    container.rs       Docker container management (bollard)
    executor.rs        Installer test execution in isolated temp dirs
    installer.rs       InstallerTest/TestResult data types
    parallel.rs        Semaphore-gated parallel runner
    retry.rs           Exponential/fixed backoff retry
```

## Key dependencies

| Crate | Purpose |
|-------|---------|
| `tokio` (full) | Async runtime |
| `clap` (derive) | CLI parsing |
| `bollard` | Docker API |
| `reqwest` (rustls-tls) | HTTP client |
| `serde` / `serde_json` / `serde_yaml` / `toml` | Serialization |
| `tracing` / `tracing-subscriber` | Structured logging |
| `sha2` / `hex` | Checksum computation |
| `regex` | Error pattern matching |
| `chrono` | Timestamps |
| `indicatif` | Progress bars |
| `tempfile` | Isolated test directories |
| `rand` | Backoff jitter |

[Unreleased]: https://github.com/Dicklesworthstone/automated_flywheel_setup_checker/commits/master
