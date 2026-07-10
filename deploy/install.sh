#!/usr/bin/env bash
# ============================================================
# MachineGuru — Production Install Script
# ============================================================
# Target: NVIDIA Jetson Orin / Ubuntu 20.04+ ARM64
# Usage:  ./deploy/install.sh [--skip-models] [--skip-frontend]
#
# What this script does:
#   1. Validates the operating system and architecture
#   2. Installs system dependencies (apt packages)
#   3. Installs Node.js 20 LTS (via NodeSource)
#   4. Installs Ollama natively (native ARM64, supports Jetson GPU)
#   5. Creates Python virtual environment and installs requirements
#   6. Installs frontend npm dependencies and builds for production
#   7. Creates the storage directory structure
#   8. Copies .env.example to .env if not already present
#   9. Pulls required AI models into Ollama
#  10. Prints final status and next steps
#
# After this script completes, start everything with:
#   ./start.sh
# ============================================================
set -euo pipefail

# ── Color codes ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Argument parsing ─────────────────────────────────────────
SKIP_MODELS=false
SKIP_FRONTEND=false
for arg in "$@"; do
    case $arg in
        --skip-models)   SKIP_MODELS=true ;;
        --skip-frontend) SKIP_FRONTEND=true ;;
        --help|-h)
            echo "Usage: $0 [--skip-models] [--skip-frontend]"
            echo "  --skip-models    Do not pull Ollama models (pull manually later)"
            echo "  --skip-frontend  Do not build the frontend"
            exit 0
            ;;
    esac
done

# ── Project root ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# ── Logging helpers ──────────────────────────────────────────
step()  { echo -e "\n${BOLD}${BLUE}▶ $1${NC}"; }
ok()    { echo -e "  ${GREEN}✓ $1${NC}"; }
warn()  { echo -e "  ${YELLOW}⚠ $1${NC}"; }
fail()  { echo -e "  ${RED}✗ $1${NC}"; exit 1; }
info()  { echo -e "  ${CYAN}ℹ $1${NC}"; }

# ── Install log ──────────────────────────────────────────────
mkdir -p "$PROJECT_ROOT/logs"
INSTALL_LOG="$PROJECT_ROOT/logs/deployment.log"
exec > >(tee -a "$INSTALL_LOG") 2>&1
echo ""
echo "============================================================"
echo "  MachineGuru — Install Script  $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Log: $INSTALL_LOG"
echo "============================================================"

# ────────────────────────────────────────────────────────────
# STEP 1: Validate OS + Architecture
# ────────────────────────────────────────────────────────────
step "Validating system"

OS="$(uname -s)"
ARCH="$(uname -m)"

if [ "$OS" != "Linux" ]; then
    warn "This script is designed for Ubuntu Linux (detected: $OS)"
    warn "Continuing anyway — some steps may not apply"
fi

info "OS: $OS | Architecture: $ARCH"

if [ "$ARCH" = "aarch64" ]; then
    ok "ARM64 (aarch64) detected — correct for Jetson Orin"
elif [ "$ARCH" = "x86_64" ]; then
    warn "x86_64 detected — for development only, NOT for Jetson deployment"
else
    warn "Unknown architecture: $ARCH"
fi

# Check Ubuntu version
if command -v lsb_release &>/dev/null; then
    UBUNTU_VERSION="$(lsb_release -rs)"
    info "Ubuntu version: $UBUNTU_VERSION"
fi

# ────────────────────────────────────────────────────────────
# STEP 2: System Dependencies
# ────────────────────────────────────────────────────────────
step "Installing system dependencies"

sudo apt-get update -qq

REQUIRED_PKGS=(
    curl
    wget
    git
    build-essential
    python3
    python3-pip
    python3-venv
    python3-dev
    tesseract-ocr
    tesseract-ocr-eng
    libgl1
    libglib2.0-0
    libsm6
    libxrender1
    libxext6
    lsof
    fuser
    net-tools
    jq
)

MISSING=()
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -l "$pkg" &>/dev/null 2>&1; then
        MISSING+=("$pkg")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    info "Installing: ${MISSING[*]}"
    sudo apt-get install -y --no-install-recommends "${MISSING[@]}"
    ok "System packages installed"
else
    ok "All system packages already installed"
fi

# ────────────────────────────────────────────────────────────
# STEP 3: Python version check
# ────────────────────────────────────────────────────────────
step "Checking Python version"

