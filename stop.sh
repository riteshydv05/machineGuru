#!/usr/bin/env bash
# ============================================================
# MachineGuru — Stop All Services
# ============================================================
# Usage: ./stop.sh [--force]
#
# Graceful shutdown sequence:
#   1. Send SIGTERM to each service
#   2. Wait up to 10 seconds for clean exit
#   3. Send SIGKILL if still running (only with --force)
#   4. Clear PID files
#   5. Print status
# ============================================================
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

FORCE=false
for arg in "$@"; do
    [ "$arg" = "--force" ] && FORCE=true
done

PID_DIR="$DIR/storage/temporary"

echo ""
echo -e "${BOLD}🛑  MachineGuru — Stopping Services${NC}"
echo "════════════════════════════════════════"

stop_service() {
    local name="$1"
    local pid_file="$PID_DIR/$2.pid"
    local fallback_pattern="${3:-}"

    # Try PID file first
    if [ -f "$pid_file" ]; then
        PID=$(cat "$pid_file" 2>/dev/null || echo "")
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            echo -n "  Stopping $name (pid $PID)..."
            kill -TERM "$PID" 2>/dev/null || true

            # Wait up to 10 seconds for graceful exit
            for i in $(seq 1 10); do
                if ! kill -0 "$PID" 2>/dev/null; then
                    echo -e " ${GREEN}done${NC}"
                    rm -f "$pid_file"
                    return 0
                fi
                sleep 1
            done

            # Force kill if requested
            if [ "$FORCE" = true ]; then
                kill -KILL "$PID" 2>/dev/null || true
                echo -e " ${YELLOW}force-killed${NC}"
            else
                echo -e " ${YELLOW}still running — use --force to kill${NC}"
            fi
        else
            echo -e "  ${YELLOW}⚠${NC} $name PID file stale (pid $PID)"
        fi
        rm -f "$pid_file"
    else
        # Fallback: pattern-based kill
        if [ -n "$fallback_pattern" ]; then
            if pkill -TERM -f "$fallback_pattern" 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} $name stopped (pattern match)"
            else
                echo -e "  ${NC}ℹ${NC} $name was not running"
            fi
        else
            echo -e "  ${NC}ℹ${NC} $name: no PID file found"
        fi
    fi
}

# Stop frontend first (no dependent services)
stop_service "Frontend" "frontend" "vite.*port\|serve.*dist\|http.server"

# Stop backend
stop_service "Backend"  "backend"  "uvicorn main:app"

# Stop Qdrant last (backend might flush to it during shutdown)
stop_service "Qdrant"   "qdrant"   "qdrant_bin/qdrant"

# Clean up any remaining port listeners as a last resort
if [ "$FORCE" = true ]; then
    BACKEND_PORT="${BACKEND_PORT:-8001}"
    if command -v fuser &>/dev/null; then
        fuser -k "${BACKEND_PORT}/tcp" 2>/dev/null || true
    fi
fi

echo ""
echo -e "${GREEN}${BOLD}  ✅  Services stopped.${NC}"
echo "════════════════════════════════════════"
echo ""
echo "  To restart:  ./start.sh"
echo ""
