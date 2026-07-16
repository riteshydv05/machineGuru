#!/usr/bin/env bash
# ============================================================
# MachineGuru — Start All Services
# ============================================================
# Usage: ./start.sh [--dev] [--no-frontend] [--no-qdrant]
#
# Options:
#   --dev          Start frontend in dev mode (npm run dev)
#   --no-frontend  Skip frontend startup
#   --no-qdrant    Skip local Qdrant startup (use if already running)
#
# Service startup order:
#   1. Validate environment
#   2. Create storage directories
#   3. Auto-start Ollama if installed but stopped
#   4. Start Qdrant
#   5. Wait for Qdrant to be ready
#   6. Start Backend (FastAPI/Uvicorn)
#   7. Wait for Backend to be ready
#   8. Verify Ollama is reachable
#   9. Start Frontend (optional)
#  10. Print summary
# ============================================================
set -uo pipefail

# ── Project root (always absolute, never relies on cwd) ──────
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Source shared library ────────────────────────────────────
DEPLOY_LIB_DIR="$DIR/deploy"
if [ -f "$DIR/deploy/deploy_lib.sh" ]; then
    # shellcheck source=deploy/deploy_lib.sh
    source "$DIR/deploy/deploy_lib.sh"
else
    # Minimal fallback if deploy_lib.sh is missing
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
    ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
    warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
    err()  { echo -e "  ${RED}✗${NC} $1"; }
    step() { echo -e "\n${BOLD}${BLUE}[$1]${NC} $2"; }
fi

# ── Argument parsing ─────────────────────────────────────────
# Default mode: 'dev' — uses Vite dev server which activates the
# /api proxy to localhost:8001. This is correct for macOS and
# native Jetson deployments without nginx.
#
# Use --prod-serve only if nginx is installed and configured to
# proxy /api/ → localhost:8001 (Jetson production with nginx).
MODE="dev"
START_FRONTEND=true
START_QDRANT=true
for arg in "$@"; do
    case $arg in
        --dev)          MODE="dev" ;;
        --prod-serve)   MODE="prod" ;;
        --no-frontend)  START_FRONTEND=false ;;
        --no-qdrant)    START_QDRANT=false ;;
    esac
done

