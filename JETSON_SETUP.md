# MachineGuru — NVIDIA Jetson Orin Setup Guide

## Overview

This guide covers everything needed to configure an NVIDIA Jetson Orin board for running MachineGuru with full GPU acceleration.

**Supported boards:**
- Jetson Orin Nano (8 GB)
- Jetson Orin NX (8 GB / 16 GB)
- Jetson AGX Orin (32 GB / 64 GB)

**Supported JetPack versions:**
- JetPack 5.1.x (Ubuntu 20.04)
- JetPack 6.x (Ubuntu 22.04) ← Recommended

---

## Quick Setup

```bash
# Run automated Jetson setup (requires JetPack already installed)
./deploy/jetson_setup.sh

# Then install the application
./deploy/install.sh
```

---

## Prerequisites

### 1. Flash JetPack

Use NVIDIA SDK Manager on a host Ubuntu machine to flash JetPack 6.x:
- Download: https://developer.nvidia.com/sdk-manager
- Select: Jetson Orin → JetPack 6.x → Install

Or use Jetson's built-in OTA update for minor versions.

### 2. Initial Jetson Configuration

After booting the flashed Jetson for the first time:

```bash
# Expand the root filesystem if needed
sudo systemctl start nvsetuphelper-complete.service

# Update system packages
sudo apt-get update && sudo apt-get upgrade -y

# Verify CUDA installation
nvcc --version
nvidia-smi          # Not available on Jetson — use tegrastats instead
tegrastats          # Jetson GPU monitoring tool
```

---

## GPU Verification

```bash
# Check CUDA
nvcc --version
ls /usr/local/cuda/

# Check GPU from Python (after jetson_setup.sh installs PyTorch)
python3 -c "import torch; print('CUDA:', torch.cuda.is_available()); print('Device:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'N/A')"

# Monitor GPU utilization
tegrastats --interval 1000
```

---

## PyTorch Installation

> ⚠️ **Critical**: Do NOT install PyTorch from PyPI (`pip install torch`) on Jetson.  
> The standard PyPI wheel is built for x86_64 and will either fail or install a CPU-only build.

NVIDIA provides JetPack-compatible PyTorch wheels:

```bash
# JetPack 6 (Ubuntu 22.04) — CUDA 12.x
pip install torch torchvision \
    --index-url https://pypi.jetson-ai-lab.dev/jp6/cu126 \
    --extra-index-url https://pypi.org/simple

# Verify GPU is available
python3 -c "import torch; print(torch.cuda.is_available())"
```

**Manual fallback** (if automated index is unavailable):
1. Visit: https://forums.developer.nvidia.com/t/pytorch-for-jetson/72048
2. Download the `.whl` file matching your JetPack version
3. Install: `pip install torch-*.whl`

The `./deploy/jetson_setup.sh` script handles this automatically.

---

## Ollama on Jetson

The official Ollama Docker image **does not support Jetson CUDA**. Ollama must be installed natively:

```bash
# Install Ollama natively (ARM64 with Jetson CUDA support)
curl -fsSL https://ollama.com/install.sh | sh

# Verify installation
ollama --version

# Start Ollama service
sudo systemctl enable ollama
sudo systemctl start ollama

# Test GPU inference
ollama run llama3.2:1b "Hello, are you using GPU?"

# Check GPU usage during inference
tegrastats  # In another terminal
```

### Ollama Model Recommendations for Jetson

| Model | VRAM | Quality | Use Case |
|-------|------|---------|----------|
| `llama3.2:1b` | ~1 GB | Good | Default — fast, low VRAM |
| `phi3:mini` | ~2 GB | Better | Balance of speed and quality |
| `llama3.2:3b` | ~2 GB | Better | More capable |
| `llama3.1:8b` | ~5 GB | Best | Needs Orin NX 16GB or AGX |
| `llava:7b` | ~5 GB | Multimodal | For vision/image analysis |

```bash
# Pull recommended model
ollama pull llama3.2:1b

# List available models
ollama list
```

---

## Jetson Power Modes

Higher power modes = better GPU performance:

```bash
# Check current mode
nvpmodel -q

# Set maximum performance (MAXN = mode 0)
sudo nvpmodel -m 0

# Maximize clocks
sudo jetson_clocks

# Available modes (varies by Jetson model)
nvpmodel -q --verbose
```

For persistent maximum performance:

```bash
# Add to crontab for persistence across reboots
echo "@reboot root nvpmodel -m 0 && jetson_clocks" | sudo tee /etc/cron.d/jetson-perf
```

---

## Memory Configuration

### Swap Setup

Jetson Orin Nano has 8 GB unified RAM shared between CPU and GPU. For large models, configure swap:

