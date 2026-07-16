#!/usr/bin/env bash
# ============================================================
# MachineGuru — Production-Grade Health Check Script
# ============================================================
# Usage: ./deploy/healthcheck.sh [--verbose] [--json]
#
# Comprehensive checks:
#   System:    Python version, Node version, disk, RAM, swap, GPU
#   Hardware:  Jetson detection, CUDA, GPU memory
#   Services:  Ollama, Qdrant, Backend, Frontend
#   Config:    Environment variables, storage directories
#   Network:   Port availability, service connectivity
#   Deps:      Backend Python dependencies importable
#   Build:     Frontend build exists
#
# Exit codes:
#   0  All checks passed
#   1  One or more checks failed
# ============================================================
set -uo pipefail

# ── Source shared library ────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=deploy_lib.sh
source "$SCRIPT_DIR/deploy_lib.sh"

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

# ── Log to file ──────────────────────────────────────────────
mkdir -p "$PROJECT_ROOT/logs"
HC_LOG="$PROJECT_ROOT/logs/healthcheck.log"
echo "── Healthcheck $(date '+%Y-%m-%d %H:%M:%S') ──" >> "$HC_LOG"

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

hc_pass() {
    local label="$1" msg="${2:-}"
    PASSED=$((PASSED + 1))
    RESULTS+=("{\"check\":\"$label\",\"status\":\"pass\",\"detail\":\"$msg\"}")
    echo "PASS: $label — $msg" >> "$HC_LOG"
    if [ "$JSON_OUTPUT" = false ]; then
        printf "  ${GREEN}✓${NC} %-45s ${GREEN}OK${NC}" "$label"
        [ -n "$msg" ] && echo " — $msg" || echo ""
    fi
}

hc_fail() {
    local label="$1" msg="${2:-}"
    FAILED=$((FAILED + 1))
    RESULTS+=("{\"check\":\"$label\",\"status\":\"fail\",\"detail\":\"$msg\"}")
    echo "FAIL: $label — $msg" >> "$HC_LOG"
    if [ "$JSON_OUTPUT" = false ]; then
        printf "  ${RED}✗${NC} %-45s ${RED}FAIL${NC}" "$label"
        [ -n "$msg" ] && echo " — $msg" || echo ""
    fi
}

hc_warn() {
    local label="$1" msg="${2:-}"
    WARNED=$((WARNED + 1))
    RESULTS+=("{\"check\":\"$label\",\"status\":\"warn\",\"detail\":\"$msg\"}")
    echo "WARN: $label — $msg" >> "$HC_LOG"
    if [ "$JSON_OUTPUT" = false ]; then
        printf "  ${YELLOW}⚠${NC} %-45s ${YELLOW}WARN${NC}" "$label"
        [ -n "$msg" ] && echo " — $msg" || echo ""
    fi
}

section() {
    [ "$JSON_OUTPUT" = false ] && echo -e "\n${BOLD}${BLUE}── $1${NC}"
}

# Print header
if [ "$JSON_OUTPUT" = false ]; then
    echo ""
    echo "============================================================"
    echo -e "${BOLD}  MachineGuru — Health Check${NC}"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================================"
fi

# ────────────────────────────────────────────────────────────
section "System"
# ────────────────────────────────────────────────────────────

