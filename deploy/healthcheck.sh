#!/usr/bin/env bash
# ============================================================
# MachineGuru — Comprehensive Health Check Script
# ============================================================
# Usage: ./deploy/healthcheck.sh [--verbose] [--json]
#
# Checks:
#   System:   Python version, Node version, disk space, memory, GPU
#   Services: Ollama, Qdrant, Backend, Frontend
#   Config:   Required environment variables, storage directories
#   Network:  Port availability
#
# Exit codes:
#   0  All checks passed
#   1  One or more checks failed
# ============================================================
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

VERBOSE=false
JSON_OUTPUT=false
FAILED=0
WARNED=0
PASSED=0

for arg in "$@"; do
    case $arg in
        --verbose) VERBOSE=true ;;
        --json)    JSON_OUTPUT=true ;;
    esac
done

# Load .env if present
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env" 2>/dev/null || true
    set +a
fi

BACKEND_PORT="${BACKEND_PORT:-8001}"
QDRANT_PORT="${QDRANT_PORT:-6333}"
QDRANT_HOST="${QDRANT_HOST:-localhost}"
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://localhost:11434}"
FRONTEND_PORT="${FRONTEND_PORT:-5173}"
TIMEOUT=5

# ── Output helpers ────────────────────────────────────────────
RESULTS=()

pass() {
    local label="$1" msg="${2:-}"
    PASSED=$((PASSED + 1))
    RESULTS+=("{\"check\":\"$label\",\"status\":\"pass\",\"detail\":\"$msg\"}")
    if [ "$JSON_OUTPUT" = false ]; then
        printf "  ${GREEN}✓${NC} %-45s ${GREEN}OK${NC}" "$label"
        [ -n "$msg" ] && echo " — $msg" || echo ""
    fi
}

fail() {
    local label="$1" msg="${2:-}"
    FAILED=$((FAILED + 1))
    RESULTS+=("{\"check\":\"$label\",\"status\":\"fail\",\"detail\":\"$msg\"}")
    if [ "$JSON_OUTPUT" = false ]; then
        printf "  ${RED}✗${NC} %-45s ${RED}FAIL${NC}" "$label"
        [ -n "$msg" ] && echo " — $msg" || echo ""
    fi
}

warn_check() {
    local label="$1" msg="${2:-}"
    WARNED=$((WARNED + 1))
    RESULTS+=("{\"check\":\"$label\",\"status\":\"warn\",\"detail\":\"$msg\"}")
    if [ "$JSON_OUTPUT" = false ]; then
        printf "  ${YELLOW}⚠${NC} %-45s ${YELLOW}WARN${NC}" "$label"
        [ -n "$msg" ] && echo " — $msg" || echo ""
    fi
}

section() {
    [ "$JSON_OUTPUT" = false ] && echo -e "\n${BOLD}${BLUE}── $1${NC}"
}

# ────────────────────────────────────────────────────────────
section "System Checks"
# ────────────────────────────────────────────────────────────

