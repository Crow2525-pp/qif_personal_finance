# Data Projects

Data projects are domain-specific pipelines that run on the shared platform in `../platform`.

Current project slots:

- `qif_personal_finance/`: tracked in this repository. Owns QIF ingestion, personal-finance dbt models, and finance dashboard QA.
- `coles_llm/`: documented slot for the Coles LLM shopper project. The active local source is currently a separate nested Git checkout at repository root (`coles-llm-shopper/`) and is not tracked here.

New data projects should live under `data_projects/<project_slug>/` unless they intentionally remain external repositories.
