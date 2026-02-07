## Summary

- Describe what changed and why.
- Commit scope is atomic (separate rename-only, logic-only, and artifact/docs-only changes where practical).

## Validation

- [ ] Local checks/tests were run (list commands in PR body)
- [ ] If dashboards changed, panel data and query errors were verified

### Dashboard Verification Evidence (Required for dashboard JSON changes)

- Before failures:
- After failures:
- Request IDs / key query errors observed:
- Dashboards/ranges validated (e.g. `1-10`, `11-23`):

## Dashboard Query Migration Checklist

Complete this when dashboard SQL sources were changed (table/view/model/column/join updates):

- [ ] Table/view renames were updated in all affected panel queries
- [ ] Column renames were mapped (no stale legacy names remain)
- [ ] Join keys were validated against current schema
- [ ] Units/labels still match the returned data format
- [ ] `scripts/check_grafana_dashboards.py` was run for impacted ranges
- [ ] Verification evidence is attached (output, screenshot, or notes)
