# Task 110 Plan: Global Custom Time Window Standardization + Dagster Gate

Related kickoff: `workitems/task-110-kickoff.md` (policy update captured here)  
Branch target: `feat/task-110-native-timepicker-unification`  
Plan revision: 2026-02-24 (rev 2 — JSON linter layer, native-picker rationale, gate rollout)

## Objective
Create one enforceable dashboard time-control standard across the Grafana suite:
1. Non-exception dashboards must use the same custom `time_window` dropdown.
2. Exception dashboards (time-specific or forward-looking) must be explicitly tagged.
3. A Dagster gate must fail the pipeline when policy violations are introduced.
4. Dashboards with future components must be handled explicitly as exception classes, not implicitly.
5. Time-control policy enforcement is implemented as a separate Dagster asset (not merged into existing QA lint logic).

## Why Custom Dropdown, Not Native Grafana Time Picker

The kickoff is titled "Native Time Picker Unification" but the implementation standard adopted here is the custom `time_window` dropdown. This decision is intentional and worth stating explicitly.

The native Grafana time picker operates on wall-clock ranges (e.g. "last 30 days") which do not align with completed-month semantics. Selecting "last 30 days" on the 5th of a month returns a partially-complete month, making metrics non-deterministic. The `time_window` dropdown offers exactly three options — `latest_month`, `ytd`, `trailing_12m` — each of which resolves to hard month boundaries in SQL. This makes every metric reproducible regardless of when the dashboard is opened.

The native picker is therefore left visible (not hidden) on all dashboards so users can still scrub for ad-hoc exploration, but it is not the authoritative time-control mechanism and is not enforced by policy.

## Non-Goals
1. Rewriting business metric formulas unrelated to time-window semantics.
2. Redesigning dashboard UX beyond time-control normalization and required labels.
3. Broad refactor of unrelated variables (except where they conflict with time controls).

## Canonical Time-Control Contract

### 1) Canonical custom variable (source baseline: `savings-analysis-dashboard.json`)
Required variable definition for non-exception dashboards:
1. `name`: `time_window`
2. `type`: `custom`
3. `query`: `latest_month,ytd,trailing_12m`
4. `options` values (exact):
   - `latest_month`
   - `ytd`
   - `trailing_12m`
5. `multi=false`, `includeAll=false`, `skipUrlSync=false`
6. Default current value: `latest_month`

Display labels:
1. Migration target label set:
   - `Last Complete Month`
   - `Year to Date`
   - `Trailing 12 Months`
2. Backward-compatibility note: existing dashboards may still show `Latest Month`; migration normalizes this to `Last Complete Month`.

### 2) SQL window contract
All non-exception dashboards must derive period bounds from `time_window` via a shared pattern:
1. `latest_month`: last completed month
2. `ytd`: first day of year through latest completed month end
3. `trailing_12m`: 12 completed months ending latest completed month

Monthly datasets must normalize to month boundaries (start-of-month to month-end) so selections are deterministic.

### 3) Link contract
For non-exception dashboards:
1. Always forward `var-time_window=${time_window}`.
2. Do not forward `var-dashboard_period`.
3. Preserve non-date drilldown variables where needed.

## Temporal Archetypes (Past / Atemporal / Future)
Every dashboard must be classified into one archetype for gate enforcement.

1. `historical_windowed` (default):
   - Uses canonical `time_window`.
   - No exception tags.
2. `historical_fixed_period`:
   - Time-specific historical dashboard where canonical `time_window` is not appropriate.
   - Must use `time_control:time_specific_exception`.
3. `atemporal_no_time_component`:
   - Dashboard has no meaningful time component (navigation shell or static/meta view).
   - Must use `time_control:no_time_component_exception`.
4. `forward_looking`:
   - Dashboard primarily modeling or projecting into future periods.
   - Must use `time_control:forward_looking_exception`.
5. `hybrid_past_future`:
   - Dashboard combines historical context with future projections in the same surface.
   - Must use `time_control:hybrid_future_component_exception`.

Future-component rule:
1. Any dashboard that displays projected future periods is `forward_looking` or `hybrid_past_future`.
2. These dashboards are exempt from canonical `time_window` strictness, but must carry explicit exception tags and reason tags.
3. If a hybrid dashboard deep-links into standard historical dashboards, it must provide a deterministic fallback `var-time_window` value when applicable (default: `latest_month`).

Atemporal link-forwarding rule:
1. `atemporal_no_time_component` dashboards (e.g. navigation shells) have no time variable of their own.
2. If an atemporal dashboard contains links to `historical_windowed` dashboards, those links must hard-code a fallback `var-time_window=latest_month` rather than forwarding a variable that doesn't exist.
3. This ensures that clicking through from an atemporal dashboard lands on a deterministic time window, not a broken/empty filter.

