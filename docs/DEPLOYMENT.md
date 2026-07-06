# Production Deployment Guide

## Overview

This guide covers production-grade deployment of MachineGuru, including TLS termination, load balancing, backup/restore, and monitoring stack setup.

---

## 1. Prerequisites

| Requirement | Version | Purpose |
|-------------|---------|---------|
| Docker & Compose | 24+ / 2.20+ | Container orchestration |
| NVIDIA Container Toolkit | 1.14+ | GPU passthrough (Jetson) |
| NVIDIA Jetson Orin Nano | Any | Target hardware |
| 16 GB+ RAM | — | Memory for models + Qdrant |
| 20 GB+ free disk | — | Docker images + model storage |
| Domain name | — | Required for TLS |
| Port 80/443 | — | HTTP/HTTPS access |

---

## 2. Environment Configuration

### Minimal Production .env

```env
# Application
DEBUG=false
CORS_ORIGINS=["https://yourdomain.com"]

# Hardware
DEVICE=cuda
USE_FP16=true
USE_FLASH_ATTENTION=true

# Logging
JSON_LOGGING=true
LOG_LEVEL=INFO

# Model
LLM_MODEL=llama3.2:1b
EMBEDDING_MODEL=multilingual-e5-small

# Concurrency (Jetson Orin Nano 8GB)
MAX_CONCURRENT_LLM=1
MAX_CONCURRENT_EMBEDDING=1
MEMORY_BUDGET_MB=1536
CHUNK_SIZE=384
BATCH_SIZE=32
```

---

## 3. Deployment Options

### Option A: Direct Docker (Recommended)

```bash
# Build with production optimizations
docker compose build --no-cache

# Start services
docker compose up -d

# Pull models
make models

# Verify deployment
make health
```

### Option B: With TLS (Nginx Proxy)

```bash
# 1. Install certbot
sudo apt-get install -y certbot python3-certbot-nginx

# 2. Obtain certificate
sudo certbot --nginx -d yourdomain.com

# 3. Update frontend/nginx.conf to include TLS
```

Example TLS-enhanced nginx config:

```nginx
server {
    listen 443 ssl http2;
    server_name yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # ... rest of config
}

server {
    listen 80;
    server_name yourdomain.com;
    return 301 https://$host$request_uri;
}
```

### Option C: Docker Swarm / Kubernetes

For production clusters, wrap the compose file as a stack:

```bash
# Docker Swarm
docker stack deploy -c docker-compose.yml machine-guru
```

---

## 4. Resource Tuning

### Jetson Orin Nano 8GB

```yaml
# docker-compose.yml overrides
services:
  backend:
    deploy:
      resources:
        limits:
          cpus: "2"
          memory: 3G
        reservations:
          cpus: "1"
          memory: 1G

  ollama:
    deploy:
      resources:
        limits:
          cpus: "2"
          memory: 4G
        reservations:
          cpus: "1"
          memory: 1G

  qdrant:
    deploy:
      resources:
        limits:
          cpus: "1"
          memory: 1G
```

### Jetson Orin Nano 16GB

```yaml
services:
  backend:
    deploy:
      resources:
        limits:
          memory: 4G

  ollama:
    deploy:
      resources:
        limits:
          memory: 8G
        environment:
          - OLLAMA_NUM_PARALLEL=4
```

---

## 5. Monitoring Stack

### Prometheus + Grafana Setup

Add to `docker-compose.yml`:

```yaml
services:
  prometheus:
    image: prom/prometheus:v2.53.0
    container_name: machine-guru-prometheus
    volumes:
      - ./deploy/prometheus:/etc/prometheus:ro
      - prometheus_data:/prometheus
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--storage.tsdb.retention.time=30d"
    ports:
      - "9090:9090"
    restart: unless-stopped
    networks:
      - machine-guru-network

  grafana:
    image: grafana/grafana:11.2.0
    container_name: machine-guru-grafana
    volumes:
      - ./deploy/grafana/datasources:/etc/grafana/provisioning/datasources:ro
      - ./deploy/grafana/dashboards:/etc/grafana/provisioning/dashboards:ro
      - grafana_data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=change-me
      - GF_INSTALL_PLUGINS=
    ports:
      - "3000:3000"
    restart: unless-stopped
    networks:
      - machine-guru-network

volumes:
  prometheus_data:
  grafana_data:
```

### Alerting Rules

Pre-configured alerts in `deploy/prometheus/alerts.yml`:

