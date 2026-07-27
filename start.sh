#!/usr/bin/env bash
# ============================================================
# MachineGuru — Start Services  (Linux / Jetson Orin)
# ============================================================
# Self-contained startup: installs deps, builds frontend,
# starts Qdrant, verifies Ollama, starts the FastAPI backend
# (which serves the built React UI), then opens an ngrok tunnel.
#
# Usage:
#   ./start.sh              # full start (all 6 steps)
#   ./start.sh --no-qdrant  # skip Qdrant (use if already running)
#   ./start.sh --reload     # uvicorn --reload (hot-reload / dev)
#   ./start.sh --no-ngrok   # skip ngrok tunnel
#   ./start.sh --stop       # gracefully stop all services
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
NO_NGROK=false

for arg in "$@"; do
    case "$arg" in
        --no-qdrant) NO_QDRANT=true  ;;
        --reload)    RELOAD=true     ;;
        --stop)      STOP=true       ;;
        --no-ngrok)  NO_NGROK=true   ;;
        --help|-h)
            echo "Usage: $0 [--no-qdrant] [--reload] [--no-ngrok] [--stop]"
            echo "  --no-qdrant  Skip Qdrant (use if already running)"
            echo "  --reload     Enable uvicorn hot-reload (dev mode)"
            echo "  --no-ngrok   Skip the ngrok tunnel"
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

