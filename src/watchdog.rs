//! Systemd watchdog notification integration
//!
//! Provides integration with systemd's watchdog mechanism for service health monitoring.
//! The service must periodically ping the watchdog to indicate it's still running.

use crate::config::WatchdogConfig;
use std::env;
use std::io;
use std::os::unix::net::UnixDatagram;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::time::interval;
use tracing::{debug, info, warn};

/// Systemd watchdog notification handler
pub struct SystemdWatchdog {
    enabled: bool,
    interval: Duration,
    log_pings: bool,
    socket_path: Option<String>,
    shutdown: Arc<AtomicBool>,
}

impl SystemdWatchdog {
    /// Create a new watchdog handler, auto-detecting systemd environment
    pub fn new() -> Self {
        // Check if we're running under systemd with watchdog
        let watchdog_usec = env::var("WATCHDOG_USEC").ok().and_then(|s| s.parse::<u64>().ok());

        let notify_socket = env::var("NOTIFY_SOCKET").ok();

        let enabled = watchdog_usec.is_some() && notify_socket.is_some();
        // Ping at half the timeout interval for safety margin
        let interval = watchdog_usec
            .map(|usec| Duration::from_micros(usec / 2))
            .unwrap_or(Duration::from_secs(120));

        if enabled {
            info!("Systemd watchdog enabled, will ping every {:?}", interval);
        } else {
            debug!("Systemd watchdog not configured (WATCHDOG_USEC or NOTIFY_SOCKET not set)");
        }

        Self {
            enabled,
            interval,
            log_pings: false,
            socket_path: notify_socket,
            shutdown: Arc::new(AtomicBool::new(false)),
        }
    }

    /// Apply config-driven defaults without overriding systemd-provided settings.
    pub fn with_config(mut self, config: &WatchdogConfig) -> Self {
        if !self.enabled {
            self.interval = Duration::from_secs(config.default_interval_seconds);
        }
        self.log_pings = config.log_pings;
        self
    }

    /// Check if watchdog is enabled
    pub fn is_enabled(&self) -> bool {
        self.enabled
    }

    /// Start the watchdog ping task
    /// Returns a JoinHandle that can be used to wait for the task
    pub fn start(self: Arc<Self>) -> Option<tokio::task::JoinHandle<()>> {
        if !self.enabled {
            return None;
        }

        let watchdog = self.clone();
        Some(tokio::spawn(async move {
            let mut ticker = interval(watchdog.interval);

            loop {
                ticker.tick().await;

                if watchdog.shutdown.load(Ordering::SeqCst) {
                    debug!("Watchdog task shutting down");
                    break;
                }

                watchdog.ping();
            }
        }))
    }

    /// Signal the watchdog task to stop
    pub fn stop(&self) {
        self.shutdown.store(true, Ordering::SeqCst);
    }

    /// Send WATCHDOG=1 to systemd
    fn ping(&self) {
        if let Some(ref socket_path) = self.socket_path {
            if let Err(e) = send_notify(socket_path, "WATCHDOG=1") {
                warn!("Failed to ping watchdog: {}", e);
            } else if self.log_pings {
                info!("Watchdog ping sent");
            } else {
                debug!("Watchdog ping sent");
            }
        }
    }

    /// Notify systemd that the service is ready to accept requests
    pub fn notify_ready(&self) {
        if let Some(ref socket_path) = self.socket_path {
            if let Err(e) = send_notify(socket_path, "READY=1") {
                warn!("Failed to send READY notification: {}", e);
            } else {
                info!("Notified systemd: READY");
            }
        }
    }

    /// Update the service status in systemd
    pub fn notify_status(&self, status: &str) {
        if let Some(ref socket_path) = self.socket_path {
            let msg = format!("STATUS={}", status);
            if let Err(e) = send_notify(socket_path, &msg) {
                warn!("Failed to send STATUS notification: {}", e);
            } else {
                debug!("Notified systemd status: {}", status);
            }
        }
    }