## Rollout Metadata (No Hard-Coded Tranche Lists)
Tranche A/B membership is defined by dashboard tags, not hard-coded UID/file arrays in scripts.

Required rollout tags for in-scope dashboards:
1. Exactly one rollout tag:
   - `time_control_rollout:tranche_a`
   - `time_control_rollout:tranche_b`
2. Exactly one archetype tag:
   - `time_control_archetype:historical_windowed`
   - `time_control_archetype:historical_fixed_period`
   - `time_control_archetype:atemporal_no_time_component`
   - `time_control_archetype:forward_looking`
   - `time_control_archetype:hybrid_past_future`

Implementation rule:
1. Checker and Dagster gate derive tranche scope dynamically from tags.
2. Enforcement logic must not hard-code dashboard UIDs/filenames for tranche membership.
3. `workitems/task-110-time-control-register.md` remains a reporting artifact, not a runtime enforcement source.

## Exception Policy

### Exception types
1. `time_specific`: dashboard intentionally fixed to a non-windowed period semantics.
2. `no_time_component`: dashboard intentionally has no time control semantics.
3. `forward_looking`: dashboard primarily forecast/projection driven.
4. `hybrid_future_component`: dashboard mixes historical and projected periods.

### Required tags on exception dashboards
1. One required class tag:
   - `time_control:time_specific_exception`
   - `time_control:no_time_component_exception`
   - `time_control:forward_looking_exception`
   - `time_control:hybrid_future_component_exception`
2. `time_control_reason:<short_reason>`

### Initial exception candidates (to confirm in Phase 1)
1. `financial_projections` (forward_looking)
2. `projections-analysis-mobile` (forward_looking)
3. `mortgage-payoff` (hybrid_past_future or forward_looking)
4. `year_over_year_comparison` (historical_fixed_period)
5. `four_year_financial_comparison` (historical_fixed_period)
6. `financial-review-command-center` (atemporal_no_time_component candidate)

## Current-State Baseline (from scan)
Dashboard inventory: 24 JSON dashboards under `grafana/provisioning/dashboards`.

1. Uses `time_window` + `dashboard_period`:
   - `executive_dashboard`
2. Uses `time_window` only:
   - `account_performance_dashboard`
   - `cash_flow_analysis`
   - `expense_performance`
   - `household_net_worth`
   - `monthly_budget_summary`
   - `outflows_reconciliation`
   - `savings_analysis`
   - `transaction_analysis_dashboard`
3. No `time_window` currently:
   - remaining dashboards (including mobile suite, comparison dashboards, projections)

## Detailed Work Plan

### Phase 0: Pre-Flight and Baseline Artifacts
1. Freeze baseline evidence before edits:
   - `rg` inventory for `time_window`, `dashboard_period`, `var-time_window`, `var-dashboard_period` across dashboard JSON files.
   - `rg` inventory for `dashboard_period` in `pipeline_personal_finance/dbt_finance/models/` to identify any dbt SQL that references the variable and will need updating in Phase 3.
   - Run JSON linter (see Phase 0.5) to identify any unparseable files and fix them before other checks run.
   - baseline lint result: `python scripts/check_grafana_dashboards.py --lint-only` (after JSON is clean).
2. Create tracking artifact:
   - `workitems/task-110-time-control-register.md` with columns:
     `dashboard_uid`, `classification`, `status`, `notes`.
3. Record baseline dashboard counts:
   - compliant
   - non-compliant
   - exception-tagged

Known pre-existing JSON defects to fix in this phase:
- `outflows-insights-dashboard.json`: invalid control character at line 1215.
- `transaction-analysis-dashboard.json`: invalid control character at line 812.
These must be resolved before any downstream checker can run.

Deliverable:
1. Clean JSON across all 24 dashboards confirmed.
2. Baseline report committed in `workitems/`.

### Phase 0.5: JSON Linter (Upstream Gate for All Checkers)

All subsequent checker scripts depend on valid, parseable JSON. A dedicated linter runs first and blocks downstream checks if any file fails to parse.

#### Checker dependency chain

```
scripts/validate_dashboard_json.py        ← new, upstream
        ↓ (must exit 0 before these run)
scripts/check_grafana_dashboards.py       ← existing, unchanged
scripts/check_dashboard_time_control_policy.py  ← new (Phase 1)
```

In Dagster the same dependency is expressed as assets:

```
dashboard_json_lint_gate                  ← new upstream asset
        ↓
dashboard_qa_lint_gate                    ← existing asset (no behavior change)
dashboard_time_control_policy_gate        ← new asset (Phase 2)
```

#### `scripts/validate_dashboard_json.py` specification

