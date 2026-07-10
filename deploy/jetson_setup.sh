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
# ============================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

step()  { echo -e "\n${BOLD}${BLUE}▶ $1${NC}"; }
ok()    { echo -e "  ${GREEN}✓ $1${NC}"; }
warn()  { echo -e "  ${YELLOW}⚠ $1${NC}"; }
fail()  { echo -e "  ${RED}✗ $1${NC}"; exit 1; }
info()  { echo -e "  ${CYAN}ℹ $1${NC}"; }

mkdir -p "$PROJECT_ROOT/logs"
exec > >(tee -a "$PROJECT_ROOT/logs/deployment.log") 2>&1

echo ""
echo "============================================================"
echo "  MachineGuru — Jetson Setup  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# ── Architecture check ────────────────────────────────────────
step "Validating Jetson hardware"

ARCH="$(uname -m)"
if [ "$ARCH" != "aarch64" ]; then
    fail "This script is for ARM64 (aarch64) only. Detected: $ARCH"
fi
ok "ARM64 architecture confirmed"

# Check for Jetson-specific file
if [ -f /etc/nv_tegra_release ] || [ -f /proc/device-tree/model ]; then
    MODEL=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || echo "NVIDIA Jetson")
    ok "Jetson board detected: $MODEL"
else
    warn "Could not verify Jetson board — continuing anyway"
fi

# ── JetPack version detection ─────────────────────────────────
step "Detecting JetPack version"

if [ -f /etc/nv_tegra_release ]; then
    JETPACK_INFO=$(cat /etc/nv_tegra_release)
    info "JetPack: $JETPACK_INFO"
elif dpkg -l nvidia-jetpack &>/dev/null 2>&1; then
    JETPACK_VER=$(dpkg -l nvidia-jetpack | grep nvidia-jetpack | awk '{print $3}')
    info "JetPack version: $JETPACK_VER"
fi

# Detect CUDA version
if command -v nvcc &>/dev/null; then
    CUDA_VERSION=$(nvcc --version | grep "release" | sed 's/.*release \([0-9\.]*\).*/\1/')
    ok "CUDA $CUDA_VERSION detected"
elif [ -d /usr/local/cuda ]; then
    ok "CUDA installation found at /usr/local/cuda"
else
    warn "CUDA not found — make sure JetPack is fully installed"
    warn "Run: sudo apt-get install nvidia-jetpack"
fi

# ── System updates ────────────────────────────────────────────
step "Updating system packages"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    python3-pip \
    python3-dev \
    libopenblas-dev \
    liblapack-dev \
    gfortran \
    pkg-config \
    cmake \
    ninja-build
ok "System packages updated"

# ── NVIDIA Container Toolkit ──────────────────────────────────
step "Installing NVIDIA Container Toolkit (for Docker GPU support)"

if command -v nvidia-ctk &>/dev/null; then
    ok "NVIDIA Container Toolkit already installed"
else
    info "Adding NVIDIA Container Toolkit repository..."
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

    sudo apt-get update -qq
    sudo apt-get install -y nvidia-container-toolkit
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker 2>/dev/null || true
    ok "NVIDIA Container Toolkit installed"
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

SWAP_TOTAL=$(free -g | grep Swap | awk '{print $2}')
if [ "$SWAP_TOTAL" -lt 4 ]; then
    info "Swap is ${SWAP_TOTAL}GB — increasing to 8GB for large model loading"

    if [ ! -f /swapfile ] || [ "$(stat -c%s /swapfile 2>/dev/null || echo 0)" -lt $((8 * 1024 * 1024 * 1024)) ]; then
        sudo swapoff -a 2>/dev/null || true
        sudo rm -f /swapfile
        sudo fallocate -l 8G /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile

        # Persist across reboots
        if ! grep -q '/swapfile' /etc/fstab; then
            echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
        fi
        ok "8GB swap created and enabled"
    else
        ok "Swap already configured"
    fi
else
    ok "Swap is ${SWAP_TOTAL}GB — sufficient"
fi

# ── PyTorch for Jetson ────────────────────────────────────────
step "Installing PyTorch for Jetson (CUDA-enabled)"

VENV_DIR="$PROJECT_ROOT/backend/.venv"
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"

# Check if already installed
if python3 -c "import torch; assert torch.cuda.is_available()" &>/dev/null 2>&1; then
    TORCH_VER=$(python3 -c "import torch; print(torch.__version__)")
    ok "PyTorch $TORCH_VER with CUDA already installed"
else
    info "Installing PyTorch for Jetson from NVIDIA wheel index..."
    info "This may take several minutes depending on your connection speed."

    # NVIDIA provides JetPack-specific torch wheels
    # See: https://forums.developer.nvidia.com/t/pytorch-for-jetson/72048
    # JetPack 6 (Ubuntu 22.04): torch 2.x wheels
    # JetPack 5 (Ubuntu 20.04): torch 2.x wheels

    pip install --upgrade pip

    # Try NVIDIA's Jetson PyPI index first
    TORCH_INSTALLED=false
    if pip install torch torchvision \
        --index-url https://pypi.jetson-ai-lab.dev/jp6/cu126 \
        --extra-index-url https://pypi.org/simple \
        --quiet 2>/dev/null; then
        TORCH_INSTALLED=true
        ok "PyTorch installed from NVIDIA Jetson index (JP6/CUDA 12.6)"
    elif pip install torch torchvision \
        --index-url https://pypi.jetson-ai-lab.dev/jp6/cu124 \
        --extra-index-url https://pypi.org/simple \
        --quiet 2>/dev/null; then
        TORCH_INSTALLED=true
        ok "PyTorch installed from NVIDIA Jetson index (JP6/CUDA 12.4)"
    fi

    if [ "$TORCH_INSTALLED" = false ]; then
        warn "Could not install from NVIDIA index — falling back to CPU-only PyTorch"
        warn "For GPU support, install PyTorch manually:"
        warn "  See: https://forums.developer.nvidia.com/t/pytorch-for-jetson/72048"
        pip install torch --quiet
    fi

    # Verify
    if python3 -c "import torch; print(f'PyTorch {torch.__version__}, CUDA available: {torch.cuda.is_available()}')" 2>/dev/null; then
        ok "PyTorch installation verified"
    else
        warn "PyTorch installed but could not verify GPU support"
    fi
fi

# ── Environment file update ───────────────────────────────────
step "Updating .env for Jetson GPU"

if [ -f "$PROJECT_ROOT/.env" ]; then
    # Check if CUDA is actually available
    if python3 -c "import torch; exit(0 if torch.cuda.is_available() else 1)" &>/dev/null 2>&1; then
        sed -i 's/^DEVICE=cpu/DEVICE=cuda/' "$PROJECT_ROOT/.env" || true
        sed -i 's/^USE_FP16=false/USE_FP16=true/' "$PROJECT_ROOT/.env" || true
        sed -i 's/^USE_FLASH_ATTENTION=false/USE_FLASH_ATTENTION=true/' "$PROJECT_ROOT/.env" || true
        ok "Updated .env: DEVICE=cuda, USE_FP16=true, USE_FLASH_ATTENTION=true"
    else
        warn "CUDA not available in PyTorch — .env DEVICE left as cpu"
    fi
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
