# MachineGuru — Production Deployment Guide

## Overview

This document covers complete deployment flows for MachineGuru across all supported platforms. The deployment system auto-detects the environment and configures itself.

---

## Supported Platforms

| Platform | Architecture | CUDA | Mode |
|----------|-------------|------|------|
| NVIDIA Jetson Orin (Native) | ARM64 | ✅ | Full GPU acceleration |
| NVIDIA Jetson Cloud Lab | ARM64 | ✅ | Resilient (apt/venv fallbacks) |
| Ubuntu ARM64 | ARM64 | Optional | Standard |
| Ubuntu x86_64 | x86_64 | Optional | Development / Production |
| macOS (dev) | ARM64/x86_64 | ❌ | Development only |
| Docker (x86_64) | x86_64 | Optional | Containerized |

---

## Deployment Architecture

```
Native Deployment (Recommended for Jetson)
─────────────────────────────────────────
Host Ubuntu ARM64
├── Ollama         ← installed natively (systemd service)
├── Qdrant         ← binary in qdrant_bin/, data in storage/qdrant/
├── Backend        ← Python venv in backend/.venv/
│                     started by start.sh as background process
│                     PID tracked in storage/temporary/backend.pid
└── Frontend       ← built to frontend/dist/ by install.sh
                      served by `npx serve` or Vite dev server

Docker Deployment (x86_64 only)
────────────────────────────────
docker compose up -d
└── Services: backend, frontend, qdrant, ollama
    Note: Ollama Docker image ≠ Jetson CUDA compatible
```

---

## Auto-Detection System

The deployment scripts automatically detect:

| Feature | How | Fallback |
|---------|-----|----------|
| **Environment** | `/proc/device-tree/model`, `/etc/nv_tegra_release`, `uname -m` | Manual config |
| **CUDA** | `nvcc`, `/usr/local/cuda`, `torch.cuda.is_available()` | DEVICE=cpu |
| **Ollama** | `which ollama` + HTTP probe on multiple endpoints | Print install instructions |
| **Ollama URL** | Probe: `localhost:11434` → `172.17.0.1:11434` → `host.docker.internal:11434` | Use configured URL |
| **apt availability** | `apt-get update` with timeout | Skip apt, use existing packages |
| **venv availability** | `python3 -m venv --help` | `pip install --user` |
| **Internet** | Probe google.com, pypi.org | Skip network-dependent steps |
| **tzdata** | Check `/usr/share/zoneinfo/tzdata.zi` | Warn, suggest `USE_OLLAMA_EMBEDDINGS=true` |

---

## Prerequisites

| Requirement | Minimum | Recommended |
|------------|---------|-------------|
| OS | Ubuntu 20.04 ARM64 | Ubuntu 22.04 ARM64 |
| RAM | 4 GB | 8–16 GB |
| Disk | 10 GB free | 50 GB SSD |
| Python | 3.10 | 3.11 or 3.12 |
| Node.js | 20 LTS | 20 LTS |
| JetPack | 5.x (Jetson only) | 6.x |

---

## Quick Start

### Preflight Check (Optional but Recommended)

```bash
./deploy/preflight.sh
```

This validates everything **without modifying** the system. Fix any FAIL items before proceeding.

### Jetson Native Deployment

```bash
# Step 1: GPU setup (Jetson only, run once)
./deploy/jetson_setup.sh

# Step 2: Install everything
./deploy/install.sh

# Step 3: Start services
./start.sh

# Step 4: Verify
./deploy/verify_installation.sh
```

### Jetson Cloud Lab Deployment

The install script auto-detects Cloud Lab and:
- Skips `apt` if repositories are unreachable
- Falls back to `pip install --user` if `python3-venv` is unavailable
- Reuses pre-installed PyTorch and CUDA
- Auto-detects Ollama if running in a container or on the host

```bash
# Step 1: Check what's available
./deploy/preflight.sh

# Step 2: Install (auto-detects Cloud Lab mode)
./deploy/install.sh

# Step 3: Start
./start.sh

# If SentenceTransformers fails due to tzdata:
# Edit .env and set USE_OLLAMA_EMBEDDINGS=true
```

### Ubuntu x86_64 Development

```bash
./deploy/install.sh
./start.sh
```

### Docker Deployment (x86_64)

```bash
docker compose up -d

# Pull models
docker exec machine-guru-ollama ollama pull llama3.2:1b

# Verify
docker compose ps
curl http://localhost:8001/api/v1/health
```

> **⚠ Jetson Note:** The `ollama/ollama` Docker image does NOT support Jetson CUDA.
> Use native deployment on Jetson for GPU acceleration.

---

## Script Reference

