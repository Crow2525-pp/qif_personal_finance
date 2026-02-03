# Pipeline Purpose & Usage Context

This file captures the operational rhythm and intent behind the
`pipeline_personal_finance` pipeline and its Grafana dashboards.
Claude should treat this as standing context when making changes to
either.

## What the pipeline is for

The pipeline exists to support **general household spend awareness**.
There are no formal budget targets or savings goals baked in — the
goal is simply to keep a clear, up-to-date picture of where money is
going so informed decisions can be made when needed.

## Operational cadence

| Step | Frequency | How |
|---|---|---|
| QIF export from banks | Monthly | Manual download from each bank |
| File drop & pipeline run | Monthly | Drop files into `qif_files/`, trigger via Dagster UI |
| Dashboard review | Once or twice a quarter | Open Grafana, review the four key dashboards |

Because the pipeline is **manual and low-frequency**, there is no
expectation of automated scheduling, real-time data, or low-latency
refresh. Changes to the pipeline or dashboards should be evaluated
against this cadence — optimising for infrequency and simplicity is
preferred over sophistication.

## Dashboards reviewed each quarter

All four dashboards listed below are part of the standard quarterly
review. They are provisioned from JSON in
`grafana/provisioning/dashboards/`.

| Dashboard | What it surfaces |
|---|---|
| Executive Financial Overview | Top-level KPIs and summary metrics |
| Cash Flow Analysis | Income vs. expense trends over time |
| Category Spending Analysis | Breakdown of spending by category |
| Account Performance | Balance tracking across accounts |

## Guardrails for Claude

When working on this pipeline or its dashboards keep the following in
mind:

- **No real-time features.** Do not propose or implement streaming,
  WebSocket-based updates, or live-refresh logic. All data is batch
  and consumed on a quarterly cadence.
- **Favour simplicity.** The pipeline runs infrequently and is
  reviewed by one person. Prefer the simplest implementation that
  solves the problem; avoid abstractions or features that only pay
  off at higher frequency or scale.
- **Manual ingestion is intentional.** Do not add automated file
  watchers, cron jobs, or scheduled Dagster triggers unless
  explicitly requested.
