.PHONY: help setup up down logs clean restart rebuild lint lint-fix test dagster-ui grafana-ui status dbt-deps dbt-compile dbt-build dbt-test

# Default target
help:
	@echo "Available commands:"
	@echo "  setup       - Copy sample.env to .env for configuration"
	@echo "  up          - Start all services with docker-compose"
	@echo "  down        - Stop all services"
	@echo "  logs        - Show logs from all services"
	@echo "  clean       - Clean up docker containers and volumes"
	@echo "  restart     - Restart all services"
	@echo "  rebuild     - Rebuild and restart all services"
	@echo "  lint        - Run SQL linting on dbt models"
	@echo "  lint-fix    - Run SQL linting with auto-fix"
	@echo "  dagster-ui  - Open Dagster UI in browser"
	@echo "  grafana-ui  - Open Grafana UI in browser"
	@echo "  status      - Show status of all services"
	@echo "  dbt-deps    - Install dbt packages"
	@echo "  dbt-compile - Compile dbt project (syntax check)"
	@echo "  dbt-build   - Build dbt models (incl. tests)"
	@echo "  dbt-test    - Run dbt tests only"

# Setup environment
setup:
	@if [ ! -f .env ]; then \
		cp sample.env .env; \
		echo "Created .env file from sample.env"; \
		echo "Please edit .env with your credentials before running 'make up'"; \
	else \
		echo ".env file already exists"; \
	fi

# Start services
up:
	docker-compose up -d
	@echo "Services starting..."
	@echo "Dagster UI will be available at http://localhost:3000"
	@echo "Grafana UI will be available at http://localhost:3001"

# Stop services
down:
	docker-compose down

# Show logs
logs:
	docker-compose logs -f

# Clean up
clean:
	docker-compose down -v --remove-orphans
	docker system prune -f

# Restart services
restart:
	docker-compose restart

# Rebuild and restart
rebuild:
	docker-compose down
	docker-compose build --no-cache
	docker-compose up -d

# SQL linting
lint:
	uv run sqlfluff lint pipeline_personal_finance/dbt_finance/models/

# SQL linting with auto-fix
lint-fix:
	uv run sqlfluff fix pipeline_personal_finance/dbt_finance/models/

# Open Dagster UI (works on macOS and Linux)
dagster-ui:
	@which open >/dev/null 2>&1 && open http://localhost:3000 || \
	 which xdg-open >/dev/null 2>&1 && xdg-open http://localhost:3000 || \
	 echo "Please open http://localhost:3000 in your browser"

# Open Grafana UI (works on macOS and Linux)
grafana-ui:
	@which open >/dev/null 2>&1 && open http://localhost:3001 || \
	 which xdg-open >/dev/null 2>&1 && xdg-open http://localhost:3001 || \
	 echo "Please open http://localhost:3001 in your browser"

# Show service status
status:
	docker-compose ps

# dbt helpers (run from finance dbt dir)
dbt-deps:
	cd pipeline_personal_finance/dbt_finance && DBT_PROFILES_DIR=. dbt deps

dbt-compile:
	cd pipeline_personal_finance/dbt_finance && DBT_PROFILES_DIR=. dbt compile

dbt-build:
	cd pipeline_personal_finance/dbt_finance && DBT_PROFILES_DIR=. dbt build

dbt-test:
	cd pipeline_personal_finance/dbt_finance && DBT_PROFILES_DIR=. dbt test