# Resolve relative paths to absolute
[[ "$QDRANT_STORAGE" != /* ]] && QDRANT_STORAGE="$DIR/$QDRANT_STORAGE"

# ── Export all variables from .env to the environment ────────
if [[ -f "$DIR/.env" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line//$'\r'/}"
        # Trim leading whitespace
        line="${line##[[:space:]]}"
        # Trim trailing whitespace
        line="${line%%[[:space:]]}"
        
        if [[ -n "$line" ]] && [[ ! "$line" =~ ^# ]] && [[ "$line" =~ = ]]; then
            key=$(echo "$line" | cut -d= -f1)
            val=$(echo "$line" | cut -d= -f2-)
            # Remove wrapping double quotes
            val="${val%\"}"
            val="${val#\"}"
            # Remove wrapping single quotes
            val="${val%\'}"
            val="${val#\'}"
            export "$key"="$val"
        fi
    done < "$DIR/.env"
fi

# ── Kill a process by PID file ────────────────────────────────
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

# ── Clear a TCP port (Linux) ─────────────────────────────────
_clear_port() {
    local port="$1"
    if command -v fuser &>/dev/null; then
        fuser -k "${port}/tcp" 2>/dev/null || true
    elif command -v ss &>/dev/null; then
        local pid
        pid=$(ss -tlnp "sport = :$port" 2>/dev/null \
              | grep -oP 'pid=\K[0-9]+' | head -1 || echo "")
        [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null || true
    fi
}

# ── --stop mode ───────────────────────────────────────────────
if [[ "$STOP" == true ]]; then
    echo -e "\n${BOLD}🛑  Stopping MachineGuru${NC}"
    echo "════════════════════════════"
    _stop_pid "ngrok"   ngrok
    _stop_pid "Backend" backend;  _clear_port "$BACKEND_PORT"
    _stop_pid "Qdrant"  qdrant;   _clear_port "$QDRANT_PORT"
    echo -e "\n  ${GREEN}Done.${NC}\n"
    exit 0
fi

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}🤖  MachineGuru — Starting (6 steps)${NC}"
echo "══════════════════════════════════════"
printf "  Backend  →  http://localhost:%s\n"   "$BACKEND_PORT"
printf "  Qdrant   →  http://%s:%s\n"          "$QDRANT_HOST" "$QDRANT_PORT"
printf "  Ollama   →  %s\n"                    "$OLLAMA_URL"
echo "══════════════════════════════════════"

# ────────────────────────────────────────────────────────────
# STEP 1 — Python interpreter
# ────────────────────────────────────────────────────────────
step "1/6  Python"

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

else
    die "No Python with FastAPI found.
       Fix:  cd backend && pip3 install --no-cache-dir -r requirements.txt"
fi

# Auto-install requirements if uvicorn is missing
if ! "$PYTHON" -c "import uvicorn" 2>/dev/null; then
    warn "uvicorn not found — installing requirements now..."
    VENV_PIP="$(dirname "$PYTHON")/pip"
    [[ -x "$VENV_PIP" ]] || VENV_PIP="$PYTHON -m pip"
    mkdir -p ~/tmp
    echo "    Running: pip install --no-cache-dir -r requirements.txt"
    if TMPDIR=~/tmp $VENV_PIP install --no-cache-dir \
            -r "$DIR/backend/requirements.txt" 2>&1 \
            | tee -a "$LOG_DIR/pip_install.log" \
            | grep -E "^(Collecting|Installing|Successfully|ERROR|error)" \
            | sed 's/^/    /'; then
        ok "requirements installed"
    else
        err "pip install failed. Full log: $LOG_DIR/pip_install.log"
        die "Fix the errors above then re-run ./start.sh"
    fi
    "$PYTHON" -c "import uvicorn" 2>/dev/null \
        || die "uvicorn still missing — check $LOG_DIR/pip_install.log"
fi

ok "uvicorn available"

# ────────────────────────────────────────────────────────────
# STEP 2 — Frontend build
# ────────────────────────────────────────────────────────────
step "2/6  Frontend build"

FRONTEND_DIR="$DIR/frontend"
DIST_INDEX="$FRONTEND_DIR/dist/index.html"

if [[ ! -d "$FRONTEND_DIR" ]]; then
    warn "frontend/ directory not found — skipping build"

elif ! command -v npm &>/dev/null; then
    warn "npm not found — skipping build"
    warn "Install Node.js 20: sudo apt install -y nodejs npm"
    [[ -f "$DIST_INDEX" ]] && ok "Using existing dist/ from a previous build" \
                            || warn "No dist/ found — UI will not load"

else
    # Install node_modules if missing or package.json is newer
    if [[ ! -d "$FRONTEND_DIR/node_modules" ]]; then
        echo "    npm install..."
        npm --prefix "$FRONTEND_DIR" install --prefer-offline \
            > "$LOG_DIR/npm_install.log" 2>&1 \
            && ok "node_modules installed" \
            || { err "npm install failed. Log: $LOG_DIR/npm_install.log"; }
    else
        ok "node_modules present"
    fi

    # Build if dist/ is missing or src/ is newer than dist/
    NEEDS_BUILD=false
    if [[ ! -f "$DIST_INDEX" ]]; then
        NEEDS_BUILD=true
        warn "dist/index.html missing — building..."
    elif [[ "$FRONTEND_DIR/src" -nt "$DIST_INDEX" ]] || \
         [[ "$FRONTEND_DIR/package.json" -nt "$DIST_INDEX" ]]; then
        NEEDS_BUILD=true
        warn "Source changed since last build — rebuilding..."
    else
        ok "dist/ is up-to-date (skip rebuild)"
    fi

    if [[ "$NEEDS_BUILD" == true ]]; then
        echo "    npm run build..."
        npm --prefix "$FRONTEND_DIR" run build \
            > "$LOG_DIR/npm_build.log" 2>&1 \
            && ok "Frontend built → frontend/dist/" \
            || {
                err "npm run build failed. Last 20 lines:"
                tail -20 "$LOG_DIR/npm_build.log" 2>/dev/null | sed 's/^/    /'
                warn "Continuing — backend will serve stale dist/ if it exists"
            }
    fi
fi

# ────────────────────────────────────────────────────────────
# STEP 3 — Qdrant
# ────────────────────────────────────────────────────────────
step "3/6  Qdrant"

QDRANT_BIN="$DIR/qdrant_bin/qdrant"

_stop_pid "stale Qdrant" qdrant 2>/dev/null || true
_clear_port "$QDRANT_PORT" 2>/dev/null || true
sleep 1

if [[ "$NO_QDRANT" == true ]]; then
    curl -sf "http://$QDRANT_HOST:$QDRANT_PORT/healthz" &>/dev/null \
        && ok "Qdrant already running on port $QDRANT_PORT" \
        || die "Qdrant not reachable — start it first or remove --no-qdrant"

elif [[ ! -x "$QDRANT_BIN" ]]; then
    # Binary missing — auto-download
    warn "Qdrant binary not found — downloading..."
    if command -v curl &>/dev/null && command -v tar &>/dev/null; then
        ARCH="$(uname -m)"
        case "$ARCH" in
            aarch64|arm64) QURL="https://github.com/qdrant/qdrant/releases/latest/download/qdrant-aarch64-unknown-linux-musl.tar.gz" ;;
            x86_64)        QURL="https://github.com/qdrant/qdrant/releases/latest/download/qdrant-x86_64-unknown-linux-musl.tar.gz" ;;
            *)             QURL="" ;;
        esac
        if [[ -n "$QURL" ]]; then
            mkdir -p "$DIR/qdrant_bin"
            curl -fL --progress-bar "$QURL" | tar xz -C "$DIR/qdrant_bin/" \
                && chmod +x "$QDRANT_BIN" && ok "Qdrant downloaded" \
                || warn "Download failed — document search disabled"
        else
            warn "Unknown arch '$ARCH' — download Qdrant manually. See SETUP.md § 5"
        fi
    else
        warn "curl/tar not available — download Qdrant manually. See SETUP.md § 5"
    fi
fi

if [[ -x "$QDRANT_BIN" ]]; then
    mkdir -p "$QDRANT_STORAGE"
    QDRANT__STORAGE__STORAGE_PATH="$QDRANT_STORAGE" \
    QDRANT__LOG_LEVEL="INFO" \
        "$QDRANT_BIN" > "$LOG_DIR/qdrant.log" 2>&1 &
    echo $! > "$PID_DIR/qdrant.pid"
    ok "Qdrant started (pid $(cat "$PID_DIR/qdrant.pid"))"

    echo -n "    Waiting for Qdrant"
    for i in $(seq 1 20); do
        curl -sf "http://$QDRANT_HOST:$QDRANT_PORT/healthz" &>/dev/null && { echo " ✓"; break; }
        (( i == 20 )) && { echo " ✗"; warn "Qdrant timed out — search disabled"; }
        sleep 1; echo -n "."
    done

elif curl -sf "http://$QDRANT_HOST:$QDRANT_PORT/healthz" &>/dev/null; then
    ok "Qdrant already running (external)"
else
    warn "Qdrant not available — document search will fail"
fi

# ────────────────────────────────────────────────────────────
# STEP 4 — Ollama
# ────────────────────────────────────────────────────────────
step "4/6  Ollama"

if curl -sf --max-time 5 "$OLLAMA_URL" &>/dev/null; then
    ok "Ollama reachable at $OLLAMA_URL"
    TAGS=$(curl -s --max-time 5 "$OLLAMA_URL/api/tags" 2>/dev/null || echo "{}")
    if echo "$TAGS" | "$PYTHON" -c \
        "import sys,json
d=json.load(sys.stdin)
names=[m['name'] for m in d.get('models',[])]
exit(0 if any('$LLM_MODEL' in n for n in names) else 1)" 2>/dev/null; then
        ok "Model '$LLM_MODEL' loaded"
    else
        warn "Model '$LLM_MODEL' not found — LLM calls will fail"
        warn "Jetson: model should be pre-loaded | macOS: ollama pull $LLM_MODEL"
    fi
else
    warn "Ollama not reachable at $OLLAMA_URL"
    warn "Jetson: check OLLAMA_BASE_URL in .env | macOS: run 'ollama serve'"
    warn "Backend will fail gracefully on LLM requests"
fi

# ────────────────────────────────────────────────────────────
# STEP 5 — Backend (FastAPI — also serves the React UI)
# ────────────────────────────────────────────────────────────
step "5/6  Backend"

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
        err "Backend failed to start. Last 30 lines:"
        tail -30 "$LOG_DIR/backend.log" 2>/dev/null | sed 's/^/    /'
        die "Backend startup failed"
    }
    sleep 1; echo -n "."
done

ok "Backend running (pid $BACKEND_PID)"

# ────────────────────────────────────────────────────────────
# STEP 6 — ngrok tunnel
# ────────────────────────────────────────────────────────────
step "6/6  ngrok tunnel"

NGROK_BIN=""
NGROK_URL=""

if [[ "$NO_NGROK" == true ]]; then
    warn "ngrok skipped (--no-ngrok)"

else
    # Locate ngrok: project root first, then PATH
    if [[ -x "$DIR/ngrok" ]]; then
        NGROK_BIN="$DIR/ngrok"
    elif command -v ngrok &>/dev/null; then
        NGROK_BIN="$(command -v ngrok)"
    fi

    if [[ -z "$NGROK_BIN" ]]; then
        warn "ngrok not found — skipping tunnel"
        warn "Download: https://ngrok.com/download  then place ./ngrok here"
    else
        # Kill any previous ngrok
        _stop_pid "stale ngrok" ngrok 2>/dev/null || true
        # Kill anything sitting on the ngrok API port (4040)
        _clear_port 4040 2>/dev/null || true
        sleep 1

        ok "Starting ngrok → port $BACKEND_PORT"
        "$NGROK_BIN" http "$BACKEND_PORT" \
            --log=stdout \
            > "$LOG_DIR/ngrok.log" 2>&1 &
        NGROK_PID=$!
        echo "$NGROK_PID" > "$PID_DIR/ngrok.pid"

        # Wait up to 10 s for ngrok's local API to come up
        echo -n "    Waiting for ngrok"
        for i in $(seq 1 10); do
            NGROK_URL=$(curl -s --max-time 2 http://127.0.0.1:4040/api/tunnels 2>/dev/null \
                | "$PYTHON" -c \
                  "import sys,json
tunnels=json.load(sys.stdin).get('tunnels',[])
https=[t['public_url'] for t in tunnels if t['public_url'].startswith('https')]
print(https[0] if https else '')" 2>/dev/null || echo "")
            [[ -n "$NGROK_URL" ]] && { echo " ✓"; break; }
            (( i == 10 )) && { echo " ✗"; warn "ngrok did not expose a URL — check $LOG_DIR/ngrok.log"; }
            sleep 1; echo -n "."
        done

        [[ -n "$NGROK_URL" ]] && ok "ngrok public URL: $NGROK_URL"
    fi
fi

# ── Summary ───────────────────────────────────────────────────
VECTORS=$(curl -sf "http://localhost:$BACKEND_PORT/api/v1/health" 2>/dev/null \
    | "$PYTHON" -c \
      "import sys,json; d=json.load(sys.stdin); print(d.get('qdrant',{}).get('point_count','?'))" \
      2>/dev/null || echo "?")

echo ""
echo "══════════════════════════════════════════════════════"
echo -e "${GREEN}${BOLD}  ✅  MachineGuru is running!${NC}"
echo ""
printf "  %-20s  %s\n"  "UI + API (local)"  "http://localhost:$BACKEND_PORT"
[[ -n "$NGROK_URL" ]] && \
printf "  %-20s  %s\n"  "UI + API (public)"  "$NGROK_URL"
printf "  %-20s  %s\n"  "API health"         "http://localhost:$BACKEND_PORT/api/v1/health"
printf "  %-20s  %s\n"  "Qdrant dashboard"   "http://$QDRANT_HOST:$QDRANT_PORT/dashboard"
printf "  %-20s  %s\n"  "Docs (debug)"       "http://localhost:$BACKEND_PORT/docs"
echo ""
printf "  Vectors in Qdrant : %s\n"  "$VECTORS"
printf "  Logs              : %s/\n" "$LOG_DIR"
echo ""
echo "  Stop all:  ./start.sh --stop"
echo "  Backend:   tail -f $LOG_DIR/backend.log"
[[ -n "$NGROK_URL" ]] && \
echo "  ngrok:     tail -f $LOG_DIR/ngrok.log"
echo "══════════════════════════════════════════════════════"
