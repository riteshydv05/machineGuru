#!/usr/bin/env bash
# ============================================================
# MachineGuru — Start Services  (Linux / Jetson Orin)
# ============================================================
# Prerequisites (must be done once before running this):
#   1. cd backend && pip3 install --no-cache-dir -r requirements.txt
#   2. cd frontend && npm run build
#   3. cp .env.example .env  (and edit as needed)
#
# The React UI is served by FastAPI — no separate frontend
# process is started.
#
# Usage:
#   ./start.sh              # start Qdrant + Backend
#   ./start.sh --no-qdrant  # skip Qdrant (use if already running)
#   ./start.sh --reload     # uvicorn --reload for development
#   ./start.sh --stop       # stop all running services
# ============================================================
set -uo pipefail

# ── Project root ─────────────────────────────────────────────
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colours ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
err()  { echo -e "  ${RED}✗${NC}  $*"; }
step() { echo -e "\n${BOLD}${BLUE}▶  $*${NC}"; }
die()  { err "$*"; exit 1; }

# ── Argument parsing ─────────────────────────────────────────
NO_QDRANT=false
RELOAD=false
STOP=false

for arg in "$@"; do
    case "$arg" in
        --no-qdrant) NO_QDRANT=true  ;;
        --reload)    RELOAD=true     ;;
        --stop)      STOP=true       ;;
        --help|-h)
            echo "Usage: $0 [--no-qdrant] [--reload] [--stop]"
            echo "  --no-qdrant  Skip Qdrant (use if already running)"
            echo "  --reload     Enable uvicorn hot-reload (dev mode)"
            echo "  --stop       Gracefully stop all running services"
            exit 0 ;;
    esac
done

# ── Directories ───────────────────────────────────────────────
PID_DIR="$DIR/storage/pids"
LOG_DIR="$DIR/logs"
mkdir -p "$PID_DIR" "$LOG_DIR"

# ── Safe .env reader (no shell source — JSON arrays stay intact) ──
_env() {
    local key="$1" default="${2:-}"
    local val
    val=$(grep -E "^${key}=" "$DIR/.env" 2>/dev/null | head -1 \
          | cut -d= -f2- | tr -d '"' | tr -d "'")
    echo "${val:-$default}"
}

BACKEND_PORT="$(_env BACKEND_PORT 8001)"
QDRANT_HOST="$(_env QDRANT_HOST localhost)"
QDRANT_PORT="$(_env QDRANT_PORT 6333)"
QDRANT_STORAGE="$(_env QDRANT_STORAGE_PATH ./storage/qdrant)"
OLLAMA_URL="$(_env OLLAMA_BASE_URL http://172.17.0.1:11434)"
LLM_MODEL="$(_env LLM_MODEL llama3.2:1b)"

