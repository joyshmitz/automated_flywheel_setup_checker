# Automated Flywheel Setup Checker

Automated testing and verification system for ACFS (Agentic Coding Flywheel Setup) installer scripts.

## Features

- **Installer Verification**: Test individual installers in isolated Docker containers
- **Error Classification**: Automatic categorization of failures (network, permission, dependency, etc.)
- **Parallel Execution**: Run multiple installer tests concurrently
- **Retry Logic**: Configurable retry with exponential backoff for transient failures
- **Structured Logging**: JSONL output for CI/CD integration
- **Auto-Remediation**: Optional Claude-powered fix suggestions (experimental)

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/Dicklesworthstone/automated_flywheel_setup_checker.git
cd automated_flywheel_setup_checker

# Build
cargo build --release

# Install (optional)
cargo install --path .
```

### Requirements

- Rust 1.75+ (2021 edition)
- Docker (for running installer tests)

## Usage

### List Available Installers

```bash
# List all installers from checksums.yaml
automated_flywheel_setup_checker list

# List only enabled installers
automated_flywheel_setup_checker list --enabled-only

# Filter by tag
automated_flywheel_setup_checker list --tag essential
```

### Validate checksums.yaml

```bash
# Validate format
automated_flywheel_setup_checker validate

# Validate and check URLs
automated_flywheel_setup_checker validate --check-urls
```

### Run Installer Checks

```bash
# Dry run - show what would be tested
automated_flywheel_setup_checker check --dry-run

# Run all enabled installers
automated_flywheel_setup_checker check

# Run specific installers
automated_flywheel_setup_checker check rust nodejs

# Run with 4 parallel workers
automated_flywheel_setup_checker check --parallel 4

# Stop on first failure
automated_flywheel_setup_checker check --fail-fast
```

### Classify Errors

```bash
# Classify an error message
automated_flywheel_setup_checker classify-error \
  --stderr "curl: (7) Failed to connect: Connection refused" \
  --exit-code 7
```

### Configuration

```bash
# Show current configuration
automated_flywheel_setup_checker config show

# Show default configuration
automated_flywheel_setup_checker config default

# Validate a config file
automated_flywheel_setup_checker --config my-config.toml config validate
```

## Configuration File

Create a `config.toml` file:

```toml
[general]
acfs_repo = "/path/to/agentic_coding_flywheel_setup"
log_level = "info"

[docker]
image = "ubuntu:22.04"
memory_limit = "2G"
cpu_quota = 1.0
timeout_seconds = 300
pull_policy = "if-not-present"

[execution]
parallel = 4
retry_transient = 3
fail_fast = false

[remediation]
enabled = false
auto_commit = false
create_pr = true
max_attempts = 3
```

Set the config path via environment variable or CLI flag:

```bash
export ACFS_CONFIG=/path/to/config.toml
# or
automated_flywheel_setup_checker --config /path/to/config.toml check
```

## Output Formats

All commands support `--format` flag:

- `human` (default): Human-readable output
- `json`: Pretty-printed JSON
- `jsonl`: JSON Lines (one object per line)

```bash
automated_flywheel_setup_checker list --format json
automated_flywheel_setup_checker check --format jsonl
```

## Development

```bash
# Run tests
cargo test

# Run with verbose logging
RUST_LOG=debug cargo run -- check --dry-run

# Format code
cargo fmt

# Run lints
cargo clippy
```

## License

MIT