| Script | Purpose |
|--------|---------|
| `deploy/preflight.sh` | Pre-install validation (no modifications) |
| `deploy/install.sh` | Full installation with auto-detection |
| `deploy/jetson_setup.sh` | Jetson GPU setup (run before install.sh) |
| `deploy/healthcheck.sh` | Production health check (colored / JSON output) |
| `deploy/verify_installation.sh` | End-to-end functional verification |
| `deploy/update.sh` | Git pull + rebuild + optional restart |
| `start.sh` | Start all services (Ollama auto-start) |
| `stop.sh` | Graceful shutdown |
| `restart.sh` | Stop + start (with port cleanup) |

### Install Script Flags

```bash
./deploy/install.sh                  # Full install
./deploy/install.sh --skip-models    # Don't pull Ollama models
./deploy/install.sh --skip-frontend  # Skip frontend build
```

### Start Script Flags

```bash
./start.sh                  # Default (dev mode with Vite proxy)
./start.sh --dev             # Explicit dev mode
./start.sh --prod-serve      # Production (requires nginx for /api proxy)
./start.sh --no-frontend     # Headless / API only
./start.sh --no-qdrant       # Skip Qdrant start (if running externally)
```

### Stop Script Flags

```bash
./stop.sh                    # Graceful stop (Ollama preserved)
./stop.sh --force            # Force-kill if graceful fails
./stop.sh --stop-ollama      # Also stop Ollama
```

---

## Environment Configuration

### Key Settings

```bash
# Auto-detected by install.sh — normally no manual edit needed
DEVICE=cpu                    # Auto-set to 'cuda' if CUDA detected
OLLAMA_BASE_URL=http://localhost:11434  # Auto-detected

# Embedding backend
USE_OLLAMA_EMBEDDINGS=false   # Set to true if SentenceTransformers fails

# Models
LLM_MODEL=llama3.2:1b        # Must be pulled: ollama pull <model>
EMBEDDING_MODEL=intfloat/multilingual-e5-small
```

### Feature Flag: USE_OLLAMA_EMBEDDINGS

When `true`, embeddings are generated via Ollama's `/api/embeddings` endpoint instead of the local SentenceTransformers model. This is useful when:

- `import pandas` fails due to missing tzdata
- SentenceTransformers dependencies cannot be installed
- You want to reduce the Python dependency footprint

> **⚠ WARNING:** Switching this flag changes the embedding dimensions. You must **re-index all documents** after switching.

---

## Startup Flow

```
./start.sh
  │
  ├─ 1. Validate: check venv or system Python packages
  ├─ 2. Create: storage/, logs/ directories
  ├─ 3. Cleanup: kill stale processes (via PID files)
  ├─ 4. Ollama: auto-start if installed but stopped
  │      └─ Auto-detect URL (localhost → 172.17.0.1 → host.docker.internal)
  ├─ 5. Start Qdrant → wait for /healthz (20s timeout)
  ├─ 6. Start Backend (uvicorn) → wait for /api/v1/health (30s timeout)
  │      Backend on startup:
  │        ├─ Setup logging (rotating file + console)
  │        ├─ Create UPLOAD_DIR, LOG_DIR
  │        ├─ Connect to Qdrant → ensure collection exists
  │        └─ Load document registry
  ├─ 7. Start Frontend → wait for HTTP 200 (20s timeout)
  └─ 8. Verify: all services reachable → print summary
```

---

## Shutdown Flow

```
./stop.sh
  ├─ 1. SIGTERM → Frontend → wait 10s → (SIGKILL with --force)
  ├─ 2. SIGTERM → Backend → wait 10s → backend flushes in-flight
  │      Backend handles SIGTERM:
  │        ├─ Sets _SHUTTING_DOWN = True → returns 503 to new requests
  │        └─ Unloads models → GC
  ├─ 3. SIGTERM → Qdrant → wait 10s → Qdrant flushes WAL
  └─ 4. Ollama → preserved (use --stop-ollama to stop)
```

---

## Data Directories

```
storage/
├── uploads/      ← Uploaded PDFs, DOCX, TXT files
├── qdrant/       ← Qdrant WAL, snapshots, segments
├── cache/        ← Query result cache
├── embeddings/   ← Cached embedding vectors
├── history/      ← Chat history (future)
├── temporary/    ← PID files (backend.pid, qdrant.pid, frontend.pid)
└── models/       ← Downloaded models cache

logs/
├── install.log      ← Installation log
├── backend.log      ← Backend application log
├── frontend.log     ← Frontend server log
├── qdrant.log       ← Qdrant server log
├── healthcheck.log  ← Health check results log
└── jetson_setup.log ← Jetson setup log
```

---

## Health Monitoring

```bash
# Colored terminal output
./deploy/healthcheck.sh

# JSON output (for scripting / monitoring)
./deploy/healthcheck.sh --json

# Full end-to-end verification (uploads test doc, runs query)
./deploy/verify_installation.sh

# Watch in real-time
watch -n 10 './deploy/healthcheck.sh'
```

