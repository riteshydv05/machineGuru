#!/usr/bin/env bash
# ============================================================
# MachineGuru — Deployment Library (sourced, not executed)
# ============================================================
# Shared functions for all deployment scripts.
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/deploy_lib.sh"
#
# Provides:
#   Environment detection, CUDA detection, Ollama probing,
#   apt/venv/internet/tzdata checks, colored output helpers,
#   smart model pulling, and logging setup.
# ============================================================

# Guard against double-sourcing
if [ "${_DEPLOY_LIB_LOADED:-}" = "true" ]; then
    return 0 2>/dev/null || true
fi
_DEPLOY_LIB_LOADED=true

# ── Color codes ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Output helpers ───────────────────────────────────────────
step()  { echo -e "\n${BOLD}${BLUE}▶ $1${NC}"; }
ok()    { echo -e "  ${GREEN}✓ $1${NC}"; }
warn()  { echo -e "  ${YELLOW}⚠ $1${NC}"; }
fail()  { echo -e "  ${RED}✗ $1${NC}"; }
info()  { echo -e "  ${CYAN}ℹ $1${NC}"; }
debug() { [ "${DEPLOY_VERBOSE:-false}" = "true" ] && echo -e "  ${DIM}… $1${NC}"; }

# Fatal error — print message and exit
die() {
    echo -e "\n${RED}${BOLD}FATAL: $1${NC}" >&2
    exit 1
}

# ── Project root detection ───────────────────────────────────
# Works regardless of which script sources this file
_detect_project_root() {
    local script_dir
    # If DEPLOY_LIB_DIR is set by the caller, use it
    if [ -n "${DEPLOY_LIB_DIR:-}" ]; then
        echo "$(dirname "$DEPLOY_LIB_DIR")"
        return
    fi
    # Otherwise try to find project root from common script locations
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)"
    # If we're in deploy/, go one level up
    if [ "$(basename "$script_dir")" = "deploy" ]; then
        echo "$(dirname "$script_dir")"
    elif [ -f "$script_dir/start.sh" ] || [ -f "$script_dir/.env.example" ]; then
        echo "$script_dir"
    else
        # Fallback: look for .env.example going up
        local dir="$script_dir"
        while [ "$dir" != "/" ]; do
            if [ -f "$dir/.env.example" ] || [ -f "$dir/start.sh" ]; then
                echo "$dir"
                return
            fi
            dir="$(dirname "$dir")"
        done
        echo "$script_dir"
    fi
}

PROJECT_ROOT="$(_detect_project_root)"

# ── Logging setup ────────────────────────────────────────────
setup_logging() {
    local log_name="${1:-deployment}"
    mkdir -p "$PROJECT_ROOT/logs"
    LOG_FILE="$PROJECT_ROOT/logs/${log_name}.log"
    exec > >(tee -a "$LOG_FILE") 2>&1
    echo ""
    echo "──────────────────────────────────────────────────"
    echo "  Log started: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  Script: ${BASH_SOURCE[1]:-unknown}"
    echo "  Log file: $LOG_FILE"
    echo "──────────────────────────────────────────────────"
}

# ── Environment Detection ────────────────────────────────────
# Returns one of: JETSON_NATIVE, JETSON_CLOUD, UBUNTU_ARM64,
#                 UBUNTU_X86, MACOS, UNKNOWN
detect_environment() {
    local os arch is_jetson is_cloud

    os="$(uname -s)"
    arch="$(uname -m)"
    is_jetson=false
    is_cloud=false

    # Detect Jetson hardware
    if [ -f /etc/nv_tegra_release ] || [ -f /proc/device-tree/model ]; then
        if grep -qi "jetson\|tegra" /proc/device-tree/model 2>/dev/null || [ -f /etc/nv_tegra_release ]; then
            is_jetson=true
        fi
    fi

    # Detect Cloud Lab environment
    # Cloud Labs typically have: restricted apt, no systemd, container-like env
    if [ "$is_jetson" = true ]; then
        # Check if apt repos are unreachable (strong Cloud Lab indicator)
        if ! check_apt_available 2>/dev/null; then
            is_cloud=true
        fi
        # Also check for container-like environment
        if [ -f /.dockerenv ] || grep -q "docker\|lxc\|kubepods" /proc/1/cgroup 2>/dev/null; then
            is_cloud=true
        fi
    fi

    if [ "$os" = "Darwin" ]; then
        echo "MACOS"
    elif [ "$is_jetson" = true ] && [ "$is_cloud" = true ]; then
        echo "JETSON_CLOUD"
    elif [ "$is_jetson" = true ]; then
        echo "JETSON_NATIVE"
    elif [ "$arch" = "aarch64" ]; then
        echo "UBUNTU_ARM64"
    elif [ "$arch" = "x86_64" ]; then
        echo "UBUNTU_X86"
    else
        echo "UNKNOWN"
    fi
}

