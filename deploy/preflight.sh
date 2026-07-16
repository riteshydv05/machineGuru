#!/usr/bin/env bash
# ============================================================
# MachineGuru — Preflight Check
# ============================================================
# Run this BEFORE install.sh to validate the environment.
# It checks everything needed for a successful deployment
# without making any modifications to the system.
#
# Usage: ./deploy/preflight.sh
#
# Exit codes:
#   0  All checks passed — safe to install
#   1  Critical checks failed — fix before installing
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=deploy_lib.sh
source "$SCRIPT_DIR/deploy_lib.sh"

FAILED=0
WARNED=0
PASSED=0

pass_check() {
    PASSED=$((PASSED + 1))
    echo -e "  ${GREEN}✓${NC} $1"
}

fail_check() {
    FAILED=$((FAILED + 1))
    echo -e "  ${RED}✗${NC} $1"
    [ -n "${2:-}" ] && echo -e "    ${DIM}Fix: $2${NC}"
}

warn_check() {
    WARNED=$((WARNED + 1))
    echo -e "  ${YELLOW}⚠${NC} $1"
    [ -n "${2:-}" ] && echo -e "    ${DIM}$2${NC}"
}

echo ""
echo "============================================================"
echo -e "${BOLD}  MachineGuru — Preflight Check${NC}"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# ── Environment detection ────────────────────────────────────
print_env_summary

# ────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}── Operating System${NC}"
# ────────────────────────────────────────────────────────────

OS="$(uname -s)"
ARCH="$(uname -m)"

if [ "$OS" = "Linux" ]; then
    pass_check "Operating system: Linux"
elif [ "$OS" = "Darwin" ]; then
    warn_check "Operating system: macOS (development only)" \
        "Production deployment requires Linux"
else
    fail_check "Unsupported OS: $OS" \
        "Use Ubuntu Linux 20.04+ or macOS for development"
fi

if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "arm64" ]; then
    pass_check "Architecture: $ARCH"
else
    fail_check "Unsupported architecture: $ARCH" \
        "Supported: aarch64 (Jetson/ARM), x86_64, arm64 (macOS)"
fi

# ────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}── Python${NC}"
# ────────────────────────────────────────────────────────────

PYTHON_BIN="$(find_python 2>/dev/null || echo "")"

