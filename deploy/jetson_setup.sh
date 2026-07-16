#!/usr/bin/env bash
# ============================================================
# MachineGuru — NVIDIA Jetson Orin Setup Script
# ============================================================
# Run this script ONCE on a fresh Jetson before install.sh.
# It installs JetPack-compatible PyTorch and CUDA tools.
#
# Usage: ./deploy/jetson_setup.sh
#
# Requirements:
#   - NVIDIA Jetson Orin (any variant: Nano, NX, AGX)
#   - JetPack 5.x or 6.x installed (Ubuntu 20.04 / 22.04)
#   - Internet connection for initial download
#   - Run as non-root user with sudo access
#
# Auto-detects:
#   - Cloud Lab vs native environment
#   - apt availability
#   - venv availability (falls back to pip --user)
#   - Existing PyTorch installations
# ============================================================

# Do NOT use set -e — handle errors explicitly for Cloud Lab resilience
set -uo pipefail

# ── Source shared library ────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=deploy_lib.sh
source "$SCRIPT_DIR/deploy_lib.sh"

# ── Setup logging ────────────────────────────────────────────
setup_logging "jetson_setup"

echo ""
echo "============================================================"
echo "  MachineGuru — Jetson Setup  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# ── Architecture check ────────────────────────────────────────
step "Validating Jetson hardware"

ARCH="$(uname -m)"
if [ "$ARCH" != "aarch64" ]; then
    fail "This script is for ARM64 (aarch64) only. Detected: $ARCH"
    exit 1
fi
ok "ARM64 architecture confirmed"

# Check for Jetson-specific file
if [ -f /etc/nv_tegra_release ] || [ -f /proc/device-tree/model ]; then
    MODEL=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || echo "NVIDIA Jetson")
    ok "Jetson board detected: $MODEL"
else
    warn "Could not verify Jetson board — continuing anyway"
fi

# ── Environment detection ─────────────────────────────────────
DEPLOY_ENV="$(detect_environment)"
info "Deployment environment: $DEPLOY_ENV"

# ── JetPack version detection ─────────────────────────────────
step "Detecting JetPack version"

if [ -f /etc/nv_tegra_release ]; then
    JETPACK_INFO=$(cat /etc/nv_tegra_release)
    info "JetPack: $JETPACK_INFO"
elif dpkg -l nvidia-jetpack &>/dev/null 2>&1; then
    JETPACK_VER=$(dpkg -l nvidia-jetpack | grep nvidia-jetpack | awk '{print $3}')
    info "JetPack version: $JETPACK_VER"
else
    warn "Could not detect JetPack version"
fi

# Detect CUDA version
detect_cuda
if [ "$CUDA_AVAILABLE" = true ]; then
    ok "CUDA $CUDA_VERSION detected"
    [ -n "$GPU_NAME" ] && info "GPU: $GPU_NAME"
elif [ -d /usr/local/cuda ]; then
    ok "CUDA installation found at /usr/local/cuda"
else
    warn "CUDA not found — make sure JetPack is fully installed"
    warn "Run: sudo apt-get install nvidia-jetpack"
fi

# ── Internet check ────────────────────────────────────────────
step "Checking connectivity"

HAS_INTERNET=false
if check_internet; then
    HAS_INTERNET=true
    ok "Internet connectivity available"
else
    warn "No internet connectivity — some steps will be skipped"
fi

# ── System updates ────────────────────────────────────────────
step "System packages"

if check_apt_available; then
    info "Installing build dependencies..."
    if sudo apt-get install -y --no-install-recommends \
        python3-pip \
        python3-dev \
        libopenblas-dev \
        liblapack-dev \
        gfortran \
        pkg-config \
        cmake \
        ninja-build 2>/dev/null; then
        ok "System packages installed"
    else
        warn "Some packages could not be installed — continuing with existing"
    fi
else
    warn "apt repositories unreachable — skipping system package install"
    info "Checking for critical build tools..."
    for cmd in gcc g++ cmake python3 pip3; do
        if command -v "$cmd" &>/dev/null; then
            ok "$cmd found"
        else
            warn "$cmd not found — some builds may fail"
        fi
    done
fi

# ── NVIDIA Container Toolkit ──────────────────────────────────
step "NVIDIA Container Toolkit"

if command -v nvidia-ctk &>/dev/null; then
    ok "NVIDIA Container Toolkit already installed"
elif [ "$HAS_INTERNET" = true ] && check_apt_available; then
    info "Adding NVIDIA Container Toolkit repository..."
    if curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null; then

        curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

        sudo apt-get update -qq 2>/dev/null || true
        if sudo apt-get install -y nvidia-container-toolkit 2>/dev/null; then
            sudo nvidia-ctk runtime configure --runtime=docker 2>/dev/null || true
            sudo systemctl restart docker 2>/dev/null || true
            ok "NVIDIA Container Toolkit installed"
        else
            warn "Could not install NVIDIA Container Toolkit"
        fi
    else
        warn "Could not add NVIDIA Container Toolkit repository"
    fi
else
    warn "Skipping NVIDIA Container Toolkit (no internet or apt unavailable)"
fi

# ── Jetson Power Mode ─────────────────────────────────────────
step "Configuring Jetson power mode"

if command -v nvpmodel &>/dev/null; then
    CURRENT_MODE=$(nvpmodel -q 2>/dev/null | grep "NV Power Mode" | head -1 || echo "unknown")
    info "Current power mode: $CURRENT_MODE"
    info "Setting maximum performance mode (MAXN)..."
    sudo nvpmodel -m 0 2>/dev/null && ok "Set to MAXN (maximum performance)" || warn "Could not set power mode — set manually: sudo nvpmodel -m 0"
    sudo jetson_clocks 2>/dev/null && ok "Jetson clocks maximized" || warn "jetson_clocks not available"
