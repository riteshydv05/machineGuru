# MachineGuru — Production Deployment Guide

## Overview

This document covers the complete native deployment flow for MachineGuru on NVIDIA Jetson Orin running Ubuntu 20.04/22.04 ARM64. For x86_64 development machines, Docker Compose is the preferred path.

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

## Prerequisites

| Requirement | Minimum | Recommended |
|------------|---------|-------------|
| OS | Ubuntu 20.04 ARM64 | Ubuntu 22.04 ARM64 |
| RAM | 8 GB | 16 GB |
| Disk | 20 GB free | 50 GB SSD |
| Python | 3.10 | 3.11 or 3.12 |
| Node.js | 20 LTS | 20 LTS |
| JetPack | 5.x | 6.x |

---

## Step-by-Step Deployment

### Step 1 — Clone the Repository

```bash
git clone <your-repo-url> /opt/machineguru
cd /opt/machineguru
```

### Step 2 — Jetson GPU Setup (Jetson Only)

```bash
./deploy/jetson_setup.sh
```

This script:
- Detects JetPack version
- Installs NVIDIA Container Toolkit
- Configures swap (8GB recommended)
- Installs PyTorch from NVIDIA's Jetson wheel index
- Sets Jetson power mode to MAXN
- Updates `.env` with `DEVICE=cuda`

### Step 3 — Install All Dependencies

```bash
./deploy/install.sh
```

Use flags to skip optional steps:
```bash
./deploy/install.sh --skip-models    # Don't pull Ollama models (pull manually later)
./deploy/install.sh --skip-frontend  # Skip frontend build (use dev mode)
```

### Step 4 — Configure Environment

```bash
# Edit .env for your specific setup
nano .env

# Key settings to verify:
# - OLLAMA_BASE_URL  (should be http://localhost:11434 for native)
# - DEVICE           (set to 'cuda' for Jetson GPU, 'cpu' for development)
# - CORS_ORIGINS     (add your Jetson's IP address if accessing remotely)
# - LLM_MODEL        (default: llama3.2:1b — pull with: ollama pull <model>)
```

### Step 5 — Start Services

```bash
# Production mode
./start.sh

# Development mode (hot reload)
./start.sh --dev

# Without frontend (headless/API only)
./start.sh --no-frontend
```

### Step 6 — Verify Installation

```bash
./deploy/verify_installation.sh
```

This runs 10 end-to-end checks including uploading a test document and running a RAG query.

---

## Startup Flow

```
./start.sh
  │
  ├─ 1. Load .env + resolve all paths to absolute
  ├─ 2. Create storage/, logs/ if missing
  ├─ 3. Kill stale processes (via PID files)
  ├─ 4. Start Qdrant → wait for /healthz (20s timeout)
  ├─ 5. Verify Ollama is reachable → warn if not
  ├─ 6. Start Backend (uvicorn) → wait for /api/v1/health (30s timeout)
  │      Backend on startup:
  │        ├─ Setup logging (rotating file + console)
  │        ├─ Create UPLOAD_DIR, LOG_DIR
  │        ├─ Connect to Qdrant → ensure collection exists
  │        └─ Load document registry
  └─ 7. Start Frontend → wait for HTTP 200 (15s timeout)
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
  └─ 3. SIGTERM → Qdrant → wait 10s → Qdrant flushes WAL
```

---

## Data Directories

All runtime data is stored under `storage/` and `logs/`, both gitignored:

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
├── backend.log   ← Backend application log (rotating)
├── qdrant.log    ← Qdrant server log
├── frontend.log  ← Frontend server log
└── deployment.log← Install/update script log
```

---

## Updating

```bash
# Pull latest code and rebuild (no service downtime during build)
./deploy/update.sh

# Pull + restart services
./deploy/update.sh --restart

# Skip model re-download
./deploy/update.sh --restart --skip-models
```

---

## Backup

```bash
# Backup uploads and Qdrant data
./scripts/backup.sh

# Backup to specific directory
./scripts/backup.sh /mnt/external/backups
```

Backups include:
- `storage/uploads/` — all uploaded documents
- `storage/qdrant/` — vector database files (or Qdrant snapshots)
- `.env` — configuration

---

## Rollback

```bash
# Stop services
./stop.sh

# Restore from backup
tar -xzf backups/<timestamp>/uploads.tar.gz -C storage/
tar -xzf backups/<timestamp>/qdrant.tar.gz -C storage/

# Restart
./start.sh
```

---

## Systemd Auto-Start (Optional)

To start MachineGuru automatically on boot:

```bash
# Create systemd service
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

## Health Monitoring

```bash
# Quick health check
./deploy/healthcheck.sh

# JSON output (for scripting)
./deploy/healthcheck.sh --json

# Full verbose output
./deploy/healthcheck.sh --verbose

# Watch in real-time
watch -n 10 './deploy/healthcheck.sh'
```

---

## Troubleshooting

### Backend fails to start

```bash
# Check the log
tail -50 logs/backend.log

# Common causes:
# 1. Qdrant not running → check logs/qdrant.log
# 2. .env not found → cp .env.example .env
# 3. Python venv missing → ./deploy/install.sh
# 4. Port already in use → lsof -i :8001
```

### Out of memory during model loading

```bash
# Check memory
free -h

# Reduce memory usage in .env:
MEMORY_BUDGET_MB=1024
BATCH_SIZE=16
MAX_CONCURRENT_LLM=1
MAX_CONCURRENT_EMBEDDING=1

# Ensure swap is configured (Jetson)
sudo swapon --show
```

### Qdrant data corruption

```bash
# Stop services
./stop.sh

# Backup current state
cp -r storage/qdrant storage/qdrant.bak

# Clear and let backend recreate the collection
rm -rf storage/qdrant/*
./start.sh

# Re-ingest documents via the UI
```

---

## Security Checklist

- [ ] `DEBUG=false` in `.env`
- [ ] `.env` is in `.gitignore` (never commit secrets)
- [ ] `CORS_ORIGINS` restricted to your actual frontend URL
- [ ] Firewall: only expose port `5173` (or `80`) externally; keep `8001`, `6333`, `11434` internal
- [ ] Log rotation configured (`LOG_RETENTION_DAYS`, `LOG_MAX_SIZE_MB`)
- [ ] File upload size limited (`MAX_FILE_SIZE=52428800` = 50 MB)
- [ ] Run backend as non-root user