```bash
# Check current swap
free -h

# Create 8 GB swap file
sudo swapoff -a
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make persistent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Verify
free -h
```

### MachineGuru Memory Settings for Jetson

```env
# For Jetson Orin Nano (8 GB)
MEMORY_BUDGET_MB=3072
BATCH_SIZE=16
MAX_CONCURRENT_LLM=1
MAX_CONCURRENT_EMBEDDING=1
IDLE_MODEL_TIMEOUT=120

# For Jetson AGX Orin (32/64 GB)
MEMORY_BUDGET_MB=8192
BATCH_SIZE=64
MAX_CONCURRENT_LLM=2
MAX_CONCURRENT_EMBEDDING=2
```

---

## Enable GPU in MachineGuru

After running `jetson_setup.sh`, verify `.env` contains:

```env
DEVICE=cuda
USE_FP16=true
USE_FLASH_ATTENTION=true
```

These enable:
- **DEVICE=cuda**: Embedding model runs on GPU
- **USE_FP16=true**: Half-precision inference (2x faster, same quality)
- **USE_FLASH_ATTENTION=true**: Flash Attention 2 (Jetson Orin Ampere architecture supports it)

---

## Performance Tuning

### Ollama GPU Settings

```bash
# In /etc/systemd/system/ollama.service.d/override.conf
# (create with: sudo systemctl edit ollama)

[Service]
Environment="OLLAMA_NUM_PARALLEL=2"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_KEEP_ALIVE=10m"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
```

### Expected Performance (Jetson Orin Nano, 8GB)

| Operation | Time |
|-----------|------|
| First token (llama3.2:1b) | ~2-4 seconds |
| Token generation | ~15-25 tokens/sec |
| PDF embedding (10 pages) | ~5-10 seconds |
| Vector search | <100ms |
| Full RAG query | ~5-15 seconds |

---

## Monitoring on Jetson

```bash
# GPU + CPU + Memory monitoring
tegrastats --interval 500

# Power consumption
cat /sys/bus/i2c/drivers/ina3221x/*/iio\:device*/in_power*_input 2>/dev/null

# Temperature
cat /sys/devices/virtual/thermal/thermal_zone*/temp 2>/dev/null | awk '{print $1/1000 "°C"}'

# MachineGuru stats endpoint
curl http://localhost:8001/api/v1/stats | python3 -m json.tool
```

---

## Networking

If accessing MachineGuru from another device on the network:

```bash
# Find Jetson's IP address
ip addr show | grep "inet " | grep -v 127

# Update .env with your Jetson's IP in CORS_ORIGINS
CORS_ORIGINS=["http://localhost:5173","http://<jetson-ip>:5173"]

# Access frontend from another machine
# http://<jetson-ip>:5173
```

For persistent static IP, configure `/etc/netplan/`:

```yaml
# /etc/netplan/01-network-manager-all.yaml
network:
  ethernets:
    eth0:
      addresses: [192.168.1.100/24]
      gateway4: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8]
```

---

## Common Jetson Issues

| Issue | Solution |
|-------|----------|
| CUDA not available in Python | Run `./deploy/jetson_setup.sh` to install Jetson PyTorch |
| Ollama using CPU not GPU | Check `OLLAMA_FLASH_ATTENTION=1` in Ollama service env |
| Out of memory | Add swap, reduce `MEMORY_BUDGET_MB`, lower `BATCH_SIZE` |
| Slow embedding | Set `DEVICE=cuda`, `USE_FP16=true` in `.env` |
| `nvcc` not found | Install CUDA: `sudo apt-get install nvidia-cuda-toolkit` |
| Docker GPU not working | Run `sudo nvidia-ctk runtime configure --runtime=docker` |
| System too hot | Check power mode: `nvpmodel -q`, ensure adequate cooling |

---

## JetPack Compatibility Table

| JetPack | Ubuntu | CUDA | PyTorch | Status |
|---------|--------|------|---------|--------|
| 4.6.x | 18.04 | 10.2 | 1.x | ❌ Not supported |
| 5.1.x | 20.04 | 11.4 | 2.0.x | ⚠️ Limited |
| 6.0 | 22.04 | 12.2 | 2.3.x | ✅ Supported |
| 6.1 | 22.04 | 12.4 | 2.4.x | ✅ Recommended |

---

## References

- [NVIDIA Jetson PyTorch](https://forums.developer.nvidia.com/t/pytorch-for-jetson/72048)
- [NVIDIA Jetson AI Lab](https://www.jetson-ai-lab.com/)
- [Ollama Installation](https://ollama.com/install)
- [JetPack SDK Manager](https://developer.nvidia.com/sdk-manager)
- [Jetson Orin Specifications](https://www.nvidia.com/en-us/autonomous-machines/embedded-systems/jetson-orin/)