# Python version
PYTHON_BIN=""
for candidate in python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" &>/dev/null; then
        PY_VER=$("$candidate" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
        PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
        PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
        if [ "$PY_MAJOR" -ge 3 ] && [ "$PY_MINOR" -ge 10 ]; then
            PYTHON_BIN="$candidate"
            break
        fi
    fi
done
[ -n "$PYTHON_BIN" ] && pass "Python 3.10+" "$PY_VER" || fail "Python 3.10+" "not found — install Python 3.10 or newer"

# Node.js
if command -v node &>/dev/null; then
    NODE_VER=$(node -v | sed 's/v//')
    NODE_MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
    [ "$NODE_MAJOR" -ge 20 ] && pass "Node.js 20+" "v$NODE_VER" || warn_check "Node.js 20+" "found v$NODE_VER — v20+ recommended"
else
    warn_check "Node.js" "not found — required for frontend"
fi

# Disk space (>= 5GB free on project root filesystem)
DISK_FREE_GB=$(df -BG "$PROJECT_ROOT" | tail -1 | awk '{print $4}' | sed 's/G//')
if [ "${DISK_FREE_GB:-0}" -ge 5 ]; then
    pass "Disk space" "${DISK_FREE_GB}GB free"
elif [ "${DISK_FREE_GB:-0}" -ge 2 ]; then
    warn_check "Disk space" "${DISK_FREE_GB}GB free — low, recommend 10GB+"
else
    fail "Disk space" "${DISK_FREE_GB}GB free — critical, need at least 5GB"
fi

# Memory (>= 4GB RAM)
MEM_TOTAL_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
MEM_FREE_MB=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
if [ "$MEM_TOTAL_MB" -ge 4096 ]; then
    pass "RAM total" "${MEM_TOTAL_MB}MB (${MEM_FREE_MB}MB free)"
elif [ "$MEM_TOTAL_MB" -ge 2048 ]; then
    warn_check "RAM total" "${MEM_TOTAL_MB}MB — 8GB+ recommended for Jetson"
else
    fail "RAM total" "${MEM_TOTAL_MB}MB — insufficient, need at least 4GB"
fi

# GPU / CUDA
if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "unknown")
    pass "NVIDIA GPU" "$GPU_NAME"
elif [ -f /proc/device-tree/model ]; then
    MODEL=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || echo "Jetson")
    pass "Jetson GPU" "$MODEL (use tegrastats to monitor)"
else
    warn_check "GPU/CUDA" "nvidia-smi not found — GPU acceleration unavailable"
fi

# ────────────────────────────────────────────────────────────
section "Environment Configuration"
# ────────────────────────────────────────────────────────────

# .env file exists
[ -f "$PROJECT_ROOT/.env" ] && pass ".env file" "found" || fail ".env file" "missing — run: cp .env.example .env"

# Required environment variables
REQUIRED_VARS=(OLLAMA_BASE_URL LLM_MODEL QDRANT_HOST QDRANT_PORT UPLOAD_DIR LOG_DIR)
for var in "${REQUIRED_VARS[@]}"; do
    val="${!var:-}"
    [ -n "$val" ] && pass "ENV: $var" "$val" || fail "ENV: $var" "not set in .env"
done

# Virtual environment
VENV_DIR="$PROJECT_ROOT/backend/.venv"
[ -d "$VENV_DIR" ] && pass "Python venv" "$VENV_DIR" || fail "Python venv" "missing — run deploy/install.sh"

# ────────────────────────────────────────────────────────────
section "Storage Directories"
# ────────────────────────────────────────────────────────────

STORAGE_DIRS=(
    "$PROJECT_ROOT/storage/uploads"
    "$PROJECT_ROOT/storage/qdrant"
    "$PROJECT_ROOT/storage/cache"
    "$PROJECT_ROOT/logs"
)
for dir in "${STORAGE_DIRS[@]}"; do
    [ -d "$dir" ] && pass "Directory: $(basename "$dir")" "$dir" || warn_check "Directory: $(basename "$dir")" "missing — will be created on startup"
done

# ────────────────────────────────────────────────────────────
section "Service Health"
# ────────────────────────────────────────────────────────────

http_check() {
    local label="$1" url="$2" expected="${3:-200}"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "$url" 2>/dev/null || echo "000")
    if [ "$code" = "$expected" ]; then
        pass "$label" "HTTP $code at $url"
    else
        fail "$label" "HTTP $code (expected $expected) at $url"
    fi
}

# Ollama
http_check "Ollama API" "$OLLAMA_BASE_URL" "200"

# Qdrant
http_check "Qdrant health" "http://${QDRANT_HOST}:${QDRANT_PORT}/healthz" "200"

# Backend
http_check "Backend /health" "http://localhost:${BACKEND_PORT}/api/v1/health" "200"

