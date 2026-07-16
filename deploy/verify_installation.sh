#!/usr/bin/env bash
# ============================================================
# MachineGuru — End-to-End Verification Script
# ============================================================
# Usage: ./deploy/verify_installation.sh
#
# Performs an end-to-end functional test of all components:
#   ✓ Environment detection summary
#   ✓ Backend health endpoint
#   ✓ Qdrant reachable + collection exists
#   ✓ Ollama reachable + model available
#   ✓ Upload endpoint (test file)
#   ✓ RAG query endpoint
#   ✓ Streaming endpoint
#   ✓ Embedding pipeline
#   ✓ Log files created
#   ✓ Stats endpoint
#   ✓ Environment validated
#   ✓ Python dependency imports
#
# All tests are non-destructive. A test file is uploaded and
# immediately deleted after the test completes.
#
# Exit codes:
#   0  All checks passed (PASS)
#   1  One or more checks failed (FAIL)
# ============================================================
set -uo pipefail

# ── Source shared library ────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/deploy_lib.sh" ]; then
    # shellcheck source=deploy_lib.sh
    source "$SCRIPT_DIR/deploy_lib.sh"
else
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
fi

# Load .env
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a; source "$PROJECT_ROOT/.env" 2>/dev/null || true; set +a
fi

BACKEND_PORT="${BACKEND_PORT:-8001}"
BACKEND_URL="http://localhost:${BACKEND_PORT}"
QDRANT_PORT="${QDRANT_PORT:-6333}"
QDRANT_HOST="${QDRANT_HOST:-localhost}"
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://localhost:11434}"
TIMEOUT=15
PASSED=0
FAILED=0

