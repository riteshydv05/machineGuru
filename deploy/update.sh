#!/usr/bin/env bash
# ============================================================
# MachineGuru — Update Script
# ============================================================
# Usage: ./deploy/update.sh [--restart] [--skip-models]
#
# What this script does:
#   1. Pulls latest code from git
#   2. Re-installs Python dependencies if requirements.txt changed
#   3. Re-installs npm packages if package.json changed
#   4. Rebuilds the frontend
#   5. Optionally restarts services (./stop.sh && ./start.sh)
# ============================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

RESTART_AFTER=false
SKIP_MODELS=false
for arg in "$@"; do
    case $arg in
        --restart)      RESTART_AFTER=true ;;
        --skip-models)  SKIP_MODELS=true ;;
    esac
done

step()  { echo -e "\n${BOLD}${BLUE}▶ $1${NC}"; }
ok()    { echo -e "  ${GREEN}✓ $1${NC}"; }
warn()  { echo -e "  ${YELLOW}⚠ $1${NC}"; }
info()  { echo -e "  ℹ $1"; }

mkdir -p "$PROJECT_ROOT/logs"
exec > >(tee -a "$PROJECT_ROOT/logs/deployment.log") 2>&1

echo ""
echo "============================================================"
echo "  MachineGuru — Update  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# ── Snapshot hashes for change detection ──────────────────────
REQ_HASH_BEFORE=$(md5sum "$PROJECT_ROOT/backend/requirements.txt" 2>/dev/null | cut -d' ' -f1 || echo "none")
PKG_HASH_BEFORE=$(md5sum "$PROJECT_ROOT/frontend/package.json" 2>/dev/null | cut -d' ' -f1 || echo "none")

# ── Git pull ──────────────────────────────────────────────────
step "Pulling latest code"
if git rev-parse --is-inside-work-tree &>/dev/null; then
    git pull --ff-only
    ok "Code updated"
    COMMIT=$(git log -1 --format="%h %s" 2>/dev/null || echo "unknown")
    info "Latest commit: $COMMIT"
else
    warn "Not a git repository — skipping git pull"
fi

# ── Python dependencies ───────────────────────────────────────
REQ_HASH_AFTER=$(md5sum "$PROJECT_ROOT/backend/requirements.txt" 2>/dev/null | cut -d' ' -f1 || echo "none")
if [ "$REQ_HASH_BEFORE" != "$REQ_HASH_AFTER" ]; then
    step "requirements.txt changed — reinstalling Python dependencies"
    source "$PROJECT_ROOT/backend/.venv/bin/activate"
    pip install -r "$PROJECT_ROOT/backend/requirements.txt" --quiet
    ok "Python dependencies updated"
else
    ok "requirements.txt unchanged — skipping pip install"
fi

# ── Node dependencies ─────────────────────────────────────────
PKG_HASH_AFTER=$(md5sum "$PROJECT_ROOT/frontend/package.json" 2>/dev/null | cut -d' ' -f1 || echo "none")
if [ "$PKG_HASH_BEFORE" != "$PKG_HASH_AFTER" ]; then
    step "package.json changed — reinstalling npm packages"
    cd "$PROJECT_ROOT/frontend"
    npm install --silent
    ok "npm packages updated"
    cd "$PROJECT_ROOT"
else
    ok "package.json unchanged — skipping npm install"
fi

# ── Rebuild frontend ──────────────────────────────────────────
step "Rebuilding frontend"
cd "$PROJECT_ROOT/frontend"
npm run build
ok "Frontend built to frontend/dist/"
cd "$PROJECT_ROOT"

# ── Script permissions ────────────────────────────────────────
chmod +x "$PROJECT_ROOT/start.sh" "$PROJECT_ROOT/stop.sh" "$PROJECT_ROOT/deploy/"*.sh 2>/dev/null || true

# ── Restart services ──────────────────────────────────────────
if [ "$RESTART_AFTER" = true ]; then
    step "Restarting services"
    "$PROJECT_ROOT/stop.sh" || true
    sleep 2
    "$PROJECT_ROOT/start.sh"
else
    warn "Services not restarted. Run ./stop.sh && ./start.sh to apply updates."
fi

echo ""
echo -e "${GREEN}${BOLD}  ✅  Update complete!${NC}"
echo ""
