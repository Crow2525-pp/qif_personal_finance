.PHONY: help setup up down logs clean restart rebuild lint lint-fix test dagster-ui grafana-ui status dagster-run dbt-deps dbt-compile dbt-build dbt-test bootstrap-local-seeds bootstrap-worktree

WORKTREE_ENV_FILE = .env.worktree.auto
PYTHON ?= python
COMPOSE_PROJECT_NAME := $(shell $(PYTHON) scripts/write_worktree_compose_env.py --print-project-name)
COMPOSE = docker compose --project-name $(COMPOSE_PROJECT_NAME) --env-file .env --env-file $(WORKTREE_ENV_FILE) -f docker-compose.yml

compose-env:
	@$(PYTHON) scripts/write_worktree_compose_env.py --output $(WORKTREE_ENV_FILE)

bootstrap-local-seeds:
	@$(PYTHON) scripts/bootstrap_local_seeds.py

bootstrap-worktree: compose-env bootstrap-local-seeds

# Default target
help:
	@echo "Available commands:"
	@echo "  setup       - Copy .env.template to .env for configuration"
	@echo "  bootstrap-local-seeds - Sync private seed CSVs from the shared local seed store"
	@echo "  bootstrap-worktree - Generate worktree env and private seed files"
	@echo "  up          - Start all services with docker-compose"
	@echo "  down        - Stop all services"
	@echo "  logs        - Show logs from all services"
	@echo "  clean       - Clean up docker containers and volumes"
	@echo "  restart     - Restart all services"
	@echo "  rebuild     - Rebuild and restart all services"
	@echo "  lint        - Run SQL linting on dbt models"
	@echo "  lint-fix    - Run SQL linting with auto-fix"
	@echo "  dagster-ui  - Open Dagster UI in browser"
	@echo "  dagster-run - Run full Dagster pipeline job (preferred deploy path)"
	@echo "  grafana-ui  - Open Grafana UI in browser"
	@echo "  status      - Show status of all services"
	@echo "  ports       - Show the derived host ports for this worktree"
	@echo "  dbt-deps    - Install dbt packages"
	@echo "  dbt-compile - Compile dbt project (syntax check)"
	@echo "  dbt-build   - Break-glass: build dbt directly (requires ALLOW_DIRECT_DBT=1)"
	@echo "  dbt-test    - Break-glass: run dbt tests directly (requires ALLOW_DIRECT_DBT=1)"

# Setup environment
setup:
	@if [ ! -f .env ]; then \
		cp .env.template .env; \
		echo "Created .env file from .env.template"; \
		echo "Please edit .env with your credentials before running 'make up'"; \
	else \
		echo ".env file already exists"; \
	fi

# Start services
up: compose-env
	@if [ ! -f .env ]; then \
		cp .env.template .env; \
		echo "WARNING: .env not found — created from .env.template with placeholder values."; \
		echo "         Edit .env and replace CHANGE_ME_* values before services can start correctly."; \
	else \
		$(PYTHON) -c "\
import re, sys; \
t = open('.env.template').read(); env = open('.env').read(); \
keys = set(re.findall(r'^([A-Z][A-Z0-9_]*)=', env, re.M)); \
missing = [l for l in t.splitlines() if l and not l.startswith('#') and l.split('=')[0] not in keys]; \
print('\n'.join(missing)) if missing else None" > /tmp/_env_missing.txt; \
		if [ -s /tmp/_env_missing.txt ]; then \
			echo "# Added from .env.template" >> .env; \
			cat /tmp/_env_missing.txt >> .env; \
			echo "  INFO: Added missing keys from .env.template — check/update values in .env:"; \
			sed 's/=.*//' /tmp/_env_missing.txt | xargs -I{} echo "    {}"; \
		fi; \
		rm -f /tmp/_env_missing.txt; \
	fi
	$(COMPOSE) up -d
	@echo "Services starting..."
	@$(PYTHON) -c "from pathlib import Path; data = dict(line.split('=', 1) for line in Path('$(WORKTREE_ENV_FILE)').read_text().splitlines() if line and not line.startswith('#')); print(f\"Dagster UI will be available at http://localhost:{data['DAGSTER_UI_PORT']}\"); print(f\"Grafana UI will be available at http://localhost:{data['GRAFANA_HOST_PORT']}\")"

