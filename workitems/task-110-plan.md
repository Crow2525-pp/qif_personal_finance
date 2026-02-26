# Task 110 Plan: Native Time Picker Unification

Related kickoff: `workitems/task-110-kickoff.md`
Branch target: `feat/task-110-native-timepicker-unification`
Plan revision: 2026-02-25 (rev 3 — pivot to native Grafana time picker, drop custom variable)

## Objective

Unify all 24 Grafana dashboards under the native Grafana time picker as the single time-control mechanism:
1. Native time picker visible on all historical dashboards with `quick_ranges` presets.
2. SQL uses `$__timeFrom()` / `$__timeTo()` macros for date filtering (not custom variables).
3. The custom `time_window` dropdown variable is removed from all dashboards.
4. Exception dashboards (atemporal, forward-looking, hybrid, fixed-period) are explicitly tagged and configured.
5. A Dagster gate enforces the policy.

## Why Native Time Picker, Not Custom Dropdown

Rev 2 adopted a custom `time_window` dropdown for month-boundary determinism. This revision pivots back to the native Grafana time picker because:
1. `quick_ranges` presets provide the same one-click access to canonical periods (last complete month, YTD, trailing 12m) with month-rounded boundaries (`now-1M/M`, `now/M`).
2. The native picker also allows free-form date exploration without a separate control.
3. SQL using `$__timeFrom()` / `$__timeTo()` is idiomatic Grafana and eliminates the need for CTE-based window resolution.
4. Fewer moving parts: no custom variable to maintain, no `var-time_window` to propagate in links.

## Non-Goals
1. Rewriting business metric formulas unrelated to time-window semantics.
2. Redesigning dashboard UX beyond time-control normalization.
3. Broad refactor of unrelated variables.

## Time-Control Contract

### 1) Native time picker configuration

For **historical_windowed** dashboards (default archetype):
- `timepicker.hidden`: `false` or absent
- `timepicker.quick_ranges`: three canonical presets (see below)
- `time.from`: `now-1M/M` (default)
- `time.to`: `now/M` (default)

### 2) Quick ranges by archetype

| Archetype | quick_ranges |
|---|---|
| `historical_windowed` | "Last complete month" (`now-1M/M` → `now/M`), "Year to date" (`now/Y` → `now`), "Trailing 12 months" (`now-12M/M` → `now/M`) |
| `historical_fixed_period` | "Full history" (`now-10y` → `now`), plus free-form native picker |
| `forward_looking` | "Next 12 months" (`now` → `now+12M`), "Next 5 years" (`now` → `now+5y`) |
| `hybrid_past_future` | "Last 12 months + next 12 months" (`now-12M` → `now+12M`), "Full history + projections" (`now-10y` → `now+5y`) |
| `atemporal_no_time_component` | Time picker **hidden** (`timepicker.hidden: true`) |

### 3) SQL contract

All non-atemporal dashboards should use `$__timeFrom()` / `$__timeTo()` / `$__timeFilter()` macros where time filtering is needed. No `${time_window}` or `${dashboard_period}` references.

### 4) Link contract

Cross-dashboard links use `${__url_time_range}` only. No `var-time_window` or `var-dashboard_period` parameters.

**URL pattern:**
```
/d/<uid>?orgId=1&${__url_time_range}
```

### 5) Template variables

- `time_window` variable: **removed** from all dashboards
- `dashboard_period` variable: **removed** from all dashboards
- Other domain-specific variables (e.g. `scenario`, `category`) are unaffected

## Temporal Archetypes

Every dashboard is classified into one archetype:

1. **`historical_windowed`** (default): Uses canonical quick_ranges. No exception tags.
2. **`historical_fixed_period`**: Time-specific historical dashboard. Tagged `time_control:time_specific_exception`.
3. **`atemporal_no_time_component`**: No time component. Tagged `time_control:no_time_component_exception`. Time picker hidden.
4. **`forward_looking`**: Primarily future projections. Tagged `time_control:forward_looking_exception`.
5. **`hybrid_past_future`**: Mixes historical and projected. Tagged `time_control:hybrid_future_component_exception`.

## Rollout Metadata

Archetype and exception classification uses dashboard tags:
- One archetype tag: `time_control_archetype:<archetype>`
- Exception dashboards carry a class tag and reason tag
- Rollout tranche tags (`time_control_rollout:tranche_a/b`) are retained for provenance but are not enforced as a phased mechanism

## Work Plan

### Step 1: Migrate all 24 dashboard JSON files (single pass)

For each **historical_windowed** dashboard:
1. Remove `time_window` from `templating.list`
2. Remove `dashboard_period` from `templating.list` if present
3. Set `timepicker.quick_ranges` to canonical historical presets
4. Set `time.from` = `now-1M/M`, `time.to` = `now/M`
5. Remove `var-time_window` and `var-dashboard_period` from all URLs (keep `${__url_time_range}`)

For each **exception** dashboard:
- `atemporal`: set `timepicker.hidden: true`, no quick_ranges
- `forward_looking`: set forward quick_ranges, appropriate time defaults
- `hybrid_past_future`: set hybrid quick_ranges
- `historical_fixed_period`: set full-history quick_ranges

### Step 2: Update policy checker

Replace custom variable enforcement with native time picker enforcement:
- Check `timepicker.quick_ranges` presence for non-atemporal dashboards
- Check `timepicker.hidden: true` for atemporal dashboards
- Check no `time_window` or `dashboard_period` variables remain
- Check no `var-time_window` or `var-dashboard_period` in links
- Check at least one panel SQL references `$__timeFrom` or `$__timeTo` or `$__timeFilter` (for non-atemporal, non-fixed-period dashboards)

### Step 3: Update tests

Rewrite tests to validate new policy (quick_ranges, no custom vars, link format).

### Step 4: Update documentation

Update plan, register, and README to reflect native picker approach.

### Step 5: Validate

1. `python scripts/validate_dashboard_json.py` — all 24 parse clean
2. `python scripts/check_dashboard_time_control_policy.py --json` — zero violations
3. `uv run pytest tests/ -v` — all tests pass

## Acceptance Criteria

1. All 24 dashboards either canonical-compliant or explicitly tagged exception.
2. No `time_window` or `dashboard_period` template variables in any dashboard.
3. No `var-time_window` or `var-dashboard_period` in any cross-dashboard links.
4. Historical dashboards have `quick_ranges` with 3 canonical presets.
5. Atemporal dashboards have `timepicker.hidden: true`.
6. Policy checker passes all 24 dashboards.
7. All tests pass.
