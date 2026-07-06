.PHONY: build build-no-cache up down restart logs ps shell models models-list
.PHONY: test test-backend test-backend-coverage test-frontend lint
.PHONY: dev-backend dev-frontend clean health
.PHONY: offline-save offline-load
.PHONY: backup restore monitor monitor-logs monitor-stats
.PHONY: security-audit deps-audit prune
.PHONY: help

# ─── Docker Lifecycle ───────────────────────────────────────────

build:
	docker compose build

build-no-cache:
	docker compose build --no-cache

up:
	docker compose up -d

down:
	docker compose down

restart: down up

logs:
	docker compose logs -f

logs-backend:
	docker compose logs -f backend

ps:
	docker compose ps

shell:
	docker compose exec backend python3

# ─── Model Setup ────────────────────────────────────────────────

models:
	docker exec machine-guru-ollama ollama pull llama3.2:1b
	docker exec machine-guru-ollama ollama pull multilingual-e5-small

models-list:
	docker exec machine-guru-ollama ollama list

# ─── Testing ────────────────────────────────────────────────────

test-backend:
	cd backend && python3 -m pytest -v

test-backend-coverage:
	cd backend && python3 -m pytest -v --cov=. --cov-report=term-missing

test-frontend:
	cd frontend && npx tsc --noEmit

test: test-backend test-frontend

lint:
	cd backend && python3 -m flake8 . 2>/dev/null || echo "flake8 not installed"
	cd backend && python3 -m mypy . 2>/dev/null || echo "mypy not installed"
	cd frontend && npx tsc --noEmit

# ─── Development ────────────────────────────────────────────────

dev-backend:
	cd backend && uvicorn main:app --reload --host 0.0.0.0 --port 8000

dev-frontend:
	cd frontend && npm run dev

# ─── Monitoring ─────────────────────────────────────────────────

health:
	@echo "=== Backend ==="; curl -s http://localhost:8000/api/v1/health | python3 -m json.tool
	@echo ""
	@echo "=== Stats ==="; curl -s http://localhost:8000/api/v1/stats | python3 -m json.tool
	@echo ""
	@echo "=== Metrics (top 20) ==="; curl -s http://localhost:8000/metrics | head -20

health-check:
	./scripts/healthcheck.sh

health-check-all:
	./scripts/healthcheck.sh all

monitor:
	watch -n 5 'curl -s http://localhost:8000/api/v1/health | python3 -m json.tool'

monitor-logs:
	docker compose logs -f --tail=50

monitor-stats:
	watch -n 5 'curl -s http://localhost:8000/api/v1/stats | python3 -m json.tool'

# ─── Prometheus Metrics ─────────────────────────────────────────

metrics:
	curl -s http://localhost:8000/metrics | head -40

metrics-all:
	curl -s http://localhost:8000/metrics

# ─── Backup & Restore ───────────────────────────────────────────

backup:
	./scripts/backup.sh

backup-to:
	./scripts/backup.sh $(DEST)

restore:
	@echo "Manual restore required — see docs/DEPLOYMENT.md#backup-and-restore"

# ─── Offline Export ────────────────────────────────────────────

offline-save:
	mkdir -p offline
	docker save qdrant/qdrant:v1.13.2 -o offline/qdrant.tar
	docker save ollama/ollama:0.4.7 -o offline/ollama.tar
	docker save machine-guru-backend:latest -o offline/backend.tar
	docker save machine-guru-frontend:latest -o offline/frontend.tar
	@echo "Images saved to offline/"

offline-load:
	docker load -i offline/qdrant.tar
	docker load -i offline/ollama.tar
	docker load -i offline/backend.tar
	docker load -i offline/frontend.tar
	@echo "Images loaded from offline/"

# ─── Security & Maintenance ────────────────────────────────────

security-audit:
	cd backend && pip-audit 2>/dev/null || echo "pip-audit not installed (run: pip install pip-audit)"
	cd frontend && npm audit 2>/dev/null || echo "npm audit completed"

deps-audit: security-audit

prune:
	docker system prune -f --volumes
	docker builder prune -f

# ─── Cleanup ────────────────────────────────────────────────────

clean:
	docker compose down -v
	docker system prune -f
	rm -rf backend/__pycache__ backend/**/__pycache__
	rm -rf frontend/dist frontend/.vite
	rm -rf logs/ uploads/
	rm -rf .pytest_cache
	rm -rf backups/

clean-all: clean
	docker system prune -af --volumes
	rm -rf offline/

# ─── Help ───────────────────────────────────────────────────────

help:
	@echo "MachineGuru — Production Management"
	@echo ""
	@echo "Docker Lifecycle:"
	@echo "  build              Build Docker images"
	@echo "  build-no-cache     Build with no cache"
	@echo "  up                 Start all services"
	@echo "  down               Stop all services"
	@echo "  restart            Restart all services"
	@echo "  logs               Tail all container logs"
	@echo "  logs-backend       Tail backend logs only"
	@echo "  ps                 List running containers"
	@echo "  shell              Open Python shell in backend"
	@echo ""
	@echo "Models:"
	@echo "  models             Pull AI models into Ollama"
	@echo "  models-list        List loaded models"
	@echo ""
	@echo "Testing:"
	@echo "  test               Run all tests"
	@echo "  test-backend       Run backend pytest"
	@echo "  test-frontend      Type-check frontend"
	@echo "  lint               Run linters"
	@echo ""
	@echo "Development:"
	@echo "  dev-backend        Start backend in dev mode"
	@echo "  dev-frontend       Start frontend in dev mode"
	@echo ""
	@echo "Monitoring:"
	@echo "  health             Check service health and stats"
	@echo "  health-check       Run health check script"
	@echo "  monitor            Watch health in real-time"
	@echo "  monitor-logs       Tail logs"
	@echo "  monitor-stats      Watch stats in real-time"
	@echo "  metrics            View Prometheus metrics"
	@echo ""
	@echo "Backup & Offline:"
	@echo "  backup             Backup volumes and config"
	@echo "  backup-to DEST=    Backup to specific directory"
	@echo "  offline-save       Export Docker images for air-gap"
	@echo "  offline-load       Import Docker images"
	@echo ""
	@echo "Security:"
	@echo "  security-audit     Run pip-audit and npm audit"
	@echo "  prune              Clean unused Docker data"
	@echo "  clean              Remove containers, volumes, caches"
	@echo "  clean-all          Complete system cleanup"
