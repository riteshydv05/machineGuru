#!/bin/bash
# ────────────────────────────────────────────
# MachineGuru — Stop All Services
# Usage: ./stop.sh
# ────────────────────────────────────────────

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "🛑  MachineGuru — Stopping services..."
echo "────────────────────────────────────────"

pkill -f "qdrant_bin/qdrant" 2>/dev/null  && echo -e "  ${GREEN}✓ Qdrant stopped${NC}"   || echo "  ✓ Qdrant was not running"
pkill -f "uvicorn main:app"  2>/dev/null  && echo -e "  ${GREEN}✓ Backend stopped${NC}"  || echo "  ✓ Backend was not running"

echo ""
echo -e "${GREEN}✅  All services stopped.${NC}"
echo "────────────────────────────────────────"