# Stop services
down:
	@$(MAKE) compose-env
	$(COMPOSE) down

# Show logs
logs:
	@$(MAKE) compose-env
	$(COMPOSE) logs -f

# Clean up
clean:
	@$(MAKE) compose-env
	$(COMPOSE) down -v --remove-orphans
	docker system prune -f

# Restart services
restart:
	@$(MAKE) compose-env
	$(COMPOSE) restart

# Rebuild and restart
rebuild: compose-env
	$(COMPOSE) down
	$(COMPOSE) build --no-cache
	$(COMPOSE) up -d

# SQL linting
lint:
	uv run sqlfluff lint pipeline_personal_finance/dbt_finance/models/

# SQL linting with auto-fix
lint-fix:
	uv run sqlfluff fix pipeline_personal_finance/dbt_finance/models/

# Open Dagster UI (works on macOS and Linux)
dagster-ui:
	@$(MAKE) compose-env
	@$(PYTHON) -c "from pathlib import Path; data = dict(line.split('=', 1) for line in Path('$(WORKTREE_ENV_FILE)').read_text().splitlines() if line and not line.startswith('#')); print(f\"http://localhost:{data['DAGSTER_UI_PORT']}\")" > /tmp/_dagster_url.txt
	@URL=$$(cat /tmp/_dagster_url.txt); \
	 which open >/dev/null 2>&1 && open $$URL || \
	 which xdg-open >/dev/null 2>&1 && xdg-open $$URL || \
	 echo "Please open $$URL in your browser"
	@rm -f /tmp/_dagster_url.txt

# Open Grafana UI (works on macOS and Linux)
grafana-ui:
	@$(MAKE) compose-env
	@$(PYTHON) -c "from pathlib import Path; data = dict(line.split('=', 1) for line in Path('$(WORKTREE_ENV_FILE)').read_text().splitlines() if line and not line.startswith('#')); print(f\"http://localhost:{data['GRAFANA_HOST_PORT']}\")" > /tmp/_grafana_url.txt
	@URL=$$(cat /tmp/_grafana_url.txt); \
	 which open >/dev/null 2>&1 && open $$URL || \
	 which xdg-open >/dev/null 2>&1 && xdg-open $$URL || \
	 echo "Please open $$URL in your browser"
	@rm -f /tmp/_grafana_url.txt

# Preferred deployment path: run through Dagster so lineage/ordering/checks are preserved
dagster-run:
	@$(MAKE) compose-env
	$(COMPOSE) exec pipeline_personal_finance dagster job execute -m pipeline_personal_finance -j qif_pipeline_job

# Show service status
status:
	@$(MAKE) compose-env
	$(COMPOSE) ps

ports: compose-env
	@$(PYTHON) -c "from pathlib import Path; print(Path('$(WORKTREE_ENV_FILE)').read_text())"

# dbt helpers (run from finance dbt dir)
dbt-deps:
	cd pipeline_personal_finance/dbt_finance && DBT_PROFILES_DIR=. dbt deps

dbt-compile:
	cd pipeline_personal_finance/dbt_finance && DBT_PROFILES_DIR=. dbt compile

dbt-build:
	@if [ "$(ALLOW_DIRECT_DBT)" != "1" ]; then \
		echo "Direct dbt build is blocked by default."; \
		echo "Use 'make dagster-run' for normal deployments."; \
		echo "Break-glass only: ALLOW_DIRECT_DBT=1 make dbt-build"; \
		exit 1; \
	fi
	cd pipeline_personal_finance/dbt_finance && DBT_PROFILES_DIR=. dbt build

dbt-test:
	@if [ "$(ALLOW_DIRECT_DBT)" != "1" ]; then \
		echo "Direct dbt test is blocked by default."; \
		echo "Use 'make dagster-run' for normal deployments."; \
		echo "Break-glass only: ALLOW_DIRECT_DBT=1 make dbt-test"; \
		exit 1; \
	fi
	cd pipeline_personal_finance/dbt_finance && DBT_PROFILES_DIR=. dbt test
