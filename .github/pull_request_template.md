## Summary

- Describe what changed and why.

## Validation

- [ ] Local checks/tests were run (list commands in PR body)
- [ ] If dashboards changed, panel data and query errors were verified

## Dashboard Query Migration Checklist

Complete this when dashboard SQL sources were changed (table/view/model/column/join updates):

- [ ] Table/view renames were updated in all affected panel queries
- [ ] Column renames were mapped (no stale legacy names remain)
- [ ] Join keys were validated against current schema
- [ ] Units/labels still match the returned data format
- [ ] `scripts/check_grafana_dashboards.py` was run for impacted ranges
- [ ] Verification evidence is attached (output, screenshot, or notes)