# Python version
PYTHON_BIN="$(find_python 2>/dev/null || echo "")"
if [ -n "$PYTHON_BIN" ]; then
    PY_VER=$("$PYTHON_BIN" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
    hc_pass "Python 3.10+" "$PY_VER ($PYTHON_BIN)"
else
    hc_fail "Python 3.10+" "not found"
fi

# Node.js
if command -v node &>/dev/null; then
    NODE_VER=$(node -v | sed 's/v//')
    NODE_MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
    [ "$NODE_MAJOR" -ge 20 ] 2>/dev/null && hc_pass "Node.js 20+" "v$NODE_VER" || hc_warn "Node.js 20+" "found v$NODE_VER — v20+ recommended"
else
    hc_warn "Node.js" "not found — required for frontend"
fi

# Disk space
if [ "$(uname -s)" = "Linux" ]; then
    DISK_FREE_GB=$(df -BG "$PROJECT_ROOT" | tail -1 | awk '{print $4}' | sed 's/G//')
elif [ "$(uname -s)" = "Darwin" ]; then
    DISK_FREE_GB=$(df -g "$PROJECT_ROOT" 2>/dev/null | tail -1 | awk '{print $4}')
else
    DISK_FREE_GB=999
fi

if [ "${DISK_FREE_GB:-0}" -ge 5 ] 2>/dev/null; then
    hc_pass "Disk space" "${DISK_FREE_GB}GB free"
elif [ "${DISK_FREE_GB:-0}" -ge 2 ] 2>/dev/null; then
    hc_warn "Disk space" "${DISK_FREE_GB}GB free — low, recommend 10GB+"
else
    hc_fail "Disk space" "${DISK_FREE_GB:-?}GB free — critical, need at least 5GB"
fi

# RAM
if [ -f /proc/meminfo ]; then
    MEM_TOTAL_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
    MEM_FREE_MB=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
elif [ "$(uname -s)" = "Darwin" ]; then
    MEM_TOTAL_MB=$(($(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1048576))
    MEM_FREE_MB="n/a"
else
    MEM_TOTAL_MB=0
    MEM_FREE_MB=0
fi

if [ "$MEM_TOTAL_MB" -ge 4096 ] 2>/dev/null; then
    hc_pass "RAM total" "${MEM_TOTAL_MB}MB (${MEM_FREE_MB}MB free)"
elif [ "$MEM_TOTAL_MB" -ge 2048 ] 2>/dev/null; then
    hc_warn "RAM total" "${MEM_TOTAL_MB}MB — 8GB+ recommended for Jetson"
else
    hc_fail "RAM total" "${MEM_TOTAL_MB}MB — insufficient, need at least 4GB"
fi

# Swap
if [ -f /proc/meminfo ]; then
    SWAP_TOTAL_MB=$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
    if [ "$SWAP_TOTAL_MB" -ge 4096 ] 2>/dev/null; then
        hc_pass "Swap" "${SWAP_TOTAL_MB}MB"
    elif [ "$SWAP_TOTAL_MB" -gt 0 ] 2>/dev/null; then
        hc_warn "Swap" "${SWAP_TOTAL_MB}MB — 4GB+ recommended"
    else
        hc_warn "Swap" "none configured"
    fi
fi

# ────────────────────────────────────────────────────────────
section "Hardware / GPU"
# ────────────────────────────────────────────────────────────

# Jetson hardware
if [ -f /proc/device-tree/model ]; then
    JETSON_MODEL=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || echo "")
    if [ -n "$JETSON_MODEL" ]; then
        hc_pass "Jetson hardware" "$JETSON_MODEL"
    fi
elif [ -f /etc/nv_tegra_release ]; then
    hc_pass "Jetson hardware" "Tegra platform detected"
fi

# CUDA / GPU
detect_cuda
if [ "$CUDA_AVAILABLE" = true ]; then
    hc_pass "CUDA" "version $CUDA_VERSION"
    [ -n "$GPU_NAME" ] && hc_pass "GPU" "$GPU_NAME"
else
    hc_warn "CUDA" "not available — GPU acceleration disabled"
fi

# GPU memory (nvidia-smi or tegrastats)
if command -v nvidia-smi &>/dev/null; then
    GPU_MEM=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
    if [ -n "$GPU_MEM" ]; then
        hc_pass "GPU memory" "${GPU_MEM} MB (used,total)"
    fi
fi

# ────────────────────────────────────────────────────────────
section "Environment Configuration"
# ────────────────────────────────────────────────────────────

# .env file exists
[ -f "$PROJECT_ROOT/.env" ] && hc_pass ".env file" "found" || hc_fail ".env file" "missing — run: cp .env.example .env"

# Required environment variables
REQUIRED_VARS=(OLLAMA_BASE_URL LLM_MODEL QDRANT_HOST QDRANT_PORT UPLOAD_DIR LOG_DIR)
for var in "${REQUIRED_VARS[@]}"; do
    val="${!var:-}"
    [ -n "$val" ] && hc_pass "ENV: $var" "$val" || hc_fail "ENV: $var" "not set in .env"
done

# Virtual environment or user packages
VENV_DIR="$PROJECT_ROOT/backend/.venv"
if [ -d "$VENV_DIR" ] && [ -f "$VENV_DIR/bin/activate" ]; then
    hc_pass "Python environment" "venv at $VENV_DIR"
elif [ -n "$PYTHON_BIN" ] && "$PYTHON_BIN" -c "import fastapi" 2>/dev/null; then
    hc_pass "Python environment" "user/system packages (fastapi importable)"
else
    hc_fail "Python environment" "no venv and dependencies not found — run deploy/install.sh"
fi

# ────────────────────────────────────────────────────────────
section "Backend Dependencies"
# ────────────────────────────────────────────────────────────

# Activate venv if it exists for import checks
if [ -d "$VENV_DIR" ] && [ -f "$VENV_DIR/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate" 2>/dev/null || true
fi

CRITICAL_PKGS=("fastapi" "uvicorn" "pydantic" "qdrant_client" "loguru" "torch" "ollama")
for pkg in "${CRITICAL_PKGS[@]}"; do
    if python3 -c "import $pkg" 2>/dev/null; then
        hc_pass "Python: $pkg" "importable"
    else
        hc_fail "Python: $pkg" "NOT importable"
    fi
done

# sentence-transformers (may fail on Cloud Lab)
if python3 -c "import sentence_transformers" 2>/dev/null; then
    hc_pass "Python: sentence-transformers" "importable"
else
    hc_warn "Python: sentence-transformers" "NOT importable — set USE_OLLAMA_EMBEDDINGS=true as fallback"
fi

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
    if [ -d "$dir" ]; then
        if [ -w "$dir" ]; then
            hc_pass "Directory: $(basename "$dir")" "$dir (writable)"
        else
            hc_warn "Directory: $(basename "$dir")" "$dir (NOT writable)"
        fi
    else
        hc_warn "Directory: $(basename "$dir")" "missing — will be created on startup"
    fi
done

# ────────────────────────────────────────────────────────────
section "Frontend Build"
# ────────────────────────────────────────────────────────────

if [ -d "$PROJECT_ROOT/frontend/dist" ] && [ -f "$PROJECT_ROOT/frontend/dist/index.html" ]; then
    hc_pass "Frontend build" "frontend/dist/ exists"
else
    hc_warn "Frontend build" "frontend/dist/ not found — build with: cd frontend && npm run build"
fi

# ────────────────────────────────────────────────────────────
section "Service Health"
# ────────────────────────────────────────────────────────────

http_check() {
    local label="$1" url="$2" expected="${3:-200}"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "$url" 2>/dev/null || echo "000")
    if [ "$code" = "$expected" ]; then
        hc_pass "$label" "HTTP $code at $url"
    else
        hc_fail "$label" "HTTP $code (expected $expected) at $url"
    fi
}

# Ollama
OLLAMA_STATUS="$(detect_ollama)"
case "$OLLAMA_STATUS" in
    INSTALLED_RUNNING)
        DETECTED_URL="$(detect_ollama_url)"
        hc_pass "Ollama installed" "$(ollama --version 2>/dev/null | head -1 || echo 'yes')"
        http_check "Ollama API" "$DETECTED_URL" "200"
        ;;
    INSTALLED_STOPPED)
        hc_pass "Ollama installed" "$(ollama --version 2>/dev/null | head -1 || echo 'yes')"
        hc_fail "Ollama running" "installed but not running — start: ollama serve"
        ;;
    MISSING)
        hc_fail "Ollama installed" "not found — install: curl -fsSL https://ollama.com/install.sh | sh"
        ;;
