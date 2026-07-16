#!/usr/bin/env bash
# ============================================================
# MachineGuru — Restart All Services
# ============================================================
# Usage: ./restart.sh [options]
#
# All arguments are forwarded to start.sh.
#
# Options:
#   --dev          Start frontend in dev mode
#   --no-frontend  Skip frontend
#   --no-qdrant    Skip local Qdrant startup
#   --force        Force-kill stale processes during stop
#
# Sequence:
#   1. Stop all services (gracefully)
#   2. Wait for clean shutdown
#   3. Start all services
# ============================================================
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Source shared library ────────────────────────────────────
if [ -f "$DIR/deploy/deploy_lib.sh" ]; then
    # shellcheck source=deploy/deploy_lib.sh
    source "$DIR/deploy/deploy_lib.sh"
else
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
fi

echo ""
echo -e "${BOLD}🔄  MachineGuru — Restarting Services${NC}"
echo "════════════════════════════════════════"

# Separate stop-specific and start-specific args
STOP_ARGS=()
START_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --force)       STOP_ARGS+=("$arg"); START_ARGS+=("$arg") ;;
        --stop-ollama) STOP_ARGS+=("$arg") ;;
        *)             START_ARGS+=("$arg") ;;
    esac
done

# Step 1: Stop
echo ""
echo -e "${BOLD}Phase 1: Stopping services...${NC}"
"$DIR/stop.sh" ${STOP_ARGS[@]:+"${STOP_ARGS[@]}"} 2>/dev/null || true

# Step 2: Wait for clean shutdown
echo ""
echo -e "${BOLD}Phase 2: Waiting for clean shutdown...${NC}"
sleep 2

# Verify ports are free
for port in 8001 6333; do
    for attempt in 1 2 3; do
        if [ "$(uname -s)" = "Darwin" ]; then
            if ! lsof -i :"$port" &>/dev/null 2>&1; then
                break
            fi
        else
            if ! ss -tln 2>/dev/null | grep -q ":${port} " 2>/dev/null; then
                break
            fi
        fi
        sleep 1
    done
done

echo -e "  ${GREEN}✓${NC} Shutdown complete"

# Step 3: Start
echo ""
echo -e "${BOLD}Phase 3: Starting services...${NC}"
"$DIR/start.sh" ${START_ARGS[@]:+"${START_ARGS[@]}"}
