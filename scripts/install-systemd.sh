#!/bin/bash
# Install Flywheel Checker systemd units
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "================================================================"
echo "  Installing Flywheel Checker systemd units"
echo "================================================================"

# Create directories
echo "[1/7] Creating directories..."
sudo mkdir -p /var/log/flywheel-checker
sudo mkdir -p /var/run/flywheel-checker
sudo mkdir -p /etc/flywheel-checker
sudo chown ubuntu:ubuntu /var/log/flywheel-checker /var/run/flywheel-checker

# Install config (don't overwrite if exists)
echo "[2/7] Installing configuration..."
if [[ ! -f /etc/flywheel-checker/config.toml ]]; then
    sudo cp "$PROJECT_ROOT/config/default.toml" /etc/flywheel-checker/config.toml
    echo "    Installed default config to /etc/flywheel-checker/config.toml"
else
    echo "    Config already exists, skipping"
fi

# Install logrotate
echo "[3/7] Installing logrotate config..."
sudo cp "$PROJECT_ROOT/systemd/logrotate-flywheel-checker" /etc/logrotate.d/flywheel-checker

# Install notification script
echo "[4/7] Installing notification script..."
sudo cp "$PROJECT_ROOT/scripts/notify-flywheel-failure.sh" /usr/local/bin/notify-flywheel-failure
sudo chmod +x /usr/local/bin/notify-flywheel-failure

# Install systemd units
echo "[5/7] Installing systemd units..."
sudo cp "$PROJECT_ROOT/systemd/automated-flywheel-checker.service" /etc/systemd/system/
sudo cp "$PROJECT_ROOT/systemd/automated-flywheel-checker.timer" /etc/systemd/system/
sudo cp "$PROJECT_ROOT/systemd/automated-flywheel-checker-emergency.service" /etc/systemd/system/

# Reload and enable
echo "[6/7] Enabling timer..."
sudo systemctl daemon-reload
sudo systemctl enable automated-flywheel-checker.timer
sudo systemctl start automated-flywheel-checker.timer

# Verify security
echo "[7/7] Verifying installation..."

echo ""
echo "================================================================"
echo "  Installation complete!"
echo "================================================================"
echo ""
echo "Timer status:"
systemctl status automated-flywheel-checker.timer --no-pager || true
echo ""
echo "Commands:"
echo "  Manual run:     sudo systemctl start automated-flywheel-checker.service"
echo "  Emergency run:  sudo systemctl start automated-flywheel-checker-emergency.service"
echo "  View logs:      journalctl -u automated-flywheel-checker.service -f"
echo "  Edit config:    sudo nano /etc/flywheel-checker/config.toml"
echo ""
echo "Verify security hardening:"
echo "  systemd-analyze security automated-flywheel-checker.service"