esac

# Qdrant
http_check "Qdrant health" "http://${QDRANT_HOST}:${QDRANT_PORT}/healthz" "200"

# Backend
http_check "Backend /health" "http://localhost:${BACKEND_PORT}/api/v1/health" "200"

# Frontend
if curl -sf "http://localhost:${FRONTEND_PORT}" &>/dev/null; then
    hc_pass "Frontend" "HTTP 200 at http://localhost:${FRONTEND_PORT}"
else
    hc_warn "Frontend" "not reachable at port ${FRONTEND_PORT}"
fi

# Qdrant collection
if curl -sf "http://${QDRANT_HOST}:${QDRANT_PORT}/healthz" &>/dev/null; then
    COLLECTION="${QDRANT_COLLECTION:-machine_guru}"
    if curl -sf "http://${QDRANT_HOST}:${QDRANT_PORT}/collections/${COLLECTION}" &>/dev/null; then
        POINT_COUNT=$(curl -s "http://${QDRANT_HOST}:${QDRANT_PORT}/collections/${COLLECTION}" 2>/dev/null | \
            python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',{}).get('vectors_count',0))" 2>/dev/null || echo "?")
        hc_pass "Qdrant collection" "$COLLECTION ($POINT_COUNT vectors)"
    else
        hc_warn "Qdrant collection" "$COLLECTION not found — will be created on first backend start"
    fi
fi

# Ollama model check
if [ "$OLLAMA_STATUS" = "INSTALLED_RUNNING" ]; then
    DETECTED_URL="$(detect_ollama_url 2>/dev/null || echo "$OLLAMA_BASE_URL")"
    LLM_MODEL_NAME="${LLM_MODEL:-llama3.2:1b}"
    MODELS=$(curl -s "$DETECTED_URL/api/tags" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); names=[m['name'] for m in d.get('models',[])]; print(' '.join(names))" 2>/dev/null || echo "")
    if echo "$MODELS" | grep -q "$LLM_MODEL_NAME"; then
        hc_pass "Ollama model: $LLM_MODEL_NAME" "loaded"
    else
        hc_warn "Ollama model: $LLM_MODEL_NAME" "not found — run: ollama pull $LLM_MODEL_NAME"
    fi
fi

# ────────────────────────────────────────────────────────────
section "Ports"
# ────────────────────────────────────────────────────────────

for port_info in "${BACKEND_PORT}:Backend" "${QDRANT_PORT}:Qdrant" "11434:Ollama"; do
    port="${port_info%%:*}"
    label="${port_info##*:}"
    if check_port_listening "$port"; then
        hc_pass "$label (port $port)" "listening"
    else
        hc_warn "$label (port $port)" "not listening"
    fi
done

# ────────────────────────────────────────────────────────────
# Results
# ────────────────────────────────────────────────────────────

if [ "$JSON_OUTPUT" = true ]; then
    echo "{"
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date '+%Y-%m-%dT%H:%M:%SZ')\","
    echo "  \"environment\": \"$(detect_environment)\","
    echo "  \"summary\": {\"passed\": $PASSED, \"warned\": $WARNED, \"failed\": $FAILED},"
    echo "  \"results\": [$(IFS=,; echo "${RESULTS[*]}")]"
    echo "}"
else
    echo ""
    echo "════════════════════════════════════════════════════════"
    if [ "$FAILED" -eq 0 ] && [ "$WARNED" -eq 0 ]; then
        echo -e "${GREEN}${BOLD}  ✅  All $PASSED checks passed${NC}"
    elif [ "$FAILED" -eq 0 ]; then
        echo -e "${YELLOW}${BOLD}  ⚠   $PASSED passed, $WARNED warnings, 0 failures${NC}"
    else
        echo -e "${RED}${BOLD}  ✗   $PASSED passed, $WARNED warnings, $FAILED FAILED${NC}"
        echo ""
        echo "  Run with --verbose for more detail"
    fi
    echo "════════════════════════════════════════════════════════"
fi

echo "" >> "$HC_LOG"
echo "Result: passed=$PASSED warned=$WARNED failed=$FAILED" >> "$HC_LOG"

[ "$FAILED" -gt 0 ] && exit 1 || exit 0