# Frontend (dev server or built dist served)
if curl -sf "http://localhost:${FRONTEND_PORT}" &>/dev/null; then
    pass "Frontend" "HTTP 200 at http://localhost:${FRONTEND_PORT}"
else
    warn_check "Frontend" "not reachable at port ${FRONTEND_PORT} — start with: npm run dev"
fi

# Qdrant collection
if curl -sf "http://${QDRANT_HOST}:${QDRANT_PORT}/healthz" &>/dev/null; then
    COLLECTION="${QDRANT_COLLECTION:-machine_guru}"
    if curl -sf "http://${QDRANT_HOST}:${QDRANT_PORT}/collections/${COLLECTION}" &>/dev/null; then
        POINT_COUNT=$(curl -s "http://${QDRANT_HOST}:${QDRANT_PORT}/collections/${COLLECTION}" 2>/dev/null | \
            python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',{}).get('vectors_count',0))" 2>/dev/null || echo "?")
        pass "Qdrant collection" "$COLLECTION ($POINT_COUNT vectors)"
    else
        warn_check "Qdrant collection" "$COLLECTION not found — will be created on first backend start"
    fi
fi

# Ollama model check
if curl -sf "$OLLAMA_BASE_URL" &>/dev/null; then
    LLM_MODEL_NAME="${LLM_MODEL:-llama3.2:1b}"
    MODELS=$(curl -s "$OLLAMA_BASE_URL/api/tags" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); names=[m['name'] for m in d.get('models',[])]; print(' '.join(names))" 2>/dev/null || echo "")
    if echo "$MODELS" | grep -q "$LLM_MODEL_NAME"; then
        pass "Ollama model: $LLM_MODEL_NAME" "loaded"
    else
        warn_check "Ollama model: $LLM_MODEL_NAME" "not found — run: ollama pull $LLM_MODEL_NAME"
    fi
fi

# ────────────────────────────────────────────────────────────
section "Ports"
# ────────────────────────────────────────────────────────────

check_port() {
    local label="$1" port="$2"
    if command -v ss &>/dev/null; then
        if ss -tln 2>/dev/null | grep -q ":${port} "; then
            pass "$label (port $port)" "listening"
        else
            warn_check "$label (port $port)" "not listening"
        fi
    elif command -v netstat &>/dev/null; then
        if netstat -tln 2>/dev/null | grep -q ":${port} "; then
            pass "$label (port $port)" "listening"
        else
            warn_check "$label (port $port)" "not listening"
        fi
    else
        warn_check "$label (port $port)" "cannot check (ss/netstat not available)"
    fi
}

check_port "Backend" "$BACKEND_PORT"
check_port "Qdrant"  "$QDRANT_PORT"
check_port "Ollama"  "11434"

# ────────────────────────────────────────────────────────────
# Results
# ────────────────────────────────────────────────────────────

if [ "$JSON_OUTPUT" = true ]; then
    echo "{"
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"summary\": {\"passed\": $PASSED, \"warned\": $WARNED, \"failed\": $FAILED},"
    echo "  \"results\": [$(IFS=,; echo "${RESULTS[*]}")]"
    echo "}"
else
    echo ""
    echo "────────────────────────────────────────────────"
    if [ "$FAILED" -eq 0 ] && [ "$WARNED" -eq 0 ]; then
        echo -e "${GREEN}${BOLD}  ✅  All $PASSED checks passed${NC}"
    elif [ "$FAILED" -eq 0 ]; then
        echo -e "${YELLOW}${BOLD}  ⚠   $PASSED passed, $WARNED warnings, 0 failures${NC}"
    else
        echo -e "${RED}${BOLD}  ✗   $PASSED passed, $WARNED warnings, $FAILED FAILED${NC}"
        echo ""
        echo "  Run with --verbose for more detail"
    fi
    echo "────────────────────────────────────────────────"
fi

[ "$FAILED" -gt 0 ] && exit 1 || exit 0
