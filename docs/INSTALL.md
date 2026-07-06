# Installation Guide

## Prerequisites

| Requirement | Version | Purpose |
|-------------|---------|---------|
| Docker & Compose | 24+ / 2.20+ | Container orchestration |
| NVIDIA Container Toolkit | 1.14+ | GPU passthrough to containers |
| NVIDIA Jetson Orin Nano | Any | Target hardware (x86_64 works for dev) |
| 16 GB+ RAM | — | Memory for models and Qdrant |
| 20 GB+ free disk | — | Docker images + model storage |

---

## 1. Jetson Orin Nano Setup

```bash
# Install NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

# Configure Docker runtime
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Verify GPU access
docker run --rm --gpus all nvidia/cuda:12.5-runtime nvidia-smi
```

---

## 2. Docker Installation

### Option A: Production (Recommended)

```bash
# Clone
git clone <repo-url> && cd MachineGuru

# Configure
cp .env.example .env
# Edit .env for your environment:
#   DEVICE=cuda
#   USE_FP16=true
#   USE_FLASH_ATTENTION=true

# Build and start
make build
make up

# Wait for services to be healthy, then pull models
make models

# Verify
make health
```

### Option B: Development

```bash
# Backend
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000 &

# Frontend (separate terminal)
cd frontend
npm install
npm run dev

# Infrastructure (separate terminal)
docker compose up qdrant ollama -d
```

---

## 3. Offline Deployment

For air-gapped environments, pre-load all Docker images:

```bash
# On a machine with internet access
docker pull qdrant/qdrant:v1.13.2
docker pull ollama/ollama:0.4.7
make build
make offline-save   # saves to ./offline/*.tar

# Copy ./offline/ to the target machine

# On the offline Jetson
make offline-load
make models         # requires models/ directory with .gguf files
make up
```

### Offline Model Files

For fully offline operation, pre-download Ollama models:

```bash
# On internet-connected machine
ollama pull llama3.2:1b
ollama pull multilingual-e5-small
tar czf ollama_models.tar.gz ~/.ollama/

# Copy to Jetson and extract
tar xzf ollama_models.tar.gz -C ~/.ollama/
```

Then mount the model volume:
```yaml
# docker-compose.yml override
volumes:
  - ~/.ollama:/root/.ollama
```

---

## 4. Verify Installation

```bash
# Health check
curl http://localhost:8000/api/v1/health
# → {"status":"healthy","version":"0.1.0",...}

# System stats
curl http://localhost:8000/api/v1/stats
# → {"memory_mb": 245.3, "cpu_percent": 12.5, "gpu": {...}, ...}

# Prometheus metrics
curl http://localhost:8000/metrics
# → machineguru_query_total{status="ok"} 42.0

# Upload a test document
curl -X POST http://localhost:8000/api/v1/ingest \
  -F "file=@test.pdf"
# → {"document_id":"...","chunk_count":47,...}

# Ask a question
curl -X POST http://localhost:8000/api/v1/query \
  -H "Content-Type: application/json" \
  -d '{"text":"What is this document about?"}'
```

---

## 5. Production Deployment

See **[Deployment Guide](DEPLOYMENT.md)** for comprehensive production setup including:

- [ ] TLS/SSL termination with Let's Encrypt
- [ ] Prometheus + Grafana monitoring stack
- [ ] Automated backups
- [ ] Health check alerts
- [ ] Resource tuning for Jetson Orin Nano
- [ ] Security hardening

## 6. Production Checklist

- [ ] `DEBUG=false` in `.env`
- [ ] `CORS_ORIGINS` restricted to your domain
- [ ] TLS/SSL termination configured (reverse proxy with certbot)
- [ ] Regular backups scheduled (see `make backup`)
- [ ] Resource limits tuned in `docker-compose.yml`
- [ ] Monitoring stack deployed (Prometheus + Grafana)
- [ ] `JSON_LOGGING=true` for log aggregation
- [ ] Health check alerts configured
- [ ] Rate limiting verified (nginx + application layer)
- [ ] Security headers confirmed (CSP, HSTS, X-Frame)

---

## 6. Troubleshooting

| Problem | Solution |
|---------|----------|
| `CUDA error: out of memory` | Reduce `MEMORY_BUDGET_MB`, set `USE_FP16=true` |
| Ollama won't start | Check `nvidia-smi`, ensure `runtime: nvidia` in compose |
| Qdrant connection refused | Wait for healthcheck, check network: `docker network ls` |
| Frontend shows blank page | Check `docker compose logs frontend`, verify nginx config |
| Slow query response | Check `GET /api/v1/stats` for cache hit rate, concurrency stats |
| Container exiting | Run `docker compose logs <service>` for details |
