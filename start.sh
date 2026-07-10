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
#   3. Start Qdrant
#   4. Wait for Qdrant to be ready
#   5. Start Backend (FastAPI/Uvicorn)
#   6. Wait for Backend to be ready
#   7. Verify Ollama is reachable
#   8. Start Frontend (optional)
#   9. Print summary
# ============================================================
set -uo pipefail

# ── Project root (always absolute, never relies on cwd) ──────
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Color codes ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ── Argument parsing ─────────────────────────────────────────
MODE="prod"
START_FRONTEND=true
START_QDRANT=true
for arg in "$@"; do
    case $arg in
        --dev)          MODE="dev" ;;
        --no-frontend)  START_FRONTEND=false ;;
        --no-qdrant)    START_QDRANT=false ;;
    esac
done

# ── Helpers ──────────────────────────────────────────────────
ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
err()   { echo -e "  ${RED}✗${NC} $1"; }
step()  { echo -e "\n${BOLD}${BLUE}[$1]${NC} $2"; }

# ── Load .env ────────────────────────────────────────────────
if [ -f "$DIR/.env" ]; then
    set -a
    source "$DIR/.env"
    set +a
else
    warn ".env not found — using defaults"
    warn "Run: cp .env.example .env  then edit it for your system"
fi

# ── Read configuration (with safe defaults) ──────────────────
BACKEND_PORT="${BACKEND_PORT:-8001}"
FRONTEND_PORT="${FRONTEND_PORT:-5173}"
QDRANT_HOST="${QDRANT_HOST:-localhost}"
QDRANT_PORT="${QDRANT_PORT:-6333}"
QDRANT_STORAGE_PATH="${QDRANT_STORAGE_PATH:-./storage/qdrant}"
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://localhost:11434}"
LOG_DIR="${LOG_DIR:-./logs}"
UPLOAD_DIR="${UPLOAD_DIR:-./storage/uploads}"

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
step "1/7" "Validating environment"

ERRORS=0

# Check Python venv
if [ ! -f "$DIR/backend/.venv/bin/activate" ]; then
    err "Python venv not found at backend/.venv/"
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
step "2/7" "Creating directories"

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
step "3/7" "Cleaning up old processes"

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
if command -v fuser &>/dev/null; then
    fuser -k "${BACKEND_PORT}/tcp" 2>/dev/null && ok "Cleared port $BACKEND_PORT" || true
elif command -v lsof &>/dev/null; then
    PIDS=$(lsof -t -i :"$BACKEND_PORT" 2>/dev/null || true)
    [ -n "$PIDS" ] && kill $PIDS 2>/dev/null && ok "Cleared port $BACKEND_PORT" || true
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
# STEP 4: Start Qdrant
# ────────────────────────────────────────────────────────────
step "4/7" "Starting Qdrant (port $QDRANT_PORT)"

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
# STEP 5: Verify Ollama
# ────────────────────────────────────────────────────────────
step "5/7" "Verifying Ollama"

if curl -sf --max-time 5 "$OLLAMA_BASE_URL" > /dev/null 2>&1; then
    ok "Ollama reachable at $OLLAMA_BASE_URL"
    LLM_MODEL_NAME="${LLM_MODEL:-llama3.2:1b}"
    TAGS=$(curl -s --max-time 5 "$OLLAMA_BASE_URL/api/tags" 2>/dev/null || echo "{}")
    if echo "$TAGS" | python3 -c "import sys,json; d=json.load(sys.stdin); names=[m['name'] for m in d.get('models',[])]; exit(0 if any('${LLM_MODEL_NAME}' in n for n in names) else 1)" 2>/dev/null; then
        ok "Model '$LLM_MODEL_NAME' is loaded"
    else
        warn "Model '$LLM_MODEL_NAME' not found in Ollama"
        warn "Run in another terminal: ollama pull $LLM_MODEL_NAME"
    fi
else
    warn "Ollama not reachable at $OLLAMA_BASE_URL"
    warn "Start Ollama: ollama serve"
    warn "Continuing — backend will retry Ollama on each request"
fi

# ────────────────────────────────────────────────────────────
# STEP 6: Start Backend
# ────────────────────────────────────────────────────────────
step "6/7" "Starting backend (port $BACKEND_PORT)"

cd "$DIR/backend"
source .venv/bin/activate

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

# Wait up to 30 seconds for backend to be ready
for i in $(seq 1 30); do
    if curl -sf --max-time 3 "http://localhost:$BACKEND_PORT/api/v1/health" > /dev/null 2>&1; then
        ok "Backend ready (pid $BACKEND_PID)"
        break
    fi
    if [ "$i" -eq 30 ]; then
        err "Backend failed to start after 30s"
        err "Check: $LOG_DIR/backend.log"
        tail -30 "$LOG_DIR/backend.log" 2>/dev/null | sed 's/^/    /'
        exit 1
    fi
    sleep 1
done

# ────────────────────────────────────────────────────────────
# STEP 7: Start Frontend
# ────────────────────────────────────────────────────────────
step "7/7" "Starting frontend"

FRONTEND_PID_FILE="$PID_DIR/frontend.pid"

if [ "$START_FRONTEND" = true ]; then
    cd "$DIR/frontend"

    if [ "$MODE" = "dev" ]; then
        npm run dev -- --port "$FRONTEND_PORT" > "$LOG_DIR/frontend.log" 2>&1 &
    else
        # Production: serve the built dist with a simple static server
        if [ -d "$DIR/frontend/dist" ]; then
            # Use npx serve if available, otherwise fallback to python
            if command -v npx &>/dev/null; then
                npx --yes serve dist -l "$FRONTEND_PORT" > "$LOG_DIR/frontend.log" 2>&1 &
            else
                python3 -m http.server "$FRONTEND_PORT" --directory "$DIR/frontend/dist" > "$LOG_DIR/frontend.log" 2>&1 &
            fi
        else
            warn "Frontend dist not built. Running dev server instead."
            npm run dev -- --port "$FRONTEND_PORT" > "$LOG_DIR/frontend.log" 2>&1 &
        fi
    fi

    FRONTEND_PID=$!
    echo "$FRONTEND_PID" > "$FRONTEND_PID_FILE"
    cd "$DIR"

    # Wait up to 15 seconds
    for i in $(seq 1 15); do
        if curl -sf --max-time 2 "http://localhost:$FRONTEND_PORT" > /dev/null 2>&1; then
            ok "Frontend ready (pid $FRONTEND_PID)"
            break
        fi
        if [ "$i" -eq 15 ]; then
            warn "Frontend not yet ready — check $LOG_DIR/frontend.log"
        fi
        sleep 1
    done
else
    warn "Frontend startup skipped (--no-frontend)"
fi

# ────────────────────────────────────────────────────────────
# Health summary
# ────────────────────────────────────────────────────────────
HEALTH=$(curl -sf "http://localhost:$BACKEND_PORT/api/v1/health" 2>/dev/null || echo "{}")
VECTORS=$(echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('qdrant',{}).get('point_count','?'))" 2>/dev/null || echo "?")

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
