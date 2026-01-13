param(
    [string]$ProjectDir = "pipeline_personal_finance/dbt_finance",
    [string]$ProfilesDir = "pipeline_personal_finance/dbt_finance/local_profiles"
)

$ErrorActionPreference = "Stop"
$env:DBT_PROFILES_DIR = $ProfilesDir

python $ProjectDir/scripts/generate_synthetic_data.py --months 24
python -m dbt deps --project-dir $ProjectDir
python -m dbt seed --project-dir $ProjectDir
python -m dbt run --project-dir $ProjectDir
python -m dbt test --project-dir $ProjectDir
python $ProjectDir/scripts/validate_grafana_dashboards.py