else
    warn "nvpmodel not found — JetPack may not be fully installed"
fi

# ── Swap configuration ────────────────────────────────────────
step "Checking swap configuration"

SWAP_TOTAL=$(free -g 2>/dev/null | grep Swap | awk '{print $2}' || echo 0)
if [ "${SWAP_TOTAL:-0}" -lt 4 ] 2>/dev/null; then
    info "Swap is ${SWAP_TOTAL}GB — increasing to 8GB for large model loading"

    if [ ! -f /swapfile ] || [ "$(stat -c%s /swapfile 2>/dev/null || echo 0)" -lt $((8 * 1024 * 1024 * 1024)) ]; then
        sudo swapoff -a 2>/dev/null || true
        sudo rm -f /swapfile
        if sudo fallocate -l 8G /swapfile 2>/dev/null; then
            sudo chmod 600 /swapfile
            sudo mkswap /swapfile
            sudo swapon /swapfile

            # Persist across reboots
            if ! grep -q '/swapfile' /etc/fstab 2>/dev/null; then
                echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
            fi
            ok "8GB swap created and enabled"
        else
            warn "Could not create swap file — model loading may be constrained"
        fi
    else
        ok "Swap already configured"
    fi
else
    ok "Swap is ${SWAP_TOTAL}GB — sufficient"
fi

# ── PyTorch for Jetson ────────────────────────────────────────
step "Installing PyTorch for Jetson (CUDA-enabled)"

VENV_DIR="$PROJECT_ROOT/backend/.venv"
activate_pip_env python3 "$VENV_DIR"

# Check if already installed
if python3 -c "import torch; assert torch.cuda.is_available()" &>/dev/null 2>&1; then
    TORCH_VER=$(python3 -c "import torch; print(torch.__version__)")
    ok "PyTorch $TORCH_VER with CUDA already installed — skipping"
else
    if [ "$HAS_INTERNET" = true ]; then
        info "Installing PyTorch for Jetson from NVIDIA wheel index..."
        info "This may take several minutes depending on your connection speed."

        pip install --upgrade pip $PIP_FLAGS 2>/dev/null || true

        # Try NVIDIA's Jetson PyPI index first
        TORCH_INSTALLED=false
        if pip install torch torchvision \
            --index-url https://pypi.jetson-ai-lab.dev/jp6/cu126 \
            --extra-index-url https://pypi.org/simple \
            --quiet $PIP_FLAGS 2>/dev/null; then
            TORCH_INSTALLED=true
            ok "PyTorch installed from NVIDIA Jetson index (JP6/CUDA 12.6)"
        elif pip install torch torchvision \
            --index-url https://pypi.jetson-ai-lab.dev/jp6/cu124 \
            --extra-index-url https://pypi.org/simple \
            --quiet $PIP_FLAGS 2>/dev/null; then
            TORCH_INSTALLED=true
            ok "PyTorch installed from NVIDIA Jetson index (JP6/CUDA 12.4)"
        fi

        if [ "$TORCH_INSTALLED" = false ]; then
            warn "Could not install from NVIDIA index — falling back to CPU-only PyTorch"
            warn "For GPU support, install PyTorch manually:"
            warn "  See: https://forums.developer.nvidia.com/t/pytorch-for-jetson/72048"
            pip install torch --quiet $PIP_FLAGS 2>/dev/null || warn "PyTorch install failed"
        fi

        # Verify
        if python3 -c "import torch; print(f'PyTorch {torch.__version__}, CUDA available: {torch.cuda.is_available()}')" 2>/dev/null; then
            ok "PyTorch installation verified"
        else
            warn "PyTorch installed but could not verify GPU support"
        fi
    else
        warn "Cannot install PyTorch — no internet connectivity"
        warn "Install PyTorch manually when internet is available"
    fi
fi

# ── Environment file update ───────────────────────────────────
step "Updating .env for Jetson GPU"

if [ -f "$PROJECT_ROOT/.env" ]; then
    auto_configure_device "$PROJECT_ROOT/.env"
else
    info ".env not yet created — will be configured during install.sh"
fi

# ── GPU verification ──────────────────────────────────────────
step "GPU verification"

if command -v tegrastats &>/dev/null; then
    info "tegrastats available — GPU monitoring enabled"
    ok "Jetson GPU tools installed"
fi

if python3 -c "import torch; print(f'  GPU: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"not available\"}')" 2>/dev/null; then
    ok "GPU check complete"
fi

# ── Summary ───────────────────────────────────────────────────
echo ""
echo "============================================================"
echo -e "${GREEN}${BOLD}  ✅  Jetson Setup Complete!${NC}"
echo "============================================================"
echo ""
echo "  Environment: $DEPLOY_ENV"
echo "  Python mode: $PIP_MODE"
echo ""
echo "  Next steps:"
echo "  1. Run the main install script: ./deploy/install.sh"
echo "  2. Start services:              ./start.sh"
echo "  3. Verify GPU in backend:       curl http://localhost:8001/api/v1/stats | python3 -m json.tool"
echo ""
echo "  GPU Status:"
if python3 -c "import torch; avail = torch.cuda.is_available(); print(f'    CUDA available: {avail}'); print(f'    Device: {torch.cuda.get_device_name(0) if avail else \"N/A\"}')" 2>/dev/null; then
    true
fi
echo "============================================================"