    /// Notify systemd that the service is stopping
    pub fn notify_stopping(&self) {
        if let Some(ref socket_path) = self.socket_path {
            if let Err(e) = send_notify(socket_path, "STOPPING=1") {
                warn!("Failed to send STOPPING notification: {}", e);
            } else {
                info!("Notified systemd: STOPPING");
            }
        }
    }

    /// Notify systemd of a reload in progress
    pub fn notify_reloading(&self) {
        if let Some(ref socket_path) = self.socket_path {
            if let Err(e) = send_notify(socket_path, "RELOADING=1") {
                warn!("Failed to send RELOADING notification: {}", e);
            } else {
                info!("Notified systemd: RELOADING");
            }
        }
    }

    /// Extend the startup timeout
    pub fn notify_extend_timeout(&self, microseconds: u64) {
        if let Some(ref socket_path) = self.socket_path {
            let msg = format!("EXTEND_TIMEOUT_USEC={}", microseconds);
            if let Err(e) = send_notify(socket_path, &msg) {
                warn!("Failed to send EXTEND_TIMEOUT notification: {}", e);
            } else {
                debug!("Extended timeout by {}us", microseconds);
            }
        }
    }
}

impl Default for SystemdWatchdog {
    fn default() -> Self {
        Self::new()
    }
}

/// Send a notification message to the systemd socket
fn send_notify(socket_path: &str, message: &str) -> io::Result<()> {
    let socket = UnixDatagram::unbound()?;
    socket.send_to(message.as_bytes(), socket_path)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    // Mutex to serialize tests that modify environment variables
    static ENV_MUTEX: Mutex<()> = Mutex::new(());

    #[test]
    fn test_watchdog_disabled_without_env() {
        let _guard = ENV_MUTEX.lock().unwrap();

        // Clear env vars
        env::remove_var("WATCHDOG_USEC");
        env::remove_var("NOTIFY_SOCKET");

        let watchdog = SystemdWatchdog::new();
        assert!(!watchdog.enabled);
        assert!(!watchdog.is_enabled());
    }

    #[test]
    fn test_watchdog_interval_calculation() {
        let _guard = ENV_MUTEX.lock().unwrap();

        env::set_var("WATCHDOG_USEC", "600000000"); // 600 seconds
        env::set_var("NOTIFY_SOCKET", "/run/test.sock");

        let watchdog = SystemdWatchdog::new();
        assert!(watchdog.enabled);
        // Should ping at half the interval
        assert_eq!(watchdog.interval, Duration::from_secs(300));

        // Cleanup
        env::remove_var("WATCHDOG_USEC");
        env::remove_var("NOTIFY_SOCKET");
    }

    #[test]
    fn test_watchdog_default_interval() {
        let _guard = ENV_MUTEX.lock().unwrap();

        env::remove_var("WATCHDOG_USEC");
        env::remove_var("NOTIFY_SOCKET");

        let watchdog = SystemdWatchdog::new();
        // Default interval when not configured
        assert_eq!(watchdog.interval, Duration::from_secs(120));
    }

    #[test]
    fn test_watchdog_with_config_override() {
        let _guard = ENV_MUTEX.lock().unwrap();

        env::remove_var("WATCHDOG_USEC");
        env::remove_var("NOTIFY_SOCKET");

        let config = WatchdogConfig { default_interval_seconds: 60, log_pings: true };
        let watchdog = SystemdWatchdog::new().with_config(&config);

        assert_eq!(watchdog.interval, Duration::from_secs(60));
        assert!(watchdog.log_pings);
    }

    #[test]
    fn test_watchdog_env_takes_priority() {
        let _guard = ENV_MUTEX.lock().unwrap();

        env::set_var("WATCHDOG_USEC", "120000000");
        env::set_var("NOTIFY_SOCKET", "/run/test.sock");

        let config = WatchdogConfig { default_interval_seconds: 15, log_pings: false };
        let watchdog = SystemdWatchdog::new().with_config(&config);

        assert_eq!(watchdog.interval, Duration::from_secs(60));

        env::remove_var("WATCHDOG_USEC");
        env::remove_var("NOTIFY_SOCKET");
    }
}
