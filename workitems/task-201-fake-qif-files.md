# Task 201 Plan: Fake QIF Files + Bank-Agnostic Pipeline

Branch: task-201-fake-qif-files
Plan revision: 2026-02-24

## Objective
Create a set of fake QIF files that run end-to-end through Dagster + dbt without requiring bank-specific hard-coded values, while keeping Grafana functional once the data lands.

## Problem Statement
The current pipeline expects bank-name-specific QIF sources and hard-coded category labels (notably "mortgage" and "interest"). This makes synthetic/test data brittle and can break dbt/Grafana when bank naming or memo patterns differ.

## Scope
- Fake QIF file generation (representative accounts + transactions).
- Bank name agnostic ingestion and transformations.
- Replace hard-coded category strings ("mortgage", "interest") with generalized classification logic.
- Introduce a Dagster-run variable or env-var bridge for bank/context values when required.
- Ensure dbt models and Grafana queries do not depend on bank-specific constants.

## Non-Goals
- Redesign of existing dashboards beyond what is needed to remove hard-coded assumptions.
- Full-scale data quality or categorization overhaul unrelated to QIF inputs.

## Key Risks / Constraints
1. dbt models and Grafana dashboards currently expect specific labels or bank names; loosening these could surface nulls or empty panels.
2. Removing hard-coded category filters may change metric definitions; must preserve intent while broadening matching.
3. Introducing new Dagster variables may require updates to local/dev and production env configs.

## Proposed Approach
1. Inventory current dependencies:
   - Identify all uses of bank names, account names, or QIF file naming assumptions in ingestion + dbt models.
   - Locate "mortgage" and "interest" hard-coded filters in dbt + Grafana SQL.
2. Define the fake QIF dataset:
   - Minimal set of QIF files to cover checking, savings, credit card, loan.
   - Include realistic transaction mix: income, transfers, recurring bills, mortgage, interest, fees, groceries, etc.
   - Use neutral bank/account identifiers so parsing does not rely on specific names.
3. Implement bank-agnostic ingestion:
   - Normalize bank/account naming during ingestion (e.g., derived from QIF metadata or filename with fallback).
   - Add a deterministic mapping layer (configurable) for account type classification.
4. Generalize category logic:
   - Replace string equals ("mortgage", "interest") with pattern-based or category-group rules.
   - Introduce macros or mapping tables so classification rules live in a single place.
5. Add a Dagster run variable / env bridge:
   - Define a run config variable (e.g., `BANK_CONTEXT` or `ACCOUNT_CLASS_MAP`).
   - Pass through to dbt as vars/env vars so models can resolve defaults safely.
6. Stabilize dbt + Grafana outputs:
   - Update dbt models to avoid null outputs when expected categories are missing.
   - Adjust Grafana queries to use generalized categories or join to mapping tables.
7. Validation:
   - Run Dagster job end-to-end with fake QIF files.
   - Run `dbt build` and confirm key models and dashboards return rows.

## Work Breakdown (Draft)
1. Create fake QIF files in `pipeline_personal_finance/qif_files/` and document their structure.
2. Add or update a mapping source for bank/account normalization.
3. Add generalized classification macros or mapping seeds for mortgage/interest logic.
4. Update dbt models to use the generalized mapping logic.
5. Update Grafana SQL panels that rely on hard-coded category labels.
6. Add Dagster run configuration or environment variable usage for bank/context.
7. Validate the full pipeline and capture evidence.

## Acceptance Criteria
1. Fake QIF files ingest successfully and produce deterministic dbt outputs.
2. dbt + Grafana queries do not rely on bank-name constants.
3. Category logic for mortgage/interest is generalized and maintainable.
4. The pipeline can be run using Dagster config/env vars without manual edits.

## Open Questions
1. Where should bank/account mapping live: dbt seed vs. Dagster config vs. code constants?
2. Should classification rules be macro-based (SQL) or table-driven (seed)?
3. Which dashboards are most sensitive to the mortgage/interest categorization change?
