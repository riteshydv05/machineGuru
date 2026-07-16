#!/usr/bin/env bash
# ============================================================
# MachineGuru — Production Install Script
# ============================================================
# Target: NVIDIA Jetson Orin / Ubuntu ARM64 / Ubuntu x86_64
#         Jetson Cloud Lab / macOS (development)
#
# Usage:  ./deploy/install.sh [--skip-models] [--skip-frontend]
#
# This script auto-detects the environment and configures itself:
#   - LOCAL MODE:  Full install (apt + venv + models)
#   - CLOUD MODE:  Skip apt if unavailable, fallback pip --user
#
# What this script does:
#   1.  Detects environment (Jetson Native/Cloud, Ubuntu, macOS)
#   2.  Validates prerequisites
#   3.  Installs system dependencies (if apt available)
#   4.  Installs Node.js 20 LTS (if missing and internet available)
#   5.  Detects/installs Ollama
#   6.  Sets up Python environment (venv or --user fallback)
#   7.  Installs Python dependencies (skips existing packages)
#   8.  Installs frontend and builds for production
#   9.  Creates storage directory structure
#  10.  Auto-configures .env (DEVICE, OLLAMA_BASE_URL)
#  11.  Pulls required AI models (smart — skips existing)
#  12.  Prints final status and next steps
# ============================================================

# Do NOT use set -e — we handle errors explicitly per-command
# so that Cloud Lab deployments can gracefully skip failing steps
set -uo pipefail

# ── Source shared library ────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=deploy_lib.sh
source "$SCRIPT_DIR/deploy_lib.sh"

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

# ── Setup logging ────────────────────────────────────────────
setup_logging "install"

echo ""
echo "============================================================"
echo "  MachineGuru — Install Script  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# ────────────────────────────────────────────────────────────
# STEP 1: Detect Environment
# ────────────────────────────────────────────────────────────
step "Detecting environment"

DEPLOY_ENV="$(detect_environment)"
ARCH="$(uname -m)"
OS="$(uname -s)"

info "Environment: $DEPLOY_ENV"
info "OS: $OS | Architecture: $ARCH"

# Determine capabilities
HAS_INTERNET=false
HAS_APT=false
HAS_VENV=true  # assume true until proven otherwise

if check_internet; then
    HAS_INTERNET=true
    ok "Internet connectivity available"
else
    warn "No internet connectivity detected"
    warn "Will skip steps requiring network access"
fi

if [ "$OS" = "Linux" ] && command -v apt-get &>/dev/null; then
    if check_apt_available; then
        HAS_APT=true
        ok "apt repositories reachable"
    else
        warn "apt repositories unreachable — skipping apt installs"
        warn "Existing system packages will be used"
    fi
elif [ "$OS" = "Darwin" ]; then
    info "macOS detected — skipping apt (use Homebrew if needed)"
fi

case "$DEPLOY_ENV" in
    JETSON_CLOUD)
        info "Cloud Lab detected — using resilient installation mode"
        info "  → apt will be skipped if unavailable"
        info "  → venv will fallback to pip --user if needed"
        info "  → Existing PyTorch/CUDA will be reused"
        ;;
    JETSON_NATIVE)
        ok "Jetson native deployment — full installation mode"
        ;;
    UBUNTU_ARM64|UBUNTU_X86)
        ok "Ubuntu $ARCH — standard installation mode"
        ;;
    MACOS)
        warn "macOS — development mode (some features may differ)"
        ;;
esac

# ────────────────────────────────────────────────────────────
# STEP 2: Validate Prerequisites
# ────────────────────────────────────────────────────────────
step "Validating prerequisites"

# tzdata check — must happen before any Python imports that use pandas/pytz
if ! check_tzdata; then
    echo ""
    fail "CRITICAL: Timezone data is missing!"
    echo ""
    echo -e "  ${RED}The system is missing /usr/share/zoneinfo/tzdata.zi${NC}"
    echo -e "  ${RED}This will cause 'import pandas' to fail at runtime.${NC}"
    echo ""
    echo "  Possible fixes:"
    echo "    1. Install tzdata:  sudo apt install tzdata"
    echo "    2. If on Cloud Lab: Contact your administrator"
    echo "    3. Set TZ env var:  export TZ=UTC"
    echo ""

    if [ "$DEPLOY_ENV" = "JETSON_CLOUD" ]; then
        warn "Continuing installation — but backend may fail to start"
        warn "Set USE_OLLAMA_EMBEDDINGS=true in .env to avoid pandas dependency"
    else
        if [ "$HAS_APT" = true ]; then
            info "Attempting to install tzdata..."
            if sudo apt-get install -y tzdata 2>/dev/null; then
                ok "tzdata installed"
            else
                warn "Could not install tzdata — continuing anyway"
            fi
        fi
    fi