---

## Updating

```bash
./deploy/update.sh                       # Pull + rebuild
./deploy/update.sh --restart             # Pull + rebuild + restart
./deploy/update.sh --restart --skip-models  # Skip model re-download
```

---

## Backup & Restore

```bash
# Backup
./scripts/backup.sh
./scripts/backup.sh /mnt/external/backups

# Restore
./stop.sh
tar -xzf backups/<timestamp>/uploads.tar.gz -C storage/
tar -xzf backups/<timestamp>/qdrant.tar.gz -C storage/
./start.sh
```

---

## Systemd Auto-Start (Optional)

```bash
sudo tee /etc/systemd/system/machineguru.service << EOF
[Unit]
Description=MachineGuru RAG Service
After=network.target ollama.service
Wants=ollama.service

[Service]
Type=forking
User=$USER
WorkingDirectory=/opt/machineguru
ExecStart=/opt/machineguru/start.sh
ExecStop=/opt/machineguru/stop.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable machineguru
sudo systemctl start machineguru
```

---

## Troubleshooting

### Backend fails to start

```bash
tail -50 logs/backend.log

# Common causes:
# 1. Qdrant not running → check logs/qdrant.log
# 2. .env not found → cp .env.example .env
# 3. Python venv missing → ./deploy/install.sh
# 4. Port already in use → lsof -i :8001
# 5. Missing dependencies → ./deploy/healthcheck.sh
```

### "import pandas" fails (tzdata missing)

This happens on Cloud Lab images missing `/usr/share/zoneinfo/tzdata.zi`.

**Fix options:**
1. Install tzdata: `sudo apt install tzdata`
2. Use Ollama embeddings: Set `USE_OLLAMA_EMBEDDINGS=true` in `.env`
3. Contact Cloud Lab administrator

### Ollama not reachable

```bash
# Check Ollama status
which ollama              # Is it installed?
ollama list               # Can it respond?
curl localhost:11434      # Is the API reachable?

# Start Ollama
ollama serve              # Manual start
sudo systemctl start ollama  # Systemd start

# If running in Docker, try alternative endpoints:
curl 172.17.0.1:11434     # Docker bridge
curl host.docker.internal:11434  # Docker Desktop
```

### Out of memory during model loading

```bash
free -h

# Reduce memory usage in .env:
MEMORY_BUDGET_MB=1024
BATCH_SIZE=16
MAX_CONCURRENT_LLM=1
MAX_CONCURRENT_EMBEDDING=1

# Ensure swap is configured (Jetson)
sudo swapon --show
```

### apt repositories unreachable (Cloud Lab)

The install script handles this automatically. If you need to install packages manually:

```bash
# Check connectivity
curl -sf https://ports.ubuntu.com > /dev/null && echo "reachable" || echo "unreachable"

# The install script will:
# - Skip apt if unreachable
# - Use pip --user if venv unavailable
# - Reuse pre-installed packages
```

### Qdrant data corruption

```bash
./stop.sh
cp -r storage/qdrant storage/qdrant.bak
rm -rf storage/qdrant/*
./start.sh
# Re-ingest documents via the UI
```

### Port conflicts

```bash
# Find what's using a port
lsof -i :8001    # Backend
lsof -i :6333    # Qdrant
lsof -i :5173    # Frontend
lsof -i :11434   # Ollama

# Force stop everything
./stop.sh --force
```

---

## Known Issues

| Issue | Status | Workaround |
|-------|--------|------------|
| Cloud Lab apt repos unreachable | ✅ Handled | install.sh auto-skips |
| Cloud Lab missing python3-venv | ✅ Handled | Auto-fallback to `pip --user` |
| Cloud Lab missing tzdata | ✅ Handled | Clear error + `USE_OLLAMA_EMBEDDINGS=true` |
| Ollama Docker ≠ Jetson CUDA | Documented | Use native Ollama on Jetson |
| First embedding load is slow | Expected | ~10–30s on Jetson for SentenceTransformers |
| Large model pull timeout | Known | Pre-pull models before deployment |

---

## Security Checklist

- [ ] `DEBUG=false` in `.env`
- [ ] `.env` is in `.gitignore` (never commit secrets)
- [ ] `CORS_ORIGINS` restricted to actual frontend URL
- [ ] Firewall: expose only port `5173` (or `80`) externally; keep `8001`, `6333`, `11434` internal
- [ ] Log rotation configured (`LOG_RETENTION_DAYS`, `LOG_MAX_SIZE_MB`)
- [ ] File upload size limited (`MAX_FILE_SIZE=52428800` = 50 MB)
- [ ] Run backend as non-root user
