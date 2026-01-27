//! Tracing/logging setup for the application

use tracing_subscriber::{fmt, prelude::*, EnvFilter};

/// Initialize the tracing subscriber with the given verbosity level
pub fn init(verbosity: u8) {
    let filter = match verbosity {
        0 => "warn",
        1 => "info",
        2 => "debug",
        _ => "trace",
    };

    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new(filter));

    tracing_subscriber::registry().with(fmt::layer()).with(env_filter).init();
}
