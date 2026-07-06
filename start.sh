#!/bin/bash
# ────────────────────────────────────────────
# MachineGuru — Start All Services
# Usage: ./start.sh
# ────────────────────────────────────────────

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "🤖  MachineGuru — Starting services..."
echo "────────────────────────────────────────"

# ── 1. Kill stale processes ──────────────────
echo -e "${YELLOW}[1/4] Cleaning up old processes...${NC}"
pkill -f "qdrant_bin/qdrant"  2>/dev/null && echo "  ✓ Stopped old Qdrant"   || echo "  ✓ Qdrant was not running"
# Kill by port — more reliable than process name matching
PIDS=$(lsof -t -i :8001 2>/dev/null)
if [ -n "$PIDS" ]; then
  kill -9 $PIDS 2>/dev/null && echo "  ✓ Stopped old backend (port 8001)"
else
  echo "  ✓ Backend was not running"
fi
sleep 2

# ── 2. Start Qdrant ─────────────────────────
echo -e "${YELLOW}[2/4] Starting Qdrant...${NC}"
mkdir -p "$DIR/qdrant_storage"
QDRANT__STORAGE__STORAGE_PATH="$DIR/qdrant_storage" \
  "$DIR/qdrant_bin/qdrant" > "$DIR/logs/qdrant.log" 2>&1 &
QDRANT_PID=$!

# Wait for Qdrant to be ready (up to 15 seconds)
for i in $(seq 1 15); do
  if curl -sf http://localhost:6333/healthz > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓ Qdrant ready (pid $QDRANT_PID)${NC}"
    break
  fi
  if [ $i -eq 15 ]; then
    echo -e "  ${RED}✗ Qdrant failed to start. Check logs/qdrant.log${NC}"
    exit 1
  fi
  sleep 1
done

# ── 3. Start Backend ─────────────────────────
echo -e "${YELLOW}[3/4] Starting backend (port 8001)...${NC}"
mkdir -p "$DIR/logs"
cd "$DIR/backend"
source .venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8001 > "$DIR/logs/backend.log" 2>&1 &
BACKEND_PID=$!

# Wait for backend to be ready (up to 15 seconds)
for i in $(seq 1 15); do
  if curl -sf http://localhost:8001/api/v1/health > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓ Backend ready (pid $BACKEND_PID)${NC}"
    break
  fi
  if [ $i -eq 15 ]; then
    echo -e "  ${RED}✗ Backend failed to start. Check logs/backend.log${NC}"
    exit 1
  fi
  sleep 1
done

# ── 4. Summary ───────────────────────────────
echo -e "${YELLOW}[4/4] Verifying health...${NC}"
HEALTH=$(curl -sf http://localhost:8001/api/v1/health)
VECTORS=$(echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['qdrant']['point_count'])" 2>/dev/null || echo "?")

echo ""
echo "────────────────────────────────────────"
echo -e "${GREEN}✅  All services running!${NC}"
echo ""
echo "  Service   │ URL                           │ PID"
echo "  ──────────┼───────────────────────────────┼──────"
printf "  Qdrant    │ http://localhost:6333/dashboard │ %s\n" "$QDRANT_PID"
printf "  Backend   │ http://localhost:8001/docs      │ %s\n" "$BACKEND_PID"
echo "  Frontend  │ run: npm run dev (port 5174)   │ manual"
echo ""
echo "  📦 Vectors in Qdrant: $VECTORS"
echo "  📋 Logs: $DIR/logs/"
echo ""
echo "  To stop everything: ./stop.sh"
echo "────────────────────────────────────────"