# ── Load .env (safe extraction — no shell source) ─────────────
# We deliberately do NOT use 'set -a; source .env' because that
# exports ALL variables into the shell environment, which corrupts
# JSON array values like CORS_ORIGINS=["url1","url2"] by stripping
# the double-quotes. The backend (pydantic-settings) reads the
# .env file directly and handles JSON arrays correctly.
#
# Instead, we extract only the simple scalar values we need for
# shell logic using grep + sed.
_env_get() {
    local key="$1" default="$2"
    local val
    val=$(grep -E "^${key}=" "$DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
    echo "${val:-$default}"
}

if [ ! -f "$DIR/.env" ]; then
    warn ".env not found — using defaults"
    warn "Run: cp .env.example .env  then edit it for your system"
fi

# ── Read configuration (with safe defaults) ──────────────────
BACKEND_PORT="$(_env_get BACKEND_PORT 8001)"
FRONTEND_PORT="$(_env_get FRONTEND_PORT 5173)"
QDRANT_HOST="$(_env_get QDRANT_HOST localhost)"
QDRANT_PORT="$(_env_get QDRANT_PORT 6333)"
QDRANT_LOG_LEVEL="$(_env_get QDRANT_LOG_LEVEL INFO)"
QDRANT_STORAGE_PATH="$(_env_get QDRANT_STORAGE_PATH ./storage/qdrant)"
OLLAMA_BASE_URL="$(_env_get OLLAMA_BASE_URL http://localhost:11434)"
LLM_MODEL="$(_env_get LLM_MODEL llama3.2:1b)"
LOG_DIR="$(_env_get LOG_DIR ./logs)"
UPLOAD_DIR="$(_env_get UPLOAD_DIR ./storage/uploads)"

# Resolve relative paths to absolute
[[ "$QDRANT_STORAGE_PATH" != /* ]] && QDRANT_STORAGE_PATH="$DIR/$QDRANT_STORAGE_PATH"
[[ "$LOG_DIR"             != /* ]] && LOG_DIR="$DIR/$LOG_DIR"
[[ "$UPLOAD_DIR"          != /* ]] && UPLOAD_DIR="$DIR/$UPLOAD_DIR"

# PID file directory
PID_DIR="$DIR/storage/temporary"

echo ""
echo -e "${BOLD}🤖  MachineGuru — Starting Services${NC}"
echo "════════════════════════════════════════"
echo "  Mode:        $MODE"
echo "  Backend:     http://localhost:$BACKEND_PORT"
echo "  Frontend:    http://localhost:$FRONTEND_PORT"
echo "  Qdrant:      http://$QDRANT_HOST:$QDRANT_PORT"
echo "  Ollama:      $OLLAMA_BASE_URL"
echo "  Logs:        $LOG_DIR"
echo "════════════════════════════════════════"

# ────────────────────────────────────────────────────────────
# STEP 1: Validate environment
# ────────────────────────────────────────────────────────────
step "1/8" "Validating environment"

ERRORS=0

# Check Python — either venv or system
if [ -f "$DIR/backend/.venv/bin/activate" ]; then
    ok "Python venv found at backend/.venv/"
elif command -v python3 &>/dev/null && python3 -c "import fastapi" 2>/dev/null; then
    ok "Python with dependencies found (user/system packages)"
else
    err "Python environment not found"
    err "Run: ./deploy/install.sh"
    ERRORS=$((ERRORS + 1))
fi

# Check qdrant binary
QDRANT_BIN="$DIR/qdrant_bin/qdrant"
if [ "$START_QDRANT" = true ] && [ ! -f "$QDRANT_BIN" ]; then
    warn "Qdrant binary not found at qdrant_bin/qdrant"
    warn "Will check if Qdrant is already running on port $QDRANT_PORT"
    START_QDRANT=false
fi

if [ "$ERRORS" -gt 0 ]; then
    err "Environment validation failed. Fix errors above and retry."
    exit 1
fi

ok "Environment validated"

# ────────────────────────────────────────────────────────────
# STEP 2: Create required directories
# ────────────────────────────────────────────────────────────
step "2/8" "Creating directories"

mkdir -p "$LOG_DIR"
mkdir -p "$UPLOAD_DIR"
mkdir -p "$QDRANT_STORAGE_PATH"
mkdir -p "$PID_DIR"
mkdir -p "$DIR/storage/cache"
mkdir -p "$DIR/storage/embeddings"

ok "Directories ready"

# ────────────────────────────────────────────────────────────
# STEP 3: Kill stale processes
# ────────────────────────────────────────────────────────────
step "3/8" "Cleaning up old processes"

# Stop old backend using PID file first, then fallback to port
BACKEND_PID_FILE="$PID_DIR/backend.pid"
if [ -f "$BACKEND_PID_FILE" ]; then
    OLD_PID=$(cat "$BACKEND_PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null && ok "Stopped old backend (pid $OLD_PID)" || true
        sleep 1
    fi
    rm -f "$BACKEND_PID_FILE"
fi

# Fallback: kill by port (works even if PID file is stale)
# macOS has BSD fuser which does not support -k PORT/tcp — use lsof on Darwin
if [[ "$(uname -s)" == "Darwin" ]]; then
    # macOS: use lsof
    if command -v lsof &>/dev/null; then
        PIDS=$(lsof -t -i :"$BACKEND_PORT" 2>/dev/null || true)
        [ -n "$PIDS" ] && kill -9 $PIDS 2>/dev/null && ok "Cleared port $BACKEND_PORT" || true
    fi
elif command -v fuser &>/dev/null; then
    # Linux: fuser supports -k PORT/tcp
    fuser -k "${BACKEND_PORT}/tcp" 2>/dev/null && ok "Cleared port $BACKEND_PORT" || true
elif command -v lsof &>/dev/null; then
    PIDS=$(lsof -t -i :"$BACKEND_PORT" 2>/dev/null || true)
    [ -n "$PIDS" ] && kill -9 $PIDS 2>/dev/null && ok "Cleared port $BACKEND_PORT" || true
fi

# Stop old Qdrant
QDRANT_PID_FILE="$PID_DIR/qdrant.pid"
if [ -f "$QDRANT_PID_FILE" ]; then
    OLD_PID=$(cat "$QDRANT_PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null && ok "Stopped old Qdrant (pid $OLD_PID)" || true
        sleep 1
    fi
    rm -f "$QDRANT_PID_FILE"
fi

sleep 1

# ────────────────────────────────────────────────────────────
# STEP 4: Auto-start Ollama if installed but not running
# ────────────────────────────────────────────────────────────
step "4/8" "Checking Ollama"

# Use deploy_lib if available, otherwise basic check
if type detect_ollama &>/dev/null; then
    OLLAMA_STATUS="$(detect_ollama)"
    case "$OLLAMA_STATUS" in
        INSTALLED_RUNNING)
            DETECTED_OLLAMA_URL="$(detect_ollama_url 2>/dev/null || echo "$OLLAMA_BASE_URL")"
            ok "Ollama running at $DETECTED_OLLAMA_URL"
            # Update OLLAMA_BASE_URL if auto-detected URL differs
            if [ "$DETECTED_OLLAMA_URL" != "$OLLAMA_BASE_URL" ]; then
                OLLAMA_BASE_URL="$DETECTED_OLLAMA_URL"
                warn "Using auto-detected Ollama URL: $OLLAMA_BASE_URL"
            fi
            ;;
        INSTALLED_STOPPED)
            warn "Ollama installed but not running — attempting to start..."
            if try_start_ollama; then
                DETECTED_OLLAMA_URL="$(detect_ollama_url 2>/dev/null || echo "$OLLAMA_BASE_URL")"
                ok "Ollama started at $DETECTED_OLLAMA_URL"
                OLLAMA_BASE_URL="$DETECTED_OLLAMA_URL"
            else
                warn "Could not start Ollama automatically"
                warn "Start manually: ollama serve"
                warn "Continuing — backend will retry Ollama on each request"
            fi
            ;;
        MISSING)
            warn "Ollama not installed"
            warn "Install: curl -fsSL https://ollama.com/install.sh | sh"
            warn "Continuing — backend will fail gracefully on LLM requests"
            ;;
    esac
else
    # Fallback if deploy_lib is not available
    if curl -sf --max-time 5 "$OLLAMA_BASE_URL" > /dev/null 2>&1; then
        ok "Ollama reachable at $OLLAMA_BASE_URL"
    else
        warn "Ollama not reachable at $OLLAMA_BASE_URL"
        warn "Start Ollama: ollama serve"
        warn "Continuing — backend will retry Ollama on each request"
    fi
fi

# Verify model availability
if curl -sf --max-time 5 "$OLLAMA_BASE_URL" > /dev/null 2>&1; then
    LLM_MODEL_NAME="${LLM_MODEL:-llama3.2:1b}"
    TAGS=$(curl -s --max-time 5 "$OLLAMA_BASE_URL/api/tags" 2>/dev/null || echo "{}")
    if echo "$TAGS" | python3 -c "import sys,json; d=json.load(sys.stdin); names=[m['name'] for m in d.get('models',[])]; exit(0 if any('${LLM_MODEL_NAME}' in n for n in names) else 1)" 2>/dev/null; then
        ok "Model '$LLM_MODEL_NAME' is loaded"
    else
        warn "Model '$LLM_MODEL_NAME' not found in Ollama"
        warn "Run in another terminal: ollama pull $LLM_MODEL_NAME"
    fi
fi

# ────────────────────────────────────────────────────────────
# STEP 5: Start Qdrant
# ────────────────────────────────────────────────────────────
step "5/8" "Starting Qdrant (port $QDRANT_PORT)"

if [ "$START_QDRANT" = true ]; then
    QDRANT__STORAGE__STORAGE_PATH="$QDRANT_STORAGE_PATH" \
    QDRANT__LOG_LEVEL="${QDRANT_LOG_LEVEL:-INFO}" \
        "$QDRANT_BIN" \
        > "$LOG_DIR/qdrant.log" 2>&1 &
    QDRANT_PID=$!
    echo "$QDRANT_PID" > "$QDRANT_PID_FILE"

    # Wait up to 20 seconds
    for i in $(seq 1 20); do
        if curl -sf "http://$QDRANT_HOST:$QDRANT_PORT/healthz" > /dev/null 2>&1; then
            ok "Qdrant ready (pid $QDRANT_PID)"
            break
        fi
        if [ "$i" -eq 20 ]; then
            err "Qdrant failed to start after 20s"
            err "Check: $LOG_DIR/qdrant.log"
            tail -20 "$LOG_DIR/qdrant.log" 2>/dev/null | sed 's/^/    /'
            exit 1
        fi
        sleep 1
    done
else
    # Check if already running
    if curl -sf "http://$QDRANT_HOST:$QDRANT_PORT/healthz" > /dev/null 2>&1; then
        ok "Qdrant already running on port $QDRANT_PORT"
    else
        err "Qdrant is not running and --no-qdrant was specified"
        err "Start Qdrant externally or remove --no-qdrant"
        exit 1
    fi
fi

# ────────────────────────────────────────────────────────────
# STEP 6: Start Backend
# ────────────────────────────────────────────────────────────
step "6/8" "Starting backend (port $BACKEND_PORT)"

cd "$DIR/backend"

# Activate venv if it exists, otherwise rely on user/system packages
if [ -f .venv/bin/activate ]; then
    source .venv/bin/activate
fi

# Set LOG_DIR and UPLOAD_DIR as absolute paths for the backend process
export LOG_DIR="$LOG_DIR"
export UPLOAD_DIR="$UPLOAD_DIR"

if [ "$MODE" = "dev" ]; then
    uvicorn main:app \
        --host 0.0.0.0 \
        --port "$BACKEND_PORT" \
        --reload \
        > "$LOG_DIR/backend.log" 2>&1 &
else
    uvicorn main:app \
        --host 0.0.0.0 \
        --port "$BACKEND_PORT" \
        --workers 1 \
        --loop uvloop \
        --limit-concurrency 16 \
        --timeout-graceful-shutdown 30 \
        > "$LOG_DIR/backend.log" 2>&1 &
fi

BACKEND_PID=$!
echo "$BACKEND_PID" > "$BACKEND_PID_FILE"

cd "$DIR"

# Wait up to 30 seconds for backend to respond with HTTP 200.
# A 503 means an old shutting-down instance is still on the port — keep waiting.
for i in $(seq 1 30); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:$BACKEND_PORT/api/v1/health" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        ok "Backend ready (pid $BACKEND_PID)"
        break
    fi
    if [ "$i" -eq 30 ]; then
        fail "Backend failed to start after 30s (last HTTP status: $HTTP_CODE)"
        fail "Check: $LOG_DIR/backend.log"
        # Use cat + head to avoid macOS sed crash with ANSI color codes in logs
        echo "  Last 30 lines of backend.log:"
        cat "$LOG_DIR/backend.log" 2>/dev/null | tail -30 | while IFS= read -r line; do echo "    $line"; done
        exit 1
    fi
    sleep 1
done

# ────────────────────────────────────────────────────────────
# STEP 7: Start Frontend
# ────────────────────────────────────────────────────────────
step "7/8" "Starting frontend"

FRONTEND_PID_FILE="$PID_DIR/frontend.pid"

if [ "$START_FRONTEND" = true ]; then
    cd "$DIR/frontend"

    if [ "$MODE" = "dev" ]; then
        # ── Vite dev server (DEFAULT) ─────────────────────────
        # Vite's dev server activates the /api proxy defined in
        # vite.config.ts, forwarding all /api/* requests to the
        # FastAPI backend at localhost:$BACKEND_PORT.
        # This is the correct mode for macOS and native Jetson
        # without a separately configured nginx reverse proxy.
        npm run dev -- --port "$FRONTEND_PORT" > "$LOG_DIR/frontend.log" 2>&1 &
        ok "Starting Vite dev server (with /api proxy → localhost:$BACKEND_PORT)"
    else
        # ── Production static serve (--prod-serve only) ───────
        # Use this ONLY when nginx is configured to proxy /api/
        # to the backend (e.g., Jetson with nginx installed).
        # Without nginx, API calls from the built app will fail
        # because the static file server has no proxy capability.
        if [ -d "$DIR/frontend/dist" ]; then
            warn "Using static file server — ensure nginx proxies /api/ to port $BACKEND_PORT"
            if command -v nginx &>/dev/null; then
                # nginx is available — start it with the project config
                nginx -c "$DIR/frontend/nginx.conf" -g "daemon off;" > "$LOG_DIR/frontend.log" 2>&1 &
            elif command -v npx &>/dev/null; then
                warn "nginx not found — using npx serve (API calls will NOT work without a proxy!)"
                npx --yes serve dist -l "$FRONTEND_PORT" > "$LOG_DIR/frontend.log" 2>&1 &
            else
                warn "Neither nginx nor npx found — falling back to Vite dev server"
                npm run dev -- --port "$FRONTEND_PORT" > "$LOG_DIR/frontend.log" 2>&1 &
            fi
        else
            warn "Frontend dist not built — running Vite dev server instead"
            warn "Build first with: cd frontend && npm run build"
            npm run dev -- --port "$FRONTEND_PORT" > "$LOG_DIR/frontend.log" 2>&1 &
        fi
    fi

    FRONTEND_PID=$!
    echo "$FRONTEND_PID" > "$FRONTEND_PID_FILE"
    cd "$DIR"

    # Wait up to 20 seconds (Vite needs a moment to compile)
    for i in $(seq 1 20); do
        if curl -sf --max-time 2 "http://localhost:$FRONTEND_PORT" > /dev/null 2>&1; then
            ok "Frontend ready (pid $FRONTEND_PID) → http://localhost:$FRONTEND_PORT"
            break
        fi
        if [ "$i" -eq 20 ]; then
            warn "Frontend not yet ready after 20s — check $LOG_DIR/frontend.log"
        fi
        sleep 1
    done
else
    warn "Frontend startup skipped (--no-frontend)"
fi

# ────────────────────────────────────────────────────────────
# STEP 8: Health summary
# ────────────────────────────────────────────────────────────
step "8/8" "Verifying services"

HEALTH=$(curl -sf "http://localhost:$BACKEND_PORT/api/v1/health" 2>/dev/null || echo "{}")
VECTORS=$(echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('qdrant',{}).get('point_count','?'))" 2>/dev/null || echo "?")

# Verify frontend is reachable
if [ "$START_FRONTEND" = true ]; then
    if curl -sf "http://localhost:$FRONTEND_PORT" > /dev/null 2>&1; then
        ok "Frontend verified reachable"
    else
        warn "Frontend not reachable — check $LOG_DIR/frontend.log"
    fi
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo -e "${GREEN}${BOLD}  ✅  All services running!${NC}"
echo ""
printf "  %-15s  %-40s  %s\n" "Service" "URL" "PID"
echo "  ──────────────────────────────────────────────────────"
printf "  %-15s  %-40s  %s\n" "Qdrant" "http://$QDRANT_HOST:$QDRANT_PORT/dashboard" "${QDRANT_PID:-running}"
printf "  %-15s  %-40s  %s\n" "Backend" "http://localhost:$BACKEND_PORT/api/v1/health" "$BACKEND_PID"
[ "$START_FRONTEND" = true ] && printf "  %-15s  %-40s  %s\n" "Frontend" "http://localhost:$FRONTEND_PORT" "${FRONTEND_PID:-running}"
echo ""
echo "  📦  Vectors in Qdrant: $VECTORS"
echo "  📋  Logs directory:    $LOG_DIR"
echo ""
echo "  To stop everything:   ./stop.sh"
echo "  Health check:         ./deploy/healthcheck.sh"
echo "  Verify installation:  ./deploy/verify_installation.sh"
echo "════════════════════════════════════════════════════════"