Responsibilities:
1. Attempt `json.load()` on every `.json` file under `grafana/provisioning/dashboards`.
2. Collect all files that raise `json.JSONDecodeError`, reporting filename, line, and column.
3. Emit a human-readable summary and optionally `--json` machine output.
4. Exit codes:
   - `0` all files parse cleanly
   - `1` one or more files failed to parse
   - `2` directory not found or runtime error

CLI flags:
1. `--dashboard-dir` (default: `grafana/provisioning/dashboards`)
2. `--json`

The script has no policy logic — it only validates parseability. Policy logic lives in the downstream checkers.

Deliverable:
1. `scripts/validate_dashboard_json.py` with README entry.
2. All 24 dashboards pass the linter.

### Phase 1: Policy Checker Script (Single Source Of Truth)
Add a dedicated policy validator script. Assumes upstream JSON linter has already passed.

Implementation target:
1. New file: `scripts/check_dashboard_time_control_policy.py`
2. Docs update: `scripts/README.md`

Checker responsibilities:
1. Parse every dashboard JSON under `grafana/provisioning/dashboards` (JSON validity guaranteed by upstream linter).
2. Match dashboards by `uid` field, not filename.
3. Identify exception dashboards by required tags.
4. Identify rollout tranche membership via `time_control_rollout:*` tags.
5. For non-exception dashboards, enforce:
   - canonical `time_window` presence and shape
   - allowed option values/query
   - no `dashboard_period` variable
   - no `var-dashboard_period` in links
6. For exception dashboards, enforce:
   - exactly one valid exception class tag present
   - reason tag present
   - class tag belongs to allowed set
7. For in-scope dashboards, enforce:
   - exactly one rollout tag (`time_control_rollout:tranche_a` or `time_control_rollout:tranche_b`)
   - exactly one archetype tag (`time_control_archetype:*`)
8. Emit:
   - human-readable summary
   - `--json` machine output for CI/Dagster
9. Exit codes:
   - `0` pass
   - `1` policy violations
   - `2` parse/runtime failure (should not occur if upstream linter passed)

Planned CLI flags:
1. `--dashboard-dir`
2. `--json`
3. `--strict` (enforce label text normalization; default true in Dagster path)

Deliverable:
1. Script + README usage + sample JSON output.

### Phase 2: Dagster Gate Wiring
Goal: enforce policy in pipeline, not just local checks.

Implementation targets:
1. `pipeline_personal_finance/definitions.py`
2. Optional helper module: `pipeline_personal_finance/dashboard_policy_gate.py`
3. Optional script wrapper for reuse in local/CI: `scripts/check_dashboard_time_control_policy.py`

Dagster architecture decision:
1. Create a dedicated asset (example name: `dashboard_time_control_policy_gate`).
2. Keep it separate from existing dashboard QA/lint checks.
3. Asset is fail-fast and emits structured policy violations.
4. Existing QA linter remains unchanged and continues to run as its own validation concern.

Planned gate behavior:
1. Gate runs after dbt build/test stage in default pipeline execution path.
2. Gate invokes policy checker script and captures stdout/stderr.
3. Any non-zero policy exit code fails the Dagster run.
4. Gate surfaces violation summary as structured metadata in run logs.

Dependency model:
1. `finance_dbt_assets` completes.
2. Existing QA checks run in current path (no behavior change).
3. `dashboard_time_control_policy_gate` runs as a separate downstream asset.
4. Pipeline run status is failed if policy gate fails, regardless of QA-lint pass.

Rollout mode:
The gate is wired in two stages to avoid blocking the pipeline while dashboard migrations are in progress.

Stage 1 — warn-only (active during Phases 3–5):
1. Gate runs but exits `0` regardless of policy violations.
2. Violations are surfaced as Dagster metadata/warnings, not failures.
3. Controlled by `DASHBOARD_POLICY_GATE_WARN_ONLY=true` env var (set in `.env` for dev, in Docker Compose for prod during migration window).

Stage 2 — hard-fail (activated at Phase 6 start):
1. `DASHBOARD_POLICY_GATE_WARN_ONLY` is removed or set to `false`.
2. Any policy violation from either checker (JSON linter or time-control policy) fails the Dagster run.
3. This is the permanent production state.

Transition trigger: all 24 dashboards in the time-control register show `status=compliant` or `status=exception-tagged` before Stage 2 is enabled.

Deliverable:
1. Dagster run evidence showing pass and intentional-fail scenarios.

### Phase 3: Dashboard Migration Tranche A (Existing `time_window` Dashboards)
Target selector:
1. All dashboards tagged `time_control_rollout:tranche_a`.
2. No hard-coded UID/file list in migration code paths.