# ── CUDA Detection ───────────────────────────────────────────
# Sets CUDA_AVAILABLE (true/false) and CUDA_VERSION
detect_cuda() {
    CUDA_AVAILABLE=false
    CUDA_VERSION=""
    GPU_NAME=""

    # Method 1: nvcc
    if command -v nvcc &>/dev/null; then
        CUDA_VERSION=$(nvcc --version 2>/dev/null | grep "release" | sed 's/.*release \([0-9\.]*\).*/\1/' || echo "")
        if [ -n "$CUDA_VERSION" ]; then
            CUDA_AVAILABLE=true
        fi
    fi

    # Method 2: /usr/local/cuda
    if [ "$CUDA_AVAILABLE" = false ] && [ -d /usr/local/cuda ]; then
        CUDA_VERSION=$(cat /usr/local/cuda/version.txt 2>/dev/null | grep -oP '[0-9]+\.[0-9]+' || echo "")
        if [ -n "$CUDA_VERSION" ]; then
            CUDA_AVAILABLE=true
        fi
    fi

    # Method 3: Python torch
    if [ "$CUDA_AVAILABLE" = false ]; then
        local python_bin
        python_bin="$(find_python)"
        if [ -n "$python_bin" ]; then
            if "$python_bin" -c "import torch; exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null; then
                CUDA_AVAILABLE=true
                CUDA_VERSION=$("$python_bin" -c "import torch; print(torch.version.cuda or '')" 2>/dev/null || echo "")
            fi
        fi
    fi

    # GPU name
    if command -v nvidia-smi &>/dev/null; then
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "")
    elif [ -f /proc/device-tree/model ]; then
        GPU_NAME=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || echo "Jetson GPU")
    fi

    export CUDA_AVAILABLE CUDA_VERSION GPU_NAME
}

# ── Ollama Detection ─────────────────────────────────────────
# Returns: INSTALLED_RUNNING, INSTALLED_STOPPED, MISSING
detect_ollama() {
    if ! command -v ollama &>/dev/null; then
        echo "MISSING"
        return
    fi

    # Ollama binary exists — check if the service is running
    local url
    url="$(detect_ollama_url)"
    if [ -n "$url" ]; then
        echo "INSTALLED_RUNNING"
    else
        echo "INSTALLED_STOPPED"
    fi
}

# ── Ollama URL Detection ─────────────────────────────────────
# Probes endpoints in priority order, returns first reachable URL
detect_ollama_url() {
    local endpoints=(
        "http://localhost:11434"
        "http://127.0.0.1:11434"
        "http://172.17.0.1:11434"
        "http://host.docker.internal:11434"
    )

    for url in "${endpoints[@]}"; do
        if curl -sf --max-time 3 "$url" >/dev/null 2>&1; then
            echo "$url"
            return 0
        fi
    done

    # Nothing reachable
    return 1
}

# ── Try to Start Ollama ──────────────────────────────────────
try_start_ollama() {
    if ! command -v ollama &>/dev/null; then
        return 1
    fi

    # Already running?
    if detect_ollama_url >/dev/null 2>&1; then
        return 0
    fi

    info "Attempting to start Ollama..."

    # Try systemctl first
    if command -v systemctl &>/dev/null && systemctl is-enabled ollama &>/dev/null 2>&1; then
        sudo systemctl start ollama 2>/dev/null || true
    else
        # Manual start
        nohup ollama serve >"$PROJECT_ROOT/logs/ollama.log" 2>&1 &
    fi

    # Wait up to 15 seconds
    local i
    for i in $(seq 1 15); do
        if detect_ollama_url >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done

    return 1
}

# ── Internet Connectivity Check ──────────────────────────────
check_internet() {
    # Test multiple endpoints for robustness
    local endpoints=(
        "https://www.google.com"
        "https://pypi.org"
        "https://registry.npmjs.org"
    )

    for url in "${endpoints[@]}"; do
        if curl -sf --max-time 5 -o /dev/null "$url" 2>/dev/null; then
            return 0
        fi
    done

    return 1
}

# ── APT Availability Check ───────────────────────────────────
check_apt_available() {
    # Quick check: is apt-get even present?
    if ! command -v apt-get &>/dev/null; then
        return 1
    fi

    # Try a lightweight apt update (timeout 15s)
    if timeout 15 sudo apt-get update -qq 2>/dev/null; then
        return 0
    fi

    return 1
}

# ── Python venv Availability ─────────────────────────────────
check_venv_available() {
    local python_bin="${1:-python3}"

    # Check if the venv module is importable
    if "$python_bin" -m venv --help &>/dev/null 2>&1; then
        return 0
    fi

    return 1
}

