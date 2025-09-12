# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a personal finance data pipeline that processes QIF (Quicken Interchange Format) bank transaction files and displays financial insights through Grafana dashboards. The system runs on a home server and provides financial visualization for household budgeting.

**Tech Stack**: Dagster (orchestration), dbt (transformations), PostgreSQL (storage), Docker Compose (deployment), Python with UV workspace management.

## Development Commands

### Setup and Run
```bash
# Copy environment file and configure credentials
cp sample.env .env  # Edit with your database credentials

# Start all services
docker-compose up -d

# Access Dagster UI
# Navigate to http://localhost:3000
```

### Development Workflow
1. Place QIF files in `pipeline_personal_finance/qif_files/`
2. Access Dagster UI at localhost:3000
3. Reload definitions in Dagster UI
4. Run the asset pipeline
5. View results in Grafana dashboards

### Database Access
- PostgreSQL runs on port 5432
- Connection details in `.env` file
- Database: `personal_finance`
- Schemas: `landing`, `staging`, `transformation`, `reporting`

### Code Quality
```bash
# SQL linting (available via dev dependencies)
uv run sqlfluff lint pipeline_personal_finance/dbt_finance/models/
uv run sqlfluff fix pipeline_personal_finance/dbt_finance/models/
```

## Architecture

### Data Flow
1. **Landing Zone**: QIF files → PostgreSQL `landing` schema (raw ingestion via Dagster)
2. **Staging Layer**: Clean and standardize data (`staging` schema via dbt)  
3. **Transformation Layer**: Business logic, categorization, balance adjustments (`transformation` schema)
4. **Reporting Layer**: Fact tables and visualization views (`reporting` schema)

### Project Structure
```
dagster_core/                    # Orchestration layer
pipeline_personal_finance/       # Main pipeline
  ├── dbt_finance/              # Data transformations
  │   ├── models/staging/       # Raw data staging
  │   ├── models/transformation/# Business logic
  │   ├── models/reporting/     # Final reporting models
  │   ├── macros/               # Custom dbt macros
  │   ├── seeds/                # Reference data (categories)
  │   └── snapshots/            # SCD tracking
  └── qif_files/                # Source transaction files
```

### Bank Integration
- Supports Australian banks: Adelaide Bank, Bendigo Bank, ING
- QIF file naming: `BankName_AccountName_Transactions_YYYYMMDD.qif`
- Automatic duplicate detection and incremental processing

## dbt Configuration

### Materializations
- **Staging**: Tables in `staging` schema
- **Transformation**: Tables in `transformation` schema  
- **Reporting**: Tables in `reporting` schema

### Key Models
- Bank-specific staging models for each account type
- Balance adjustment and account consolidation logic
- Transaction categorization using seed data
- Visualization-ready fact tables

### Running dbt Commands
dbt commands should be executed within the containerized environment or by accessing the running `pipeline_personal_finance` container.

## Environment Configuration

### Required Environment Variables
- `DAGSTER_POSTGRES_HOST/USER/PASSWORD/PORT/DB`: Database connection
- `DAGSTER_DEPLOYMENT`: Set to `prod` or `dev`
- `TIMEZONE`: Australia/Melbourne
- `GRAFANA_USER/PASSWORD`: Reader access for dashboards

### Deployment Environments
- **Production**: Full Docker Compose stack with persistent volumes
- **Development**: Uses same containers with code volume mounts for live development

## Database Schemas

- **landing**: Raw QIF file ingestion
- **staging**: Cleaned and standardized bank data
- **transformation**: Business logic applied (categorization, balance adjustments)
- **reporting**: Final models for visualization

## Testing

Test files located in `dagster_finance_tests/` directory. Testing infrastructure is minimal and requires expansion for comprehensive coverage.