#!/usr/bin/env bash
set -euo pipefail

# MachineGuru Health Check Script
# Usage: ./scripts/healthcheck.sh [service]
#   service: all (default) | backend | frontend | qdrant | ollama

BASE_URL="${HEALTHCHECK_URL:-http://localhost}"
TIMEOUT="${HEALTHCHECK_TIMEOUT:-5}"
SERVICES=("backend" "frontend" "qdrant" "ollama")

check_service() {
    local name="$1"
    local url="$2"
    local expected="$3"

    echo -n "Checking $name... "
    if response=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "$url" 2>/dev/null); then
        if [ "$response" = "$expected" ]; then
            echo "OK (HTTP $response)"
            return 0
        else
            echo "FAIL (HTTP $response, expected $expected)"
            return 1
        fi
    else
        echo "FAIL (unreachable)"
        return 1
    fi
}

check_all() {
    local failed=0
    echo "MachineGuru Health Check"
    echo "========================"

    check_service "Backend API"  "$BASE_URL/api/v1/health" "200" || ((failed++))
    check_service "Frontend"     "$BASE_URL/" "200" || ((failed++))
    check_service "Qdrant"       "$BASE_URL:6333/healthz" "200" || ((failed++))
    check_service "Ollama"       "$BASE_URL:11434" "200" || ((failed++))

    echo ""
    if [ "$failed" -eq 0 ]; then
        echo "All services healthy"
    else
        echo "$failed service(s) unhealthy"
    fi
    exit "$failed"
}

check_single() {
    case "$1" in
        backend)  check_service "Backend API"  "$BASE_URL/api/v1/health" "200" ;;
        frontend) check_service "Frontend"     "$BASE_URL/" "200" ;;
        qdrant)   check_service "Qdrant"       "$BASE_URL:6333/healthz" "200" ;;
        ollama)   check_service "Ollama"       "$BASE_URL:11434" "200" ;;
        *)        echo "Unknown service: $1 (use: all, backend, frontend, qdrant, ollama)" >&2; exit 1 ;;
    esac
}

SERVICE="${1:-all}"

if [ "$SERVICE" = "all" ]; then
    check_all
else
    check_single "$SERVICE"
fi