# ── tzdata Validation ────────────────────────────────────────
check_tzdata() {
    # Check for timezone data that pandas/pytz need
    if [ -f /usr/share/zoneinfo/tzdata.zi ]; then
        return 0
    fi

    # Fallback: check if any timezone files exist
    if [ -d /usr/share/zoneinfo ] && [ -f /usr/share/zoneinfo/UTC ]; then
        return 0
    fi

    # Final fallback: check Python
    local python_bin
    python_bin="$(find_python)"
    if [ -n "$python_bin" ]; then
        if "$python_bin" -c "import zoneinfo; zoneinfo.ZoneInfo('UTC')" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

# ── Port Availability Check ──────────────────────────────────
check_port_available() {
    local port="$1"

    if command -v ss &>/dev/null; then
        if ss -tln 2>/dev/null | grep -q ":${port} "; then
            return 1  # Port is in use
        fi
    elif command -v lsof &>/dev/null; then
        if lsof -i ":${port}" &>/dev/null; then
            return 1  # Port is in use
        fi
    elif command -v netstat &>/dev/null; then
        if netstat -tln 2>/dev/null | grep -q ":${port} "; then
            return 1  # Port is in use
        fi
    fi

    return 0  # Port is available (or cannot check)
}

# ── Port In-Use Check (inverse of available) ─────────────────
check_port_listening() {
    local port="$1"
    ! check_port_available "$port"
}

# ── Find Python 3.10+ ────────────────────────────────────────
find_python() {
    local candidate version major minor
    for candidate in python3.12 python3.11 python3.10 python3; do
        if command -v "$candidate" &>/dev/null; then
            version=$("$candidate" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "0.0")
            major=$(echo "$version" | cut -d. -f1)
            minor=$(echo "$version" | cut -d. -f2)
            if [ "$major" -ge 3 ] 2>/dev/null && [ "$minor" -ge 10 ] 2>/dev/null; then
                echo "$candidate"
                return 0
            fi
        fi
    done
    return 1
}

# ── Determine pip install mode ───────────────────────────────
# Returns "venv" or "user" based on what's available
pip_install_mode() {
    local python_bin="${1:-python3}"
    local venv_dir="${2:-$PROJECT_ROOT/backend/.venv}"

    # If venv already exists, use it
    if [ -d "$venv_dir" ] && [ -f "$venv_dir/bin/activate" ]; then
        echo "venv"
        return
    fi

    # Can we create a venv?
    if check_venv_available "$python_bin"; then
        echo "venv"
        return
    fi

    # Fallback to --user
    echo "user"
}

# ── Activate pip environment ─────────────────────────────────
# Sets up either venv or --user pip, returns pip flags
activate_pip_env() {
    local python_bin="${1:-python3}"
    local venv_dir="${2:-$PROJECT_ROOT/backend/.venv}"
    local mode

    mode="$(pip_install_mode "$python_bin" "$venv_dir")"

    if [ "$mode" = "venv" ]; then
        if [ ! -d "$venv_dir" ]; then
            info "Creating virtual environment at $venv_dir"
            "$python_bin" -m venv "$venv_dir" || {
                warn "Failed to create venv — falling back to pip --user"
                PIP_MODE="user"
                PIP_FLAGS="--user"
                export PIP_MODE PIP_FLAGS
                return
            }
            ok "Virtual environment created"
        fi
        # shellcheck disable=SC1091
        source "$venv_dir/bin/activate"
        PIP_MODE="venv"
        PIP_FLAGS=""
    else
        warn "python3-venv unavailable — using pip install --user"
        info "Packages will be installed to ~/.local/lib/python*/"
        PIP_MODE="user"
        PIP_FLAGS="--user"
    fi

    export PIP_MODE PIP_FLAGS
}

# ── Smart Model Pull ─────────────────────────────────────────
# Only pulls model if not already present in Ollama
smart_model_pull() {
    local model_name="$1"
    local ollama_url="${2:-}"

    # If no URL provided, detect it
    if [ -z "$ollama_url" ]; then
        ollama_url="$(detect_ollama_url 2>/dev/null || echo "")"
    fi

    if [ -z "$ollama_url" ]; then
        warn "Ollama not reachable — cannot pull model '$model_name'"
        return 1
    fi

    # Check if model is already loaded
    local models
    models=$(curl -s --max-time 5 "$ollama_url/api/tags" 2>/dev/null || echo "{}")
    local python_bin
    python_bin="$(find_python 2>/dev/null || echo "python3")"

    if echo "$models" | "$python_bin" -c "
import sys, json
try:
    d = json.load(sys.stdin)
    names = [m['name'] for m in d.get('models', [])]
    target = '${model_name}'
    # Check exact match or match without tag
    if any(target in n or n.startswith(target.split(':')[0]) for n in names):
        sys.exit(0)
    sys.exit(1)
except:
    sys.exit(1)
" 2>/dev/null; then
        ok "Model '$model_name' already available — skipping pull"
        return 0
    fi

    info "Pulling model: $model_name (this may take a while)..."
    if ollama pull "$model_name"; then
        ok "Model '$model_name' pulled successfully"
        return 0
    else
        warn "Failed to pull '$model_name' — pull manually: ollama pull $model_name"
        return 1
    fi
}

# ── Check if a Python package is installed ───────────────────
is_python_pkg_installed() {
    local pkg="$1"
    local python_bin="${2:-python3}"
    "$python_bin" -c "import importlib; importlib.import_module('${pkg}')" 2>/dev/null
}

# ── Check if PyTorch has CUDA ────────────────────────────────
is_torch_cuda_available() {
    local python_bin="${1:-python3}"
    "$python_bin" -c "import torch; exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null
}

# ── Auto-configure .env DEVICE setting ───────────────────────
auto_configure_device() {
    local env_file="${1:-$PROJECT_ROOT/.env}"

    if [ ! -f "$env_file" ]; then
        return
    fi

    detect_cuda

    if [ "$CUDA_AVAILABLE" = true ]; then
        # Set DEVICE=cuda
        if grep -q "^DEVICE=cpu" "$env_file" 2>/dev/null; then
            sed -i.bak 's/^DEVICE=cpu/DEVICE=cuda/' "$env_file" 2>/dev/null || \
            sed -i '' 's/^DEVICE=cpu/DEVICE=cuda/' "$env_file" 2>/dev/null || true
            rm -f "${env_file}.bak"
            ok "Auto-configured DEVICE=cuda (CUDA $CUDA_VERSION detected)"
        fi
        if grep -q "^USE_FP16=false" "$env_file" 2>/dev/null; then
            sed -i.bak 's/^USE_FP16=false/USE_FP16=true/' "$env_file" 2>/dev/null || \
            sed -i '' 's/^USE_FP16=false/USE_FP16=true/' "$env_file" 2>/dev/null || true
            rm -f "${env_file}.bak"
        fi
    else
        info "CUDA not detected — DEVICE will remain as cpu"
    fi
}

# ── Auto-configure Ollama URL in .env ────────────────────────
auto_configure_ollama_url() {
    local env_file="${1:-$PROJECT_ROOT/.env}"
    local detected_url

    detected_url="$(detect_ollama_url 2>/dev/null || echo "")"

    if [ -z "$detected_url" ]; then
        return 1
    fi

    if [ ! -f "$env_file" ]; then
        return 1
    fi

    local current_url
    current_url=$(grep "^OLLAMA_BASE_URL=" "$env_file" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'" || echo "")

    if [ "$current_url" != "$detected_url" ] && [ -n "$detected_url" ]; then
        sed -i.bak "s|^OLLAMA_BASE_URL=.*|OLLAMA_BASE_URL=$detected_url|" "$env_file" 2>/dev/null || \
        sed -i '' "s|^OLLAMA_BASE_URL=.*|OLLAMA_BASE_URL=$detected_url|" "$env_file" 2>/dev/null || true
        rm -f "${env_file}.bak"
        ok "Auto-configured OLLAMA_BASE_URL=$detected_url"
    fi

    return 0
}

# ── Read a value from .env ───────────────────────────────────
env_get() {
    local key="$1" default="${2:-}"
    local val
    val=$(grep -E "^${key}=" "$PROJECT_ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
    echo "${val:-$default}"
}

# ── Print environment summary ────────────────────────────────
print_env_summary() {
    local env
    env="$(detect_environment)"
    detect_cuda

    echo ""
    echo -e "${BOLD}Environment Summary${NC}"
    echo "────────────────────────────────────────"
    echo -e "  Platform:      ${CYAN}$env${NC}"
    echo -e "  OS:            $(uname -s) $(uname -r 2>/dev/null | cut -d- -f1)"
    echo -e "  Architecture:  $(uname -m)"

    if [ "$CUDA_AVAILABLE" = true ]; then
        echo -e "  CUDA:          ${GREEN}$CUDA_VERSION${NC}"
        [ -n "$GPU_NAME" ] && echo -e "  GPU:           ${GREEN}$GPU_NAME${NC}"
    else
        echo -e "  CUDA:          ${YELLOW}not available${NC}"
    fi

    local ollama_status
    ollama_status="$(detect_ollama)"
    case "$ollama_status" in
        INSTALLED_RUNNING) echo -e "  Ollama:        ${GREEN}running${NC}" ;;
        INSTALLED_STOPPED) echo -e "  Ollama:        ${YELLOW}installed but stopped${NC}" ;;
        MISSING)           echo -e "  Ollama:        ${RED}not installed${NC}" ;;
    esac

    echo "────────────────────────────────────────"
}