| Alert | Severity | Condition |
|-------|----------|-----------|
| BackendDown | Critical | Backend unreachable > 30s |
| HighErrorRate | Warning | 5xx rate > 0.05 req/s |
| HighMemoryUsage | Warning | RSS memory > 3GB |
| SlowQueries | Warning | P95 latency > 10s |
| LowCacheHitRate | Info | Cache hit rate < 10% |
| QdrantDown | Critical | Qdrant unreachable > 30s |
| HighGPUUsage | Warning | GPU util > 90% for 5m |

---

## 6. Backup and Restore

### Automated Backups

```bash
# Full backup (volumes + config + logs)
make backup

# Backup to specific directory
make backup-to DEST=/mnt/backups/$(date +%Y%m%d)

# Scheduled backup (crontab)
0 2 * * * cd /opt/machine-guru && make backup-to DEST=/mnt/backups/$(date +\%Y\%m\%d)
```

The backup includes:
- Qdrant vector database (full snapshot)
- Ollama model files
- Uploaded documents
- Environment configuration
- Docker compose files
- Recent container logs

### Restore

```bash
# Stop services
docker compose down

# Restore volumes from backup
docker run --rm \
  -v machine-guru-qdrant-storage:/target \
  -v $(pwd)/backups/machine-guru-backup-20260101:/backup \
  alpine:latest \
  tar xzf /backup/qdrant-storage.tar.gz -C /target

docker run --rm \
  -v machine-guru-ollama-models:/target \
  -v $(pwd)/backups/machine-guru-backup-20260101:/backup \
  alpine:latest \
  tar xzf /backup/ollama-models.tar.gz -C /target

# Restart services
docker compose up -d
```

---

## 7. Logging in Production

### Log Aggregation

With `JSON_LOGGING=true`, logs are structured for ingestion:

```json
{"timestamp": "2026-01-15T10:30:00Z", "level": "INFO", "message": "Query received", "request_id": "abc-123"}
```

### Log Shipping (Filebeat example)

```yaml
# filebeat.yml
filebeat.inputs:
  - type: container
    paths:
      - /var/lib/docker/containers/*/*.log
    processors:
      - add_docker_metadata: ~

output.elasticsearch:
  hosts: ["https://elasticsearch:9200"]
```

### Log Rotation

Already configured:
- 10 MB per file
- 30-day retention
- Gzip compression
- Daily rotation by date

---

## 8. Health Checks

### Docker Healthchecks

All services have built-in healthchecks:

| Service | Interval | Timeout | Start Period | Retries |
|---------|----------|---------|--------------|---------|
| Backend | 15s | 5s | 30s | 5 |
| Frontend | 15s | 5s | 10s | 3 |
| Qdrant | 10s | 5s | 5s | 5 |
| Ollama | 30s | 10s | 60s | 3 |

### Watchdog Script

For auto-recovery, run the watchdog:

```bash
# Run as systemd service
cat > /etc/systemd/system/machine-guru-watchdog.service << EOF
[Unit]
Description=MachineGuru Watchdog
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/opt/machine-guru/scripts/watchdog.sh --interval 30
WorkingDirectory=/opt/machine-guru
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now machine-guru-watchdog
```

---

## 9. Security Checklist

- [ ] `DEBUG=false` in production
- [ ] `CORS_ORIGINS` restricted to specific domains
- [ ] TLS termination with valid certificate
- [ ] Rate limiting enabled (nginx + application layer)
- [ ] Security headers configured (CSP, HSTS, X-Frame)
- [ ] Docker containers run as non-root user
- [ ] Secrets managed via environment (not hardcoded)
- [ ] Regular dependency audits (`pip-audit`, `npm audit`)
- [ ] Backup schedule configured and tested
- [ ] Monitoring alerts configured
- [ ] Log rotation and retention configured
- [ ] Docker daemon in `userns-remap` mode

---

## 10. Troubleshooting

| Problem | Solution |
|---------|----------|
| Backend won't start | Check `docker compose logs backend` for Python errors |
| GPU not available | Verify `nvidia-smi` output, check `runtime: nvidia` in compose |
| Ollama out of memory | Reduce `OLLAMA_NUM_PARALLEL`, lower model size |
| Qdrant connection refused | Check Qdrant health: `curl http://localhost:6333/healthz` |
| Slow queries | Check `/api/v1/stats` for cache hit rate, concurrency stats |
| Frontend blank page | Check nginx logs: `docker compose logs frontend` |
| Disk space low | Run `docker system prune -f` to clean unused data |
| High memory usage | Reduce `MEMORY_BUDGET_MB`, enable more aggressive GC |
