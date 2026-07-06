#!/usr/bin/env bash
set -euo pipefail

# MachineGuru Backup Script
# Backs up Docker volumes and configuration
#
# Usage: ./scripts/backup.sh [destination]
#   destination: Backup directory (default: ./backups)

BACKUP_DIR="${1:-./backups}"
TIMESTAMP
TIMESTAMP=$(date -u +"%Y%m%d_%H%M%S")
BACKUP_PATH="$BACKUP_DIR/machine-guru-backup-$TIMESTAMP"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
COMPOSE_FILE="${BACKUP_COMPOSE:-docker-compose.yml}"

log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"
}

mkdir -p "$BACKUP_PATH"
log "Starting backup to $BACKUP_PATH"

# Backup Qdrant data
log "Backing up Qdrant storage..."
if docker ps --format '{{.Names}}' | grep -q "machine-guru-qdrant"; then
    docker run --rm \
        -v machine-guru-qdrant-storage:/source:ro \
        -v "$(pwd)/$BACKUP_PATH:/backup" \
        alpine:latest \
        tar czf /backup/qdrant-storage.tar.gz -C /source . 2>&1
    log "  Qdrant backup complete"
else
    log "  WARN: Qdrant container not running, skipping"
fi

# Backup Ollama models
log "Backing up Ollama models..."
if docker ps --format '{{.Names}}' | grep -q "machine-guru-ollama"; then
    docker run --rm \
        -v machine-guru-ollama-models:/source:ro \
        -v "$(pwd)/$BACKUP_PATH:/backup" \
        alpine:latest \
        tar czf /backup/ollama-models.tar.gz -C /source . 2>&1
    log "  Ollama backup complete"
else
    log "  WARN: Ollama container not running, skipping"
fi

# Backup uploads
log "Backing up uploads..."
if docker ps --format '{{.Names}}' | grep -q "machine-guru-backend"; then
    docker run --rm \
        -v machine-guru-uploads:/source:ro \
        -v "$(pwd)/$BACKUP_PATH:/backup" \
        alpine:latest \
        tar czf /backup/uploads.tar.gz -C /source . 2>&1
    log "  Uploads backup complete"
else
    log "  WARN: Backend container not running, skipping"
fi

# Backup configuration files
log "Backing up configuration..."
tar czf "$BACKUP_PATH/config.tar.gz" \
    -C "$(pwd)" \
    .env.example \
    docker-compose.yml \
    Makefile \
    deploy/ \
    scripts/ \
    2>/dev/null || true
log "  Config backup complete"

# Backup docker-compose environment
if [ -f .env ]; then
    cp .env "$BACKUP_PATH/.env.backup"
    log "  .env file backed up (redact secrets before storing)"
fi

# Save container logs
log "Saving recent container logs..."
for svc in backend frontend qdrant ollama; do
    docker compose logs --tail=500 "$svc" > "$BACKUP_PATH/logs-$svc.txt" 2>/dev/null || true
done

# Generate backup manifest
cat > "$BACKUP_PATH/MANIFEST.txt" << EOF
MachineGuru Backup
==================
Date: $(date -u)
Timestamp: $TIMESTAMP
Components:
  - Qdrant storage (machine-guru-qdrant-storage)
  - Ollama models (machine-guru-ollama-models)
  - Uploads (machine-guru-uploads)
  - Environment configuration
  - Docker compose configuration
  - Container logs (last 500 lines each)
EOF

log "Backup complete: $BACKUP_PATH"

# Calculate size
SIZE
SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
log "Backup size: $SIZE"

# Retention: remove backups older than N days
log "Cleaning backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "machine-guru-backup-*" -type d -mtime "+$RETENTION_DAYS" -exec rm -rf {} \; 2>/dev/null || true
log "Retention cleanup complete"

# Print summary
echo ""
echo "=== Backup Summary ==="
echo "  Location: $BACKUP_PATH"
echo "  Size:     $SIZE"
echo "  Contents:"
ls -lh "$BACKUP_PATH/"*.tar.gz "$BACKUP_PATH/"*.txt 2>/dev/null | sed 's/^/    /'
echo "========================"
