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

## Classification Strategy Options (Hands-Free Focus)
Goal: minimize manual rules while still yielding stable, explainable categories for dbt + dashboards.

1. Rule-first + fallback ML-lite (recommended start)
   - Deterministic rules for high-signal types: transfers, payroll/wages, mortgage/loan payments, interest, fees.
   - Use memo/merchant pattern libraries + account-type hints (loan vs credit vs depository).
   - Add a fallback “unknown” bucket to avoid empty panels.
   - Pros: explainable, stable, easy to test. Cons: requires upkeep of pattern lists.

2. Table-driven mapping (seed-based)
   - Create a `transaction_type_map` seed with pattern -> type (regex/LIKE).
   - Add priority + scope columns (account type, bank, sign) to avoid over-matching.
   - Pros: editable without code; easy to extend. Cons: still a rule system.

3. Heuristic clustering + label propagation
   - Group transactions by merchant + memo similarity + amount periodicity.
   - Infer “payroll” by cadence + positive inflow; “mortgage” by recurring large outflow to same payee; “interest received” by small inflows with “interest” or bank memo patterns.
   - Pros: more automatic; adapts to new merchants. Cons: more complex; risk of mislabels.

4. External classifier (optional later)
   - Use a lightweight classifier (e.g., local model) trained on labeled history.
   - Feed merchant/memo/amount/cadence features.
   - Pros: most hands-free once trained. Cons: ops overhead + model drift.

Recommendation: start with option 1 + option 2 (rule-first + mapping seed), then evaluate adding heuristic clustering for “new merchant” coverage.

## Advisory Clustering Add-On (Personalized, Low-Risk)
Goal: keep personalized rules authoritative while using clustering to suggest new mappings.

Proposed flow:
1. Normalize transactions (strip refs, card numbers, dates; standardize merchant tokens).
2. Run clustering on normalized merchant + amount + cadence features.
3. Output “suggested clusters” and candidate labels (advisory only).
4. Promote accepted suggestions into a user-owned mapping seed (not committed to repo by default).

Personalization strategy:
- Store user mappings in a local seed or config file (ignored by git), with a template example in repo.
- Provide a starter mapping template + docs so new users can copy and customize quickly.
- Keep the core repo bank-agnostic by shipping only generic defaults.

## Work Breakdown (Draft)
1. Create fake QIF files in `pipeline_personal_finance/qif_files/` and document their structure.
2. Add or update a mapping source for bank/account normalization.
3. Add generalized classification macros or mapping seeds for mortgage/interest logic.
4. Update dbt models to use the generalized mapping logic.
5. Update Grafana SQL panels that rely on hard-coded category labels.
6. Add Dagster run configuration or environment variable usage for bank/context.
7. Validate the full pipeline and capture evidence.
8. (Optional) Add clustering script that writes advisory suggestions into a local-only artifact.

## Acceptance Criteria
1. Fake QIF files ingest successfully and produce deterministic dbt outputs.
2. dbt + Grafana queries do not rely on bank-name constants.
3. Category logic for mortgage/interest is generalized and maintainable.
4. The pipeline can be run using Dagster config/env vars without manual edits.

## Open Questions
1. Where should bank/account mapping live: dbt seed vs. Dagster config vs. code constants?
2. Should classification rules be macro-based (SQL) or table-driven (seed)?
3. Which dashboards are most sensitive to broadened category matching (e.g., wages, interest received, shares)?
4. Do we want to track confidence/“auto vs manual” flags for classification?
5. Should clustering outputs be stored as a local report or a seed file that users selectively import?
