#!/bin/bash
# Uninstall Flywheel Checker systemd units
set -euo pipefail

echo "================================================================"
echo "  Uninstalling Flywheel Checker"
echo "================================================================"

echo "[1/4] Stopping timer..."
sudo systemctl stop automated-flywheel-checker.timer 2>/dev/null || true
sudo systemctl stop automated-flywheel-checker.service 2>/dev/null || true

echo "[2/4] Disabling timer..."
sudo systemctl disable automated-flywheel-checker.timer 2>/dev/null || true

echo "[3/4] Removing systemd units..."
sudo rm -f /etc/systemd/system/automated-flywheel-checker.service
sudo rm -f /etc/systemd/system/automated-flywheel-checker.timer
sudo rm -f /etc/systemd/system/automated-flywheel-checker-emergency.service
sudo rm -f /etc/logrotate.d/flywheel-checker
sudo rm -f /usr/local/bin/notify-flywheel-failure

echo "[4/4] Reloading systemd..."
sudo systemctl daemon-reload

echo ""
echo "================================================================"
echo "  Uninstalled (logs and config preserved)"
echo "================================================================"
echo ""
echo "To remove completely:"
echo "  sudo rm -rf /var/log/flywheel-checker /etc/flywheel-checker /var/run/flywheel-checker"