if [ -n "$PYTHON_BIN" ]; then
    PY_VER=$("$PYTHON_BIN" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
    pass_check "Python 3.10+: $PYTHON_BIN ($PY_VER)"
else
    fail_check "Python 3.10+ not found" \
        "Install Python 3.10+: sudo apt install python3 python3-pip"
fi

# venv check
if [ -n "$PYTHON_BIN" ]; then
    if check_venv_available "$PYTHON_BIN"; then
        pass_check "Python venv module available"
    else
        warn_check "Python venv module not available" \
            "Will use 'pip install --user' as fallback. Install: sudo apt install python3-venv"
    fi
fi

# pip check
if command -v pip3 &>/dev/null || ([ -n "$PYTHON_BIN" ] && "$PYTHON_BIN" -m pip --version &>/dev/null 2>&1); then
    pass_check "pip available"
else
    fail_check "pip not found" \
        "Install: sudo apt install python3-pip"
fi

# ────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}── Node.js${NC}"
# ────────────────────────────────────────────────────────────

if command -v node &>/dev/null; then
    NODE_VER=$(node -v | sed 's/v//')
    NODE_MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
    if [ "$NODE_MAJOR" -ge 20 ] 2>/dev/null; then
        pass_check "Node.js: v$NODE_VER"
    else
        warn_check "Node.js v$NODE_VER found (v20+ recommended)" \
            "Install Node.js 20: curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -"
    fi
else
    warn_check "Node.js not found" \
        "Required for frontend. Install: curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -"
fi

if command -v npm &>/dev/null; then
    pass_check "npm: $(npm -v 2>/dev/null)"
else
    warn_check "npm not found" "Will be installed with Node.js"
fi

# ────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}── System Resources${NC}"
# ────────────────────────────────────────────────────────────

# Disk space
if [ "$OS" = "Linux" ]; then
    DISK_FREE_GB=$(df -BG "$PROJECT_ROOT" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//')
elif [ "$OS" = "Darwin" ]; then
    DISK_FREE_GB=$(df -g "$PROJECT_ROOT" 2>/dev/null | tail -1 | awk '{print $4}')
else
    DISK_FREE_GB=999
fi

if [ "${DISK_FREE_GB:-0}" -ge 10 ] 2>/dev/null; then
    pass_check "Disk space: ${DISK_FREE_GB}GB free"
elif [ "${DISK_FREE_GB:-0}" -ge 5 ] 2>/dev/null; then
    warn_check "Disk space: ${DISK_FREE_GB}GB free (10GB+ recommended)"
else
    fail_check "Disk space: ${DISK_FREE_GB:-?}GB free (need at least 5GB)" \
        "Free up disk space before installation"
fi

# RAM
if [ -f /proc/meminfo ]; then
    MEM_TOTAL_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
    MEM_FREE_MB=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
elif [ "$OS" = "Darwin" ]; then
    MEM_TOTAL_MB=$(($(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1048576))
    MEM_FREE_MB="N/A"
else
    MEM_TOTAL_MB=0
    MEM_FREE_MB=0
fi

if [ "$MEM_TOTAL_MB" -ge 8192 ] 2>/dev/null; then
    pass_check "RAM: ${MEM_TOTAL_MB}MB total"
elif [ "$MEM_TOTAL_MB" -ge 4096 ] 2>/dev/null; then
    warn_check "RAM: ${MEM_TOTAL_MB}MB total (8GB+ recommended for Jetson)"
elif [ "$MEM_TOTAL_MB" -gt 0 ] 2>/dev/null; then
    fail_check "RAM: ${MEM_TOTAL_MB}MB total (need at least 4GB)" \
        "System needs at least 4GB RAM"
fi

# Swap (Linux only)
if [ -f /proc/meminfo ]; then
    SWAP_TOTAL_MB=$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
    if [ "$SWAP_TOTAL_MB" -ge 4096 ] 2>/dev/null; then
        pass_check "Swap: ${SWAP_TOTAL_MB}MB"
    elif [ "$SWAP_TOTAL_MB" -gt 0 ] 2>/dev/null; then
        warn_check "Swap: ${SWAP_TOTAL_MB}MB (4GB+ recommended for large model loading)" \
            "Increase swap: sudo fallocate -l 8G /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
    else
        warn_check "No swap configured" \
            "Recommended for Jetson: sudo fallocate -l 8G /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
    fi
fi

# ────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}── Network & Repositories${NC}"
# ────────────────────────────────────────────────────────────

if check_internet; then
    pass_check "Internet connectivity"
else
    warn_check "No internet connectivity detected" \
        "Some installation steps will be skipped. Pre-install dependencies if possible."
fi

if [ "$OS" = "Linux" ]; then
    if command -v apt-get &>/dev/null; then
        if check_apt_available; then
            pass_check "apt repositories reachable"
        else
            warn_check "apt repositories unreachable" \
                "System packages cannot be installed. Existing packages will be used."
        fi
    fi
fi

# ────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}── System Dependencies${NC}"
# ────────────────────────────────────────────────────────────

# tzdata
if check_tzdata; then
    pass_check "Timezone data (tzdata)"
else
    fail_check "Timezone data missing (/usr/share/zoneinfo/tzdata.zi)" \
        "Cloud image is missing tzdata. Contact administrator or run: sudo apt install tzdata"
fi

# curl
if command -v curl &>/dev/null; then
    pass_check "curl"
else
    fail_check "curl not found" "Install: sudo apt install curl"
fi

# git
if command -v git &>/dev/null; then
    pass_check "git"
else
    warn_check "git not found" "Install: sudo apt install git"
fi

# jq (optional but useful)
if command -v jq &>/dev/null; then
    pass_check "jq"
else
    warn_check "jq not found (optional)" "Install: sudo apt install jq"
fi

# ────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}── Ollama${NC}"
# ────────────────────────────────────────────────────────────

OLLAMA_STATUS="$(detect_ollama)"
case "$OLLAMA_STATUS" in
    INSTALLED_RUNNING)
        OLLAMA_VER=$(ollama --version 2>/dev/null | head -1 || echo "unknown")
        pass_check "Ollama installed and running ($OLLAMA_VER)"
        OLLAMA_URL="$(detect_ollama_url)"
        pass_check "Ollama reachable at $OLLAMA_URL"
        ;;
    INSTALLED_STOPPED)
        warn_check "Ollama installed but not running" \
            "Start with: ollama serve (or: sudo systemctl start ollama)"
        ;;
    MISSING)
        warn_check "Ollama not installed" \
            "Install: curl -fsSL https://ollama.com/install.sh | sh"
        ;;
esac

# ────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}── GPU / CUDA${NC}"
# ────────────────────────────────────────────────────────────

detect_cuda

if [ "$CUDA_AVAILABLE" = true ]; then
    pass_check "CUDA available: $CUDA_VERSION"
    [ -n "$GPU_NAME" ] && pass_check "GPU: $GPU_NAME"
else
    warn_check "CUDA not detected — will use CPU mode" \
        "For Jetson GPU support, ensure JetPack is installed: sudo apt install nvidia-jetpack"
fi

# ────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}── Ports${NC}"
# ────────────────────────────────────────────────────────────

for port_info in "8001:Backend" "6333:Qdrant" "5173:Frontend" "11434:Ollama"; do
    port="${port_info%%:*}"
    label="${port_info##*:}"
    if check_port_available "$port"; then
        pass_check "Port $port ($label): available"
    else
        warn_check "Port $port ($label): already in use" \
            "Another process is using this port. Check: lsof -i :$port"
    fi
done

# ────────────────────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════════════════════"
TOTAL=$((PASSED + WARNED + FAILED))

if [ "$FAILED" -eq 0 ] && [ "$WARNED" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}  ✅  PASS — All $TOTAL preflight checks passed${NC}"
    echo ""
    echo "  Ready to install. Run:"
    echo "    ./deploy/install.sh"
elif [ "$FAILED" -eq 0 ]; then
    echo -e "${YELLOW}${BOLD}  ⚠   PASS WITH WARNINGS — $PASSED passed, $WARNED warnings${NC}"
    echo ""
    echo "  Installation can proceed but some features may be limited."
    echo "  Review warnings above. Run:"
    echo "    ./deploy/install.sh"
else
    echo -e "${RED}${BOLD}  ✗   FAIL — $PASSED passed, $WARNED warnings, $FAILED FAILED${NC}"
    echo ""
    echo "  Fix the failures above before installing."
    echo "  After fixing, re-run:"
    echo "    ./deploy/preflight.sh"
fi
echo "════════════════════════════════════════════════════════"

[ "$FAILED" -gt 0 ] && exit 1 || exit 0
