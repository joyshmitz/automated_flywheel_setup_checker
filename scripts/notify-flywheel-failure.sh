#!/bin/bash
# Notification script for flywheel checker failures
set -euo pipefail

SCRIPT_NAME="notify-flywheel-failure"
CONFIG_FILE="${ACFS_CONFIG:-/etc/flywheel-checker/config.toml}"
LOG_DIR="/var/log/flywheel-checker"
STATUS_FILE="/var/run/flywheel-checker/status.json"

# Logging
log() {
    echo "[$(date -Iseconds)] [$SCRIPT_NAME] $*" | tee -a "$LOG_DIR/notifications.log"
}

# Load config
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # Parse TOML for notification settings
        SLACK_WEBHOOK=$(grep -E "^slack_webhook" "$CONFIG_FILE" | cut -d'"' -f2 || echo "")
        GITHUB_ISSUE_REPO=$(grep -E "^github_issue_repo" "$CONFIG_FILE" | cut -d'"' -f2 || echo "")
        NOTIFICATION_ENABLED=$(grep -E "^notification_enabled" "$CONFIG_FILE" | grep -q "true" && echo "true" || echo "false")
    else
        log "WARNING: Config file not found: $CONFIG_FILE"
        NOTIFICATION_ENABLED="false"
    fi
}

# Get failure details from recent logs
get_failure_details() {
    local log_file="$LOG_DIR/checker.log"
    local details=""

    if [[ -f "$log_file" ]]; then
        details=$(tail -100 "$log_file" | grep -E "(ERROR|FAIL|error|failed)" | tail -20 || echo "No specific errors found")
    fi

    echo "$details"
}

# Get summary from JSONL
get_run_summary() {
    local jsonl_file="$LOG_DIR/runs.jsonl"

    if [[ -f "$jsonl_file" ]]; then
        tail -1 "$jsonl_file" 2>/dev/null || echo "{}"
    else
        echo "{}"
    fi
}

# Send Slack notification
send_slack() {
    local message="$1"

    if [[ -z "$SLACK_WEBHOOK" ]]; then
        log "Slack webhook not configured, skipping"
        return 0
    fi

    log "Sending Slack notification..."

    local payload
    payload=$(jq -n \
        --arg host "$(hostname)" \
        --arg time "$(date -Iseconds)" \
        --arg result "${SERVICE_RESULT:-unknown}" \
        --arg msg "${message:0:2000}" \
        '{
            text: ":warning: Flywheel Checker Failed",
            blocks: [
                {type: "header", text: {type: "plain_text", text: ":warning: Flywheel Checker Failed"}},
                {type: "section", text: {type: "mrkdwn", text: ("*Host:* " + $host + "\n*Time:* " + $time + "\n*Service Result:* " + $result)}},
                {type: "section", text: {type: "mrkdwn", text: ("*Recent Errors:*\n```\n" + $msg + "\n```")}},
                {type: "actions", elements: [{type: "button", text: {type: "plain_text", text: "View Logs"}, url: "https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/actions"}]}
            ]
        }')

    curl -s -X POST "$SLACK_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        && log "Slack notification sent" \
        || log "ERROR: Failed to send Slack notification"
}

# Create GitHub issue for failure
create_github_issue() {
    local details="$1"

    if [[ -z "$GITHUB_ISSUE_REPO" ]]; then
        log "GitHub issue repo not configured, skipping"
        return 0
    fi

    if ! command -v gh &>/dev/null; then
        log "gh CLI not available, skipping GitHub issue"
        return 0
    fi

    log "Creating GitHub issue..."

    local title="[Automated] Flywheel Checker Failed - $(date +%Y-%m-%d)"
    local body
    body=$(cat << EOF
## Flywheel Checker Failure Report

**Host:** $(hostname)
**Time:** $(date -Iseconds)
**Service Result:** ${SERVICE_RESULT:-unknown}

### Error Details

\`\`\`
${details:0:4000}
\`\`\`

### Run Summary

\`\`\`json
$(get_run_summary)
\`\`\`

### Logs Location

- Main log: \`/var/log/flywheel-checker/checker.log\`
- JSONL: \`/var/log/flywheel-checker/runs.jsonl\`

---
*This issue was automatically created by the flywheel-checker notification system.*
EOF
    )

    gh issue create \
        --repo "$GITHUB_ISSUE_REPO" \
        --title "$title" \
        --body "$body" \
        --label "automated,bug,checker-failure" \
        && log "GitHub issue created" \
        || log "ERROR: Failed to create GitHub issue"
}

# Update status file
update_status() {
    local status="$1"
    local details="$2"

    mkdir -p "$(dirname "$STATUS_FILE")"

    jq -n \
        --arg status "$status" \
        --arg ts "$(date -Iseconds)" \
        --arg host "$(hostname)" \
        --arg result "${SERVICE_RESULT:-unknown}" \
        --arg preview "${details:0:500}" \
        --arg log "$LOG_DIR/checker.log" \
        '{
            status: $status,
            timestamp: $ts,
            hostname: $host,
            service_result: $result,
            details_preview: $preview,
            log_file: $log,
            notified: true
        }' > "$STATUS_FILE"

    log "Status file updated: $STATUS_FILE"
}

# Main
main() {
    log "================================================================"
    log "  Flywheel Checker Failure Notification"
    log "================================================================"

    load_config

    if [[ "$NOTIFICATION_ENABLED" != "true" ]]; then
        log "Notifications disabled in config"
        exit 0
    fi

    local failure_details
    failure_details=$(get_failure_details)

    log "Service result: ${SERVICE_RESULT:-unknown}"
    log "Getting failure details..."

    # Send notifications
    send_slack "$failure_details"
    create_github_issue "$failure_details"

    # Update status
    update_status "failed" "$failure_details"

    log "Notification process complete"
}

main "$@"
