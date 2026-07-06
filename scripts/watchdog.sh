#!/usr/bin/env bash
set -euo pipefail

# MachineGuru Watchdog Script
# Runs health checks periodically and logs status
# Can be configured via cron or systemd timer
#
# Usage: ./scripts/watchdog.sh [--alert] [--interval N]
#   --alert:    Send alert on failure (requires webhook URL)
#   --interval: Check interval in seconds (default: 60)

ALERT="${WATCHDOG_ALERT:-false}"
INTERVAL="${WATCHDOG_INTERVAL:-60}"
WEBHOOK_URL="${WATCHDOG_WEBHOOK_URL:-}"
LOG_FILE="${WATCHDOG_LOG:-logs/watchdog.log}"
COMPOSE_FILE="${WATCHDOG_COMPOSE:-docker-compose.yml}"
COMPOSE_DIR="${WATCHDOG_DIR:-.}"

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "$timestamp [$level] $message" >> "$LOG_FILE"
    echo "[$level] $message"
}

send_alert() {
    local message="$1"
    if [ -n "$WEBHOOK_URL" ]; then
        curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"[MachineGuru Watchdog] $message\"}" \
            --max-time 5 2>/dev/null || log "WARN" "Failed to send alert"
    fi
}

recover_service() {
    local service="$1"
    log "INFO" "Attempting to recover service: $service"
    cd "$COMPOSE_DIR" && docker compose -f "$COMPOSE_FILE" up -d --no-deps "$service" 2>&1 | while IFS= read -r line; do log "INFO" "Recovery: $line"; done
}

check_and_recover() {
    local failed=0
    local failed_services=()

    if ! curl -s -o /dev/null --max-time 5 "http://localhost/api/v1/health"; then
        log "ERROR" "Backend is unhealthy"
        failed=$((failed + 1))
        failed_services+=("backend")
    fi

    if ! curl -s -o /dev/null --max-time 5 "http://localhost/"; then
        log "ERROR" "Frontend is unhealthy"
        failed=$((failed + 1))
        failed_services+=("frontend")
    fi

    if ! curl -s -o /dev/null --max-time 5 "http://localhost:6333/healthz"; then
        log "WARN" "Qdrant is unhealthy"
        failed=$((failed + 1))
        failed_services+=("qdrant")
    fi

    if [ "$failed" -gt 0 ]; then
        log "WARN" "$failed service(s) unhealthy: ${failed_services[*]}"
        send_alert "$failed service(s) unhealthy: ${failed_services[*]}"
        for svc in "${failed_services[@]}"; do
            recover_service "$svc"
        done
        return 1
    fi

    log "INFO" "All services healthy"
    return 0
}

mkdir -p "$(dirname "$LOG_FILE")"

log "INFO" "Watchdog started (interval=${INTERVAL}s, alert=${ALERT})"

while true; do
    check_and_recover
    sleep "$INTERVAL"
done