fi

ok "Prerequisites validated"

# ────────────────────────────────────────────────────────────
# STEP 3: System Dependencies (apt)
# ────────────────────────────────────────────────────────────
step "System dependencies"

if [ "$HAS_APT" = true ]; then
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
        if sudo apt-get install -y --no-install-recommends "${MISSING[@]}" 2>/dev/null; then
            ok "System packages installed"
        else
            warn "Some packages could not be installed — continuing with what's available"
            # Try installing one by one to get as many as possible
            for pkg in "${MISSING[@]}"; do
                sudo apt-get install -y --no-install-recommends "$pkg" 2>/dev/null || \
                    debug "Could not install: $pkg"
            done
        fi
    else
        ok "All system packages already installed"
    fi
else
    if [ "$OS" = "Linux" ]; then
        warn "Skipping apt install (repositories unavailable)"
        info "Checking for critical commands..."
        for cmd in curl git python3; do
            if command -v "$cmd" &>/dev/null; then
                ok "$cmd found"
            else
                fail "$cmd NOT found — installation may fail"
            fi
        done
    else
        info "Non-Linux OS — skipping apt install"
    fi
fi

# ────────────────────────────────────────────────────────────
# STEP 4: Python Version Check
# ────────────────────────────────────────────────────────────
step "Checking Python version"

PYTHON_BIN="$(find_python 2>/dev/null || echo "")"

if [ -z "$PYTHON_BIN" ]; then
    fail "Python 3.10+ is required. Please install it first."
    echo "  Install: sudo apt install python3"
    exit 1
fi

PY_VER=$("$PYTHON_BIN" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
ok "Found $PYTHON_BIN ($PY_VER)"

# ────────────────────────────────────────────────────────────
# STEP 5: Node.js 20+
# ────────────────────────────────────────────────────────────
step "Checking Node.js"

install_node=false
if command -v node &>/dev/null; then
    NODE_VERSION=$(node -v | sed 's/v//')
    NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
    if [ "$NODE_MAJOR" -lt 20 ] 2>/dev/null; then
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
    if [ "$HAS_INTERNET" = true ]; then
        if [ "$OS" = "Linux" ] && [ "$HAS_APT" = true ]; then
            if curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - 2>/dev/null; then
                sudo apt-get install -y nodejs 2>/dev/null && \
                    ok "Node.js $(node -v) installed" || \
                    warn "Node.js installation failed — frontend build will be skipped"
            else
                warn "Could not add NodeSource repository — try manual install"
            fi
        elif [ "$OS" = "Darwin" ]; then
            warn "Install Node.js 20 via Homebrew: brew install node@20"
        else
            warn "Cannot install Node.js — apt unavailable"
            warn "Install manually: https://nodejs.org/en/download/"
        fi
    else
        warn "Cannot install Node.js — no internet connectivity"
    fi
fi

# ────────────────────────────────────────────────────────────
# STEP 6: Ollama
# ────────────────────────────────────────────────────────────
step "Checking Ollama"

OLLAMA_STATUS="$(detect_ollama)"

case "$OLLAMA_STATUS" in
    INSTALLED_RUNNING)
        OLLAMA_VER=$(ollama --version 2>/dev/null | head -1 || echo "unknown")
        OLLAMA_URL="$(detect_ollama_url)"
        ok "Ollama installed and running: $OLLAMA_VER"
        ok "Ollama reachable at: $OLLAMA_URL"
        ;;
    INSTALLED_STOPPED)
        warn "Ollama is installed but not running"
        if try_start_ollama; then
            OLLAMA_URL="$(detect_ollama_url)"
            ok "Ollama started successfully at $OLLAMA_URL"
        else
            warn "Could not start Ollama automatically"
            info "Start manually: ollama serve"
            info "Or: sudo systemctl start ollama"
        fi
        ;;
    MISSING)
        warn "Ollama is not installed"
        if [ "$HAS_INTERNET" = true ]; then
            info "Installing Ollama..."
            if [ "$ARCH" = "aarch64" ]; then
                info "Note: Native ARM64 install required for Jetson CUDA support"
                info "Docker-based Ollama does NOT support Jetson CUDA"
            fi
            if curl -fsSL https://ollama.com/install.sh | sh 2>/dev/null; then
                ok "Ollama installed"
                if try_start_ollama; then
                    OLLAMA_URL="$(detect_ollama_url)"
                    ok "Ollama started at $OLLAMA_URL"
                fi
            else
                warn "Ollama installation failed"
                echo ""
                echo "  Install Ollama manually:"
                echo "    curl -fsSL https://ollama.com/install.sh | sh"
                echo ""
                echo "  Then start it:"
                echo "    ollama serve"
                echo ""
            fi
        else
            echo ""
            echo -e "  ${YELLOW}Ollama must be installed manually:${NC}"
            echo ""
            echo "    1. Download from: https://ollama.com/download"
            echo "    2. Install the binary"
            echo "    3. Start with: ollama serve"
            echo "    4. Pull a model: ollama pull llama3.2:1b"
            echo ""
        fi
        ;;