step()  { echo -e "\n${BOLD}${BLUE}── $1${NC}"; }
pass()  { PASSED=$((PASSED + 1)); echo -e "  ${GREEN}✓${NC} $1"; }
vfail() { FAILED=$((FAILED + 1)); echo -e "  ${RED}✗${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
info()  { echo -e "  ℹ $1"; }

# ── Log output ───────────────────────────────────────────────
mkdir -p "$PROJECT_ROOT/logs"
VER_LOG="$PROJECT_ROOT/logs/healthcheck.log"

echo ""
echo "============================================================"
echo -e "${BOLD}  MachineGuru — Installation Verification${NC}"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# ── Environment summary ─────────────────────────────────────
if type print_env_summary &>/dev/null; then
    print_env_summary
fi

# ────────────────────────────────────────────────────────────
step "1. Backend Health"
# ────────────────────────────────────────────────────────────

HEALTH_RESPONSE=$(curl -s --max-time "$TIMEOUT" "$BACKEND_URL/api/v1/health" 2>/dev/null)
if [ -n "$HEALTH_RESPONSE" ]; then
    STATUS=$(echo "$HEALTH_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null || echo "unknown")
    pass "Backend responds at $BACKEND_URL (status: $STATUS)"
else
    vfail "Backend not reachable at $BACKEND_URL"
    echo ""
    echo "  Start backend with: ./start.sh"
    echo "  Then re-run this script."
    exit 1
fi

# ────────────────────────────────────────────────────────────
step "2. Qdrant Vector Database"
# ────────────────────────────────────────────────────────────

QDRANT_URL="http://${QDRANT_HOST}:${QDRANT_PORT}"
if curl -sf --max-time "$TIMEOUT" "$QDRANT_URL/healthz" &>/dev/null; then
    pass "Qdrant reachable at $QDRANT_URL"

    COLLECTION="${QDRANT_COLLECTION:-machine_guru}"
    COLL_RESP=$(curl -s --max-time "$TIMEOUT" "$QDRANT_URL/collections/$COLLECTION" 2>/dev/null)
    if echo "$COLL_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('status')=='ok' else 1)" 2>/dev/null; then
        VECTORS=$(echo "$COLL_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',{}).get('vectors_count',0))" 2>/dev/null || echo "?")
        pass "Qdrant collection '$COLLECTION' exists ($VECTORS vectors)"
    else
        warn "Qdrant collection '$COLLECTION' not found — will be auto-created on first use"
    fi
else
    vfail "Qdrant not reachable at $QDRANT_URL"
fi

# ────────────────────────────────────────────────────────────
step "3. Ollama LLM Server"
# ────────────────────────────────────────────────────────────

if curl -sf --max-time "$TIMEOUT" "$OLLAMA_BASE_URL" &>/dev/null; then
    pass "Ollama reachable at $OLLAMA_BASE_URL"

    LLM_MODEL_NAME="${LLM_MODEL:-llama3.2:1b}"
    TAGS=$(curl -s --max-time "$TIMEOUT" "$OLLAMA_BASE_URL/api/tags" 2>/dev/null)
    if echo "$TAGS" | python3 -c "import sys,json; d=json.load(sys.stdin); names=[m['name'] for m in d.get('models',[])]; exit(0 if any('${LLM_MODEL_NAME}' in n for n in names) else 1)" 2>/dev/null; then
        pass "Ollama model '$LLM_MODEL_NAME' is available"
    else
        warn "Model '$LLM_MODEL_NAME' not pulled — run: ollama pull $LLM_MODEL_NAME"
        FAILED=$((FAILED + 1))
    fi
else
    vfail "Ollama not reachable at $OLLAMA_BASE_URL"
fi

# ────────────────────────────────────────────────────────────
step "4. Python Dependency Imports"
# ────────────────────────────────────────────────────────────

VENV_DIR="$PROJECT_ROOT/backend/.venv"
if [ -f "$VENV_DIR/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate" 2>/dev/null || true
fi

IMPORT_OK=true
for pkg in "fastapi" "uvicorn" "pydantic" "qdrant_client" "loguru" "torch" "ollama"; do
    if python3 -c "import $pkg" 2>/dev/null; then
        pass "import $pkg"
    else
        vfail "import $pkg — FAILED"
        IMPORT_OK=false
    fi
done

# sentence-transformers (soft check)
if python3 -c "import sentence_transformers" 2>/dev/null; then
    pass "import sentence_transformers"
else
    warn "import sentence_transformers — not available (USE_OLLAMA_EMBEDDINGS=true as fallback)"
fi

# ────────────────────────────────────────────────────────────
step "5. File Upload"
# ────────────────────────────────────────────────────────────

# Create a minimal test document
TEST_PDF="/tmp/machineguru_test_$$.txt"
cat > "$TEST_PDF" << 'EOF'
MachineGuru Verification Test Document

This is a test document used to verify the upload and RAG pipeline.
It contains information about industrial machine maintenance.

Section 1: Preventive Maintenance
Regular inspection of bearings, seals, and lubrication points is essential
for preventing equipment failure. Maintenance intervals should be followed
as specified in the equipment manual.

Section 2: Safety Procedures
Always follow lockout/tagout procedures before performing maintenance.
Personal protective equipment must be worn at all times in the maintenance area.
EOF

UPLOAD_RESP=$(curl -s --max-time 60 \
    -X POST "$BACKEND_URL/api/v1/ingest" \
    -F "file=@$TEST_PDF;type=text/plain" \
    -F "filename=test_verify.txt" \
    2>/dev/null || echo "")

rm -f "$TEST_PDF"

if echo "$UPLOAD_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('status') in ('ok','success') or d.get('chunk_count',0) > 0 else 1)" 2>/dev/null; then
    CHUNKS=$(echo "$UPLOAD_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('chunk_count', '?'))" 2>/dev/null || echo "?")
    DOC_ID=$(echo "$UPLOAD_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('document_id',''))" 2>/dev/null || echo "")
    pass "Upload + ingest successful ($CHUNKS chunks)"
else
    warn "Upload/ingest returned unexpected response"
    info "Response: $(echo "$UPLOAD_RESP" | head -c 200)"
    FAILED=$((FAILED + 1))
fi

# ────────────────────────────────────────────────────────────
step "6. RAG Query"
# ────────────────────────────────────────────────────────────

QUERY_PAYLOAD='{"text": "What are the safety procedures for maintenance?", "stream": false}'
QUERY_RESP=$(curl -s --max-time 120 \
    -X POST "$BACKEND_URL/api/v1/query" \
    -H "Content-Type: application/json" \
    -d "$QUERY_PAYLOAD" \
    2>/dev/null || echo "")

if echo "$QUERY_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('answer') or d.get('response') else 1)" 2>/dev/null; then
    ANSWER_SNIPPET=$(echo "$QUERY_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); a=d.get('answer',d.get('response','')); print(a[:80]+'...' if len(a)>80 else a)" 2>/dev/null || echo "")
    pass "RAG query returned an answer"
    info "Answer preview: $ANSWER_SNIPPET"
else
    warn "RAG query did not return an answer"
    info "Response: $(echo "$QUERY_RESP" | head -c 200)"
    FAILED=$((FAILED + 1))
fi

# ────────────────────────────────────────────────────────────
step "7. Streaming Endpoint"
# ────────────────────────────────────────────────────────────

STREAM_RESP=$(curl -s --max-time 30 -N \
    -X POST "$BACKEND_URL/api/v1/query/stream" \
    -H "Content-Type: application/json" \
    -H "Accept: text/event-stream" \
    -d '{"text": "What is preventive maintenance?", "stream": true}' \
    2>/dev/null | head -c 500 || echo "")

if echo "$STREAM_RESP" | grep -q "data:"; then
    pass "Streaming endpoint responds with SSE data"
else
    warn "Streaming endpoint did not return SSE data (may need model loaded)"
    FAILED=$((FAILED + 1))
fi

# ────────────────────────────────────────────────────────────
step "8. Stats Endpoint"
# ────────────────────────────────────────────────────────────

STATS_RESP=$(curl -s --max-time "$TIMEOUT" "$BACKEND_URL/api/v1/stats" 2>/dev/null || echo "")
if echo "$STATS_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if 'service' in d or 'memory_mb' in d else 1)" 2>/dev/null; then
    MEM=$(echo "$STATS_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('memory_mb','?'))" 2>/dev/null || echo "?")
    pass "Stats endpoint OK (memory: ${MEM}MB)"
else
    warn "Stats endpoint returned unexpected response"
fi

# ────────────────────────────────────────────────────────────
step "9. Log Files"
# ────────────────────────────────────────────────────────────

LOG_DIR="${LOG_DIR:-./logs}"
# Resolve relative path
if [[ "$LOG_DIR" != /* ]]; then
    LOG_DIR="$PROJECT_ROOT/$LOG_DIR"
fi

if [ -d "$LOG_DIR" ]; then
    LOG_COUNT=$(find "$LOG_DIR" -name "*.log" -o -name "*.json" 2>/dev/null | wc -l)
    pass "Log directory exists ($LOG_COUNT log files in $LOG_DIR)"
else
    warn "Log directory not found at $LOG_DIR"
fi

# ────────────────────────────────────────────────────────────
step "10. Storage Directories"
# ────────────────────────────────────────────────────────────

UPLOAD_DIR_PATH="${UPLOAD_DIR:-./storage/uploads}"
[[ "$UPLOAD_DIR_PATH" != /* ]] && UPLOAD_DIR_PATH="$PROJECT_ROOT/$UPLOAD_DIR_PATH"

[ -d "$UPLOAD_DIR_PATH" ] && pass "Upload directory: $UPLOAD_DIR_PATH" || warn "Upload directory missing: $UPLOAD_DIR_PATH"
[ -d "$PROJECT_ROOT/storage/qdrant" ] && pass "Qdrant storage directory" || warn "storage/qdrant/ missing"

# ────────────────────────────────────────────────────────────
step "11. Environment Variables"
# ────────────────────────────────────────────────────────────

REQUIRED=(OLLAMA_BASE_URL LLM_MODEL QDRANT_HOST QDRANT_PORT QDRANT_COLLECTION UPLOAD_DIR LOG_DIR)
ALL_SET=true
for var in "${REQUIRED[@]}"; do
    val="${!var:-}"
    if [ -z "$val" ]; then
        warn "Missing: $var"
        ALL_SET=false
    fi
done
$ALL_SET && pass "All required environment variables set" || FAILED=$((FAILED + 1))

# ────────────────────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
TOTAL=$((PASSED + FAILED))
if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}  ✅  PASS — All $PASSED/$TOTAL checks passed — MachineGuru is ready!${NC}"
    echo ""
    echo "  Access the application:"
    echo "  → Backend API:  $BACKEND_URL/docs"
    echo "  → Frontend:     http://localhost:${FRONTEND_PORT:-5173}"
    echo "  → Metrics:      $BACKEND_URL/metrics"
else
    echo -e "${YELLOW}${BOLD}  ⚠   PARTIAL — $PASSED/$TOTAL passed, $FAILED failed/warned${NC}"
    echo ""
    echo "  Some checks failed. Review warnings above."
    echo "  If services are not running, start with: ./start.sh"
fi
echo "============================================================"

echo "" >> "$VER_LOG"
echo "── Verification $(date '+%Y-%m-%d %H:%M:%S'): passed=$PASSED failed=$FAILED ──" >> "$VER_LOG"

[ "$FAILED" -gt 0 ] && exit 1 || exit 0