Actions:
1. Remove `dashboard_period` (notably from executive).
2. Normalize dropdown labels/options/query.
3. Update SQL to remove dual-source windowing ambiguity.
4. Remove `var-dashboard_period` links.
5. Keep or normalize month-boundary logic.

Deliverable:
1. Tranche A dashboards policy-compliant with no exception tags.

### Phase 4: Dashboard Migration Tranche B (No `time_window` Yet, Non-Exceptions)
Target selector:
1. All dashboards tagged `time_control_rollout:tranche_b`.
2. Dashboards tagged with exception class tags are excluded from canonical `time_window` migration in this phase.

Mobile scoping rule:
1. Mobile dashboards are included in Tranche B only when tagged `time_control_rollout:tranche_b`.
2. Mobile dashboards tagged as forward/hybrid exceptions are excluded and validated under Phase 5.

Actions:
1. Add canonical `time_window`.
2. Convert hard-coded or native-only period assumptions to `time_window` where applicable.
3. Ensure outgoing links pass `var-time_window`.

Deliverable:
1. Tranche B dashboards policy-compliant or explicitly reclassified as exceptions.

### Phase 5: Exception Dashboard Finalization
1. Confirm exception classification for candidate list.
2. Add required tags and reason tags.
3. Validate exception dashboards are excluded from non-exception checks.
4. Validate forward/hybrid dashboards for future-period behavior and historical fallback behavior.
5. Ensure links between exception and standard dashboards do not break context handling.
6. Ensure every in-scope dashboard has exactly one rollout tag and one archetype tag.

Deliverable:
1. Finalized exception register in `workitems/task-110-time-control-register.md`.

### Phase 6: Validation, QA, and Evidence
Required checks:
1. Static lint:
   - `python scripts/check_grafana_dashboards.py --lint-only`
2. Policy checker:
   - `python scripts/check_dashboard_time_control_policy.py --json`
3. Targeted live checks:
   - `python scripts/check_grafana_dashboards.py --dashboard executive_dashboard --dashboard cash_flow_analysis --dashboard savings_analysis --days 365`
4. Expanded live checks (post-tranche):
   - run against all modified dashboards
5. Dagster gate verification:
   - one passing run
   - one intentionally failing run (temporary test change reverted after proof)
6. Playwright walkthrough (scoped to migrated dashboards only, not all 24):
   - For each Tranche A and Tranche B dashboard: verify `time_window` dropdown is visible with correct options.
   - Spot-check at least two cross-dashboard link transitions (e.g. executive → cash-flow, command-center → savings) to confirm `var-time_window` is preserved in the URL.
   - For exception dashboards (`forward_looking`, `hybrid`): verify future-period panels render as designed.
   - Verify no `No data` regressions on any panel in touched dashboards.
   - Store screenshots in `screenshots/task-110/`.
   - Explicit list of dashboards covered is recorded in task notes.

Deliverable:
1. Evidence bundle paths listed in final task notes.

## Acceptance Criteria (Detailed)
1. All 24 dashboards are either:
   - canonical-compliant non-exception, or
   - explicitly tagged exception with reason.
2. All in-scope dashboards contain metadata tags:
   - exactly one `time_control_rollout:*` tag
   - exactly one `time_control_archetype:*` tag
3. Non-exception dashboards contain:
   - exactly one canonical `time_window` variable
   - no `dashboard_period`
4. Non-exception links:
   - include `var-time_window=${time_window}`
   - exclude `var-dashboard_period`
5. Dagster gate blocks merges/runs when policy is violated.
6. Every future-component dashboard is classified as `forward_looking` or `hybrid_future_component` and tagged.
7. Validation evidence (lint, policy checker, live checks, Playwright screenshots) is complete.

## Risks and Mitigations
1. Risk: migration touches many dashboards and increases regression surface.
   - Mitigation: tranche rollout + gate + targeted live checks after each tranche.
2. Risk: label mismatch (`Latest Month` vs `Last Complete Month`) causes inconsistent UX.
   - Mitigation: strict-label mode in policy checker and one-pass normalization.
3. Risk: exception creep weakens policy.
   - Mitigation: mandatory reason tags and tracked exception register with classification rationale in notes.
4. Risk: month-boundary misalignment introduces silent metric drift.
   - Mitigation: enforce month normalization pattern in SQL review checklist.

## Execution Order
1. Fix broken JSON files (Phase 0).
2. Build JSON linter script (Phase 0.5).
3. Build time-control policy checker (Phase 1).
4. Wire Dagster gate in warn-only mode (Phase 2, Stage 1).
5. Migrate Tranche A dashboards (Phase 3).
6. Migrate Tranche B dashboards (Phase 4).
7. Finalize exception classifications and tags (Phase 5).
8. Switch gate to hard-fail, run full validation, publish evidence (Phase 6, Stage 2).