# Resolve relative to project root
[[ "$QDRANT_STORAGE" != /* ]] && QDRANT_STORAGE="$DIR/$QDRANT_STORAGE"

# ── Kill a process by PID file, then by port (Linux only) ────
_stop_pid() {
    local name="$1" pid_file="$PID_DIR/$2.pid"
    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null && ok "Stopped $name (pid $pid)" || true
            local i=0
            while kill -0 "$pid" 2>/dev/null && (( i < 8 )); do sleep 1; (( i++ )); done
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null && \
                warn "$name needed SIGKILL" || true
        fi
        rm -f "$pid_file"
    fi
}

_clear_port() {
    local port="$1"
    if command -v fuser &>/dev/null; then
        fuser -k "${port}/tcp" 2>/dev/null && ok "Cleared port $port" || true
    elif command -v ss &>/dev/null; then
        # ss doesn't kill; best-effort with /proc
        local pid
        pid=$(ss -tlnp "sport = :$port" 2>/dev/null \
              | grep -oP 'pid=\K[0-9]+' | head -1 || echo "")
        [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null && ok "Cleared port $port" || true
    fi
}

# ── --stop mode ───────────────────────────────────────────────
if [[ "$STOP" == true ]]; then
    echo -e "\n${BOLD}🛑  Stopping MachineGuru${NC}"
    echo "════════════════════════════"
    _stop_pid "Backend" backend
    _clear_port "$BACKEND_PORT"
    _stop_pid "Qdrant"  qdrant
    _clear_port "$QDRANT_PORT"
    echo -e "\n  ${GREEN}Done.${NC}\n"
    exit 0
fi

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}🤖  MachineGuru — Starting${NC}"
echo "══════════════════════════════════════"
printf "  Backend  →  http://localhost:%s\n"   "$BACKEND_PORT"
printf "  Qdrant   →  http://%s:%s\n"          "$QDRANT_HOST" "$QDRANT_PORT"
printf "  Ollama   →  %s\n"                    "$OLLAMA_URL"
echo "══════════════════════════════════════"

# ────────────────────────────────────────────────────────────
# STEP 1 — Python interpreter
# ────────────────────────────────────────────────────────────
step "1/4  Python"

PYTHON=""

if [[ -f "$DIR/backend/.venv/bin/activate" ]]; then
    # shellcheck source=/dev/null
    source "$DIR/backend/.venv/bin/activate"
    PYTHON="$DIR/backend/.venv/bin/python"
    ok "venv activated: backend/.venv"

elif [[ -x "$DIR/backend/.venv/bin/python" ]]; then
    PYTHON="$DIR/backend/.venv/bin/python"
    ok "Using venv python directly"

elif python3 -c "import fastapi" 2>/dev/null; then
    PYTHON="$(command -v python3)"
    warn "No venv found — using system python3: $PYTHON"
    warn "Run pip install first if imports fail"

else
    die "No Python with FastAPI found.
       Fix:  cd backend
             pip3 install --no-cache-dir -r requirements.txt"
fi

"$PYTHON" -c "import uvicorn" 2>/dev/null \
    || die "uvicorn missing. Run: pip3 install --no-cache-dir -r backend/requirements.txt"

ok "uvicorn available"

# ────────────────────────────────────────────────────────────
# STEP 2 — Qdrant
# ────────────────────────────────────────────────────────────
step "2/4  Qdrant"

QDRANT_BIN="$DIR/qdrant_bin/qdrant"

# Always clean up any stale PID / port first
_stop_pid "stale Qdrant" qdrant 2>/dev/null || true
_clear_port "$QDRANT_PORT" 2>/dev/null || true
sleep 1

if [[ "$NO_QDRANT" == true ]]; then
    curl -sf "http://$QDRANT_HOST:$QDRANT_PORT/healthz" &>/dev/null \
        && ok "Qdrant already running on port $QDRANT_PORT" \
        || die "Qdrant not reachable — start it first or remove --no-qdrant"

elif [[ -x "$QDRANT_BIN" ]]; then
    mkdir -p "$QDRANT_STORAGE"
    QDRANT__STORAGE__STORAGE_PATH="$QDRANT_STORAGE" \
    QDRANT__LOG_LEVEL="INFO" \
        "$QDRANT_BIN" > "$LOG_DIR/qdrant.log" 2>&1 &
    echo $! > "$PID_DIR/qdrant.pid"
    ok "Qdrant started (pid $(cat "$PID_DIR/qdrant.pid"))"

    echo -n "    Waiting for Qdrant"
    for i in $(seq 1 20); do
        curl -sf "http://$QDRANT_HOST:$QDRANT_PORT/healthz" &>/dev/null && { echo " ✓"; break; }
        (( i == 20 )) && {
            echo " ✗"
            err "Qdrant timed out. Last log:"
            tail -15 "$LOG_DIR/qdrant.log" 2>/dev/null | sed 's/^/    /'
            die "Qdrant startup failed"
        }
        sleep 1; echo -n "."
    done

elif curl -sf "http://$QDRANT_HOST:$QDRANT_PORT/healthz" &>/dev/null; then
    ok "Qdrant already running (external)"

else
    warn "Qdrant binary not found at qdrant_bin/qdrant and not running externally"
    warn "Document search will fail. See SETUP.md § 5 to download Qdrant."
fi

# ────────────────────────────────────────────────────────────
# STEP 3 — Ollama
# ────────────────────────────────────────────────────────────
step "3/4  Ollama"

if curl -sf --max-time 5 "$OLLAMA_URL" &>/dev/null; then
    ok "Ollama reachable"
    TAGS=$(curl -s --max-time 5 "$OLLAMA_URL/api/tags" 2>/dev/null || echo "{}")
    if echo "$TAGS" | "$PYTHON" -c \
        "import sys,json
d=json.load(sys.stdin)
names=[m['name'] for m in d.get('models',[])]
exit(0 if any('$LLM_MODEL' in n for n in names) else 1)" 2>/dev/null; then
        ok "Model '$LLM_MODEL' loaded"
    else
        warn "Model '$LLM_MODEL' not found — LLM calls will fail"
        warn "Jetson: model should be pre-loaded. macOS: ollama pull $LLM_MODEL"
    fi
else
    warn "Ollama not reachable at $OLLAMA_URL"
    warn "Jetson: check OLLAMA_BASE_URL in .env matches bridge IP"
    warn "Continuing — backend will fail gracefully on LLM requests"
fi

# ────────────────────────────────────────────────────────────
# STEP 4 — Backend
# ────────────────────────────────────────────────────────────
step "4/4  Backend"

# Kill stale backend on same port
_stop_pid "stale Backend" backend 2>/dev/null || true
_clear_port "$BACKEND_PORT" 2>/dev/null || true
sleep 1

cd "$DIR/backend"

if [[ "$RELOAD" == true ]]; then
    "$PYTHON" -m uvicorn main:app \
        --host 0.0.0.0 \
        --port "$BACKEND_PORT" \
        --reload \
        > "$LOG_DIR/backend.log" 2>&1 &
    warn "uvicorn hot-reload enabled (dev mode)"
else
    "$PYTHON" -m uvicorn main:app \
        --host 0.0.0.0 \
        --port "$BACKEND_PORT" \
        --workers 1 \
        --loop uvloop \
        --limit-concurrency 16 \
        --timeout-graceful-shutdown 30 \
        > "$LOG_DIR/backend.log" 2>&1 &
fi

BACKEND_PID=$!
echo "$BACKEND_PID" > "$PID_DIR/backend.pid"
cd "$DIR"

echo -n "    Waiting for backend"
for i in $(seq 1 30); do
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
           "http://localhost:$BACKEND_PORT/api/v1/health" 2>/dev/null || echo "000")
    [[ "$HTTP" == "200" ]] && { echo " ✓"; break; }
    (( i == 30 )) && {
        echo " ✗  (last HTTP: $HTTP)"
        err "Backend did not start. Last 30 lines of backend.log:"
        tail -30 "$LOG_DIR/backend.log" 2>/dev/null | sed 's/^/    /'
        die "Backend startup failed"
    }
    sleep 1; echo -n "."
done

ok "Backend running (pid $BACKEND_PID)"

# ── Summary ───────────────────────────────────────────────────
VECTORS=$( curl -sf "http://localhost:$BACKEND_PORT/api/v1/health" 2>/dev/null \
    | "$PYTHON" -c \
      "import sys,json; d=json.load(sys.stdin); print(d.get('qdrant',{}).get('point_count','?'))" \
      2>/dev/null || echo "?" )

echo ""
echo "══════════════════════════════════════════════════"
echo -e "${GREEN}${BOLD}  ✅  All services running!${NC}"
echo ""
printf "  %-18s  %s\n"  "UI + API"       "http://localhost:$BACKEND_PORT"
printf "  %-18s  %s\n"  "API health"     "http://localhost:$BACKEND_PORT/api/v1/health"
printf "  %-18s  %s\n"  "Qdrant"         "http://$QDRANT_HOST:$QDRANT_PORT/dashboard"
printf "  %-18s  %s\n"  "Docs (debug)"   "http://localhost:$BACKEND_PORT/docs"
echo ""
printf "  Vectors in Qdrant : %s\n"  "$VECTORS"
printf "  Logs              : %s\n"  "$LOG_DIR"
echo ""
echo "  Stop:   ./start.sh --stop"
echo "  Logs:   tail -f $LOG_DIR/backend.log"
echo "══════════════════════════════════════════════════"