esac

# ────────────────────────────────────────────────────────────
# STEP 7: Python Environment + Dependencies
# ────────────────────────────────────────────────────────────
step "Setting up Python environment"

VENV_DIR="$PROJECT_ROOT/backend/.venv"
activate_pip_env "$PYTHON_BIN" "$VENV_DIR"

info "Pip install mode: $PIP_MODE"

# Upgrade pip
pip install --upgrade pip --quiet $PIP_FLAGS 2>/dev/null || true

step "Installing Python dependencies"

# ── Check for existing PyTorch (especially on Jetson) ────────
TORCH_PREINSTALLED=false
if "$PYTHON_BIN" -c "import torch; print(torch.__version__)" &>/dev/null 2>&1; then
    TORCH_VER=$("$PYTHON_BIN" -c "import torch; print(torch.__version__)" 2>/dev/null)
    TORCH_CUDA=$("$PYTHON_BIN" -c "import torch; print(torch.cuda.is_available())" 2>/dev/null)
    ok "PyTorch $TORCH_VER already installed (CUDA: $TORCH_CUDA)"
    TORCH_PREINSTALLED=true
fi

# ── Smart dependency installation ────────────────────────────
REQ_FILE="$PROJECT_ROOT/backend/requirements.txt"

if [ "$TORCH_PREINSTALLED" = true ] && [ "$ARCH" = "aarch64" ]; then
    # On ARM64 with pre-installed torch, skip torch from requirements
    info "ARM64 with existing PyTorch — installing requirements without torch"
    grep -v "^torch" "$REQ_FILE" > /tmp/requirements_no_torch.txt
    pip install -r /tmp/requirements_no_torch.txt --quiet $PIP_FLAGS 2>/dev/null && \
        ok "Python dependencies installed (torch preserved)" || \
        warn "Some Python packages may have failed to install"
    rm -f /tmp/requirements_no_torch.txt
elif [ "$DEPLOY_ENV" = "JETSON_CLOUD" ] && [ "$TORCH_PREINSTALLED" = true ]; then
    # Cloud Lab with pre-installed torch
    info "Cloud Lab with existing PyTorch — installing only missing packages"
    grep -v "^torch" "$REQ_FILE" > /tmp/requirements_no_torch.txt
    pip install -r /tmp/requirements_no_torch.txt --quiet $PIP_FLAGS 2>/dev/null && \
        ok "Python dependencies installed" || \
        warn "Some Python packages may have failed to install"
    rm -f /tmp/requirements_no_torch.txt
else
    # Standard install
    pip install -r "$REQ_FILE" --quiet $PIP_FLAGS 2>/dev/null && \
        ok "Python dependencies installed" || \
        warn "Some Python packages may have failed — check logs"
fi

# ── Verify critical imports ──────────────────────────────────
step "Verifying critical Python dependencies"

IMPORT_FAILURES=0
for pkg_check in "fastapi:fastapi" "uvicorn:uvicorn" "pydantic:pydantic" "qdrant_client:qdrant-client" "loguru:loguru"; do
    module="${pkg_check%%:*}"
    name="${pkg_check##*:}"
    if is_python_pkg_installed "$module" "$PYTHON_BIN" 2>/dev/null; then
        ok "$name"
    else
        fail "$name — NOT importable"
        IMPORT_FAILURES=$((IMPORT_FAILURES + 1))
    fi
done

# Check sentence-transformers (may fail on Cloud Lab due to tzdata)
if is_python_pkg_installed "sentence_transformers" "$PYTHON_BIN" 2>/dev/null; then
    ok "sentence-transformers"