PYTHON_BIN=""
for candidate in python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" &>/dev/null; then
        VERSION=$("$candidate" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        MAJOR=$(echo "$VERSION" | cut -d. -f1)
        MINOR=$(echo "$VERSION" | cut -d. -f2)
        if [ "$MAJOR" -ge 3 ] && [ "$MINOR" -ge 10 ]; then
            PYTHON_BIN="$candidate"
            ok "Found $candidate ($VERSION)"
            break
        fi
    fi
done

if [ -z "$PYTHON_BIN" ]; then
    fail "Python 3.10+ is required. Please install it first."
fi

# ────────────────────────────────────────────────────────────
# STEP 4: Node.js 20+
# ────────────────────────────────────────────────────────────
step "Checking Node.js"

install_node=false
if command -v node &>/dev/null; then
    NODE_VERSION=$(node -v | sed 's/v//')
    NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
    if [ "$NODE_MAJOR" -lt 20 ]; then
        warn "Node.js $NODE_VERSION found but v20+ is required — upgrading"
        install_node=true
    else
        ok "Node.js $NODE_VERSION found"
    fi
else
    info "Node.js not found — installing Node.js 20 LTS"
    install_node=true
fi

if [ "$install_node" = true ]; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
    ok "Node.js $(node -v) installed"
fi

# ────────────────────────────────────────────────────────────
# STEP 5: Ollama
# ────────────────────────────────────────────────────────────
step "Checking Ollama"

if command -v ollama &>/dev/null; then
    OLLAMA_VERSION=$(ollama --version 2>/dev/null | head -1 || echo "unknown")
    ok "Ollama already installed: $OLLAMA_VERSION"
else
    info "Installing Ollama (native ARM64 with Jetson CUDA support)..."
    info "Note: Docker-based Ollama does NOT support Jetson CUDA. Native install is required."
    curl -fsSL https://ollama.com/install.sh | sh
    ok "Ollama installed"
fi

# Start Ollama if not running
if ! curl -sf http://localhost:11434 &>/dev/null; then
    info "Starting Ollama service..."
    if command -v systemctl &>/dev/null && systemctl is-enabled ollama &>/dev/null 2>&1; then
        sudo systemctl start ollama
    else
        nohup ollama serve >/dev/null 2>&1 &
        sleep 3
    fi

    for i in $(seq 1 15); do
        if curl -sf http://localhost:11434 &>/dev/null; then
            ok "Ollama is running"
            break
        fi
        if [ "$i" -eq 15 ]; then
            warn "Ollama did not start in time. Start it manually: ollama serve"
        fi
        sleep 1
    done
else
    ok "Ollama is already running"
fi

# ────────────────────────────────────────────────────────────
# STEP 6: Python Virtual Environment + Dependencies
# ────────────────────────────────────────────────────────────
step "Setting up Python virtual environment"

VENV_DIR="$PROJECT_ROOT/backend/.venv"

if [ ! -d "$VENV_DIR" ]; then
    info "Creating virtual environment at $VENV_DIR"
    "$PYTHON_BIN" -m venv "$VENV_DIR"
    ok "Virtual environment created"
else
    ok "Virtual environment already exists"
fi

# Activate venv
source "$VENV_DIR/bin/activate"

# Upgrade pip
pip install --upgrade pip --quiet

step "Installing Python dependencies"

# ── PyTorch ARM64 note ───────────────────────────────────────
# On NVIDIA Jetson (JetPack), PyTorch must be installed from
# the NVIDIA wheel index, not from PyPI. If you are on Jetson,
# run deploy/jetson_setup.sh first, which installs the correct
# PyTorch wheel before this script runs pip install.
# ─────────────────────────────────────────────────────────────
if [ "$ARCH" = "aarch64" ]; then
    # Check if PyTorch is already installed (by jetson_setup.sh)
    if "$PYTHON_BIN" -c "import torch; print(torch.__version__)" &>/dev/null 2>&1; then
        TORCH_VER=$("$PYTHON_BIN" -c "import torch; print(torch.__version__)")
        ok "PyTorch $TORCH_VER already installed (skipping PyPI torch)"
        # Install requirements without torch (already installed)
        grep -v "^torch" "$PROJECT_ROOT/backend/requirements.txt" > /tmp/requirements_no_torch.txt
        pip install -r /tmp/requirements_no_torch.txt --quiet
    else
        warn "PyTorch not found on ARM64. Installing CPU-only from PyPI."
        warn "For Jetson GPU support, run: deploy/jetson_setup.sh"
        pip install -r "$PROJECT_ROOT/backend/requirements.txt" --quiet
    fi
else
    pip install -r "$PROJECT_ROOT/backend/requirements.txt" --quiet
fi

ok "Python dependencies installed"

# ────────────────────────────────────────────────────────────
# STEP 7: Frontend
# ────────────────────────────────────────────────────────────
if [ "$SKIP_FRONTEND" = false ]; then
    step "Installing frontend dependencies"
    cd "$PROJECT_ROOT/frontend"
    npm install --silent
    ok "Frontend npm packages installed"

    step "Building frontend for production"
    npm run build
    ok "Frontend built to frontend/dist/"
    cd "$PROJECT_ROOT"
else
    warn "Skipping frontend build (--skip-frontend)"
fi

# ────────────────────────────────────────────────────────────
# STEP 8: Storage Directory Structure
# ────────────────────────────────────────────────────────────
step "Creating storage directories"

mkdir -p "$PROJECT_ROOT/storage/uploads"
mkdir -p "$PROJECT_ROOT/storage/qdrant"
mkdir -p "$PROJECT_ROOT/storage/cache"
mkdir -p "$PROJECT_ROOT/storage/embeddings"
mkdir -p "$PROJECT_ROOT/storage/history"
mkdir -p "$PROJECT_ROOT/storage/temporary"
mkdir -p "$PROJECT_ROOT/storage/models"
mkdir -p "$PROJECT_ROOT/logs"

# Migrate existing data if found
if [ -d "$PROJECT_ROOT/qdrant_storage" ] && [ "$(ls -A "$PROJECT_ROOT/qdrant_storage" 2>/dev/null)" ]; then
    warn "Found existing data in qdrant_storage/ — migrating to storage/qdrant/"
    cp -rn "$PROJECT_ROOT/qdrant_storage/." "$PROJECT_ROOT/storage/qdrant/" 2>/dev/null || true
    ok "Qdrant data migrated to storage/qdrant/ (original preserved in qdrant_storage/)"
fi

if [ -d "$PROJECT_ROOT/backend/uploads" ] && [ "$(ls -A "$PROJECT_ROOT/backend/uploads" 2>/dev/null)" ]; then
    warn "Found existing uploads in backend/uploads/ — migrating to storage/uploads/"
    cp -rn "$PROJECT_ROOT/backend/uploads/." "$PROJECT_ROOT/storage/uploads/" 2>/dev/null || true
    ok "Uploads migrated to storage/uploads/ (original preserved in backend/uploads/)"
fi

ok "Storage directories ready"

# ────────────────────────────────────────────────────────────
# STEP 9: Environment File
# ────────────────────────────────────────────────────────────
step "Setting up environment configuration"

if [ ! -f "$PROJECT_ROOT/.env" ]; then
    cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
    ok "Created .env from .env.example"
    warn "IMPORTANT: Edit .env before starting services."
    warn "  → Set OLLAMA_BASE_URL, DEVICE, and CORS_ORIGINS for your environment."
else
    ok ".env already exists — not overwriting"
    info "Review .env.example for new variables and merge as needed"
fi

# ────────────────────────────────────────────────────────────
# STEP 10: Make scripts executable
# ────────────────────────────────────────────────────────────
step "Setting script permissions"

chmod +x "$PROJECT_ROOT/start.sh" || true
chmod +x "$PROJECT_ROOT/stop.sh" || true
chmod +x "$PROJECT_ROOT/deploy/"*.sh || true
chmod +x "$PROJECT_ROOT/scripts/"*.sh 2>/dev/null || true

ok "Scripts are executable"

# ────────────────────────────────────────────────────────────
# STEP 11: Pull Ollama Models
# ────────────────────────────────────────────────────────────
if [ "$SKIP_MODELS" = false ]; then
    step "Pulling AI models"

    # Read model from .env
    LLM_MODEL_NAME=$(grep '^LLM_MODEL=' "$PROJECT_ROOT/.env" | cut -d= -f2 | tr -d '"' || echo "llama3.2:1b")
    info "Pulling LLM model: $LLM_MODEL_NAME"
    ollama pull "$LLM_MODEL_NAME" || warn "Could not pull $LLM_MODEL_NAME — pull manually: ollama pull $LLM_MODEL_NAME"

    ok "Models ready"
else
    warn "Skipping model download (--skip-models)"
    info "Pull models manually: ollama pull llama3.2:1b"
fi

# ────────────────────────────────────────────────────────────
# DONE
# ────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo -e "${GREEN}${BOLD}  ✅  MachineGuru Installation Complete!${NC}"
echo "============================================================"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Review and edit .env if needed:"
echo "     nano .env"
echo ""
echo "  2. Start all services:"
echo "     ./start.sh"
echo ""
echo "  3. Verify everything is working:"
echo "     ./deploy/healthcheck.sh"
echo ""
echo "  4. For NVIDIA GPU acceleration on Jetson:"
echo "     ./deploy/jetson_setup.sh"
echo ""
echo "  Log saved to: $INSTALL_LOG"
echo "============================================================"