else
    warn "sentence-transformers not importable"
    info "This may be due to missing tzdata. Consider setting USE_OLLAMA_EMBEDDINGS=true"
fi

# Check torch
if is_python_pkg_installed "torch" "$PYTHON_BIN" 2>/dev/null; then
    ok "torch"
else
    fail "torch — NOT importable"
    IMPORT_FAILURES=$((IMPORT_FAILURES + 1))
fi

if [ "$IMPORT_FAILURES" -gt 0 ]; then
    warn "$IMPORT_FAILURES critical packages are not importable"
    warn "The backend may not start correctly"
fi

# ────────────────────────────────────────────────────────────
# STEP 8: Frontend
# ────────────────────────────────────────────────────────────
if [ "$SKIP_FRONTEND" = false ]; then
    if command -v node &>/dev/null && command -v npm &>/dev/null; then
        step "Installing frontend dependencies"
        cd "$PROJECT_ROOT/frontend"
        npm install --silent 2>/dev/null && \
            ok "Frontend npm packages installed" || \
            warn "npm install had issues — check logs"

        step "Building frontend for production"
        npm run build 2>/dev/null && \
            ok "Frontend built to frontend/dist/" || \
            warn "Frontend build failed — use dev mode instead"
        cd "$PROJECT_ROOT"
    else
        warn "Skipping frontend build (Node.js/npm not available)"
    fi
else
    warn "Skipping frontend build (--skip-frontend)"
fi

# ────────────────────────────────────────────────────────────
# STEP 9: Storage Directory Structure
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
# STEP 10: Environment File + Auto-Configuration
# ────────────────────────────────────────────────────────────
step "Setting up environment configuration"

if [ ! -f "$PROJECT_ROOT/.env" ]; then
    cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
    ok "Created .env from .env.example"
else
    ok ".env already exists — not overwriting"
    info "Review .env.example for new variables and merge as needed"
fi

# Auto-detect and configure DEVICE
auto_configure_device "$PROJECT_ROOT/.env"

# Auto-detect and configure Ollama URL
auto_configure_ollama_url "$PROJECT_ROOT/.env" || \
    info "Ollama URL auto-detection skipped (Ollama not reachable)"

# ────────────────────────────────────────────────────────────
# STEP 11: Script Permissions
# ────────────────────────────────────────────────────────────
step "Setting script permissions"

chmod +x "$PROJECT_ROOT/start.sh" 2>/dev/null || true
chmod +x "$PROJECT_ROOT/stop.sh" 2>/dev/null || true
chmod +x "$PROJECT_ROOT/restart.sh" 2>/dev/null || true
chmod +x "$PROJECT_ROOT/deploy/"*.sh 2>/dev/null || true
chmod +x "$PROJECT_ROOT/scripts/"*.sh 2>/dev/null || true

ok "Scripts are executable"

# ────────────────────────────────────────────────────────────
# STEP 12: Pull Ollama Models (Smart)
# ────────────────────────────────────────────────────────────
if [ "$SKIP_MODELS" = false ]; then
    step "Pulling AI models"

    # Read model from .env
    LLM_MODEL_NAME=$(env_get "LLM_MODEL" "llama3.2:1b")

    OLLAMA_STATUS="$(detect_ollama)"
    if [ "$OLLAMA_STATUS" = "INSTALLED_RUNNING" ]; then
        smart_model_pull "$LLM_MODEL_NAME" || true
    elif [ "$OLLAMA_STATUS" = "INSTALLED_STOPPED" ]; then
        warn "Ollama not running — cannot pull models"
        info "Start Ollama and pull manually: ollama pull $LLM_MODEL_NAME"
    else
        warn "Ollama not installed — cannot pull models"
        info "Install Ollama first, then: ollama pull $LLM_MODEL_NAME"
    fi
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
echo "  Environment: $DEPLOY_ENV"
echo "  Python:      $PIP_MODE mode"

detect_cuda
if [ "$CUDA_AVAILABLE" = true ]; then
    echo -e "  CUDA:        ${GREEN}$CUDA_VERSION${NC}"
else
    echo "  CUDA:        not available (CPU mode)"
fi

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

if [ "$DEPLOY_ENV" = "JETSON_NATIVE" ] || [ "$DEPLOY_ENV" = "UBUNTU_ARM64" ]; then
    echo "  4. For NVIDIA GPU acceleration on Jetson:"
    echo "     ./deploy/jetson_setup.sh"
    echo ""
fi

echo "  Log saved to: $LOG_FILE"
echo "============================================================"
