param(
    [string]$ProjectDir = "pipeline_personal_finance/dbt_finance",
    [string]$ProfilesDir = "pipeline_personal_finance/dbt_finance/local_profiles"
)

$ErrorActionPreference = "Stop"
$env:DBT_PROFILES_DIR = $ProfilesDir
$duckdbPath = Join-Path $ProjectDir "duckdb/personal_finance.duckdb"
$duckdbWalPath = "${duckdbPath}.wal"

if (Test-Path $duckdbPath) {
    Remove-Item $duckdbPath -Force
}

if (Test-Path $duckdbWalPath) {
    Remove-Item $duckdbWalPath -Force
}

function Invoke-Dbt {
    param([string[]]$DbtArgs)

    if (Get-Command dbt -ErrorAction SilentlyContinue) {
        & dbt @DbtArgs
        if ($LASTEXITCODE -ne 0) {
            throw "dbt failed with exit code $LASTEXITCODE"
        }
        return
    }

    & python -m dbt @DbtArgs
    if ($LASTEXITCODE -ne 0) {
        throw "dbt failed with exit code $LASTEXITCODE"
    }
}

python $ProjectDir/scripts/generate_synthetic_data.py --months 24
Invoke-Dbt @("deps", "--project-dir", $ProjectDir)
Invoke-Dbt @("seed", "--project-dir", $ProjectDir)
Invoke-Dbt @("run", "--project-dir", $ProjectDir, "--threads", "1")
Invoke-Dbt @("test", "--project-dir", $ProjectDir, "--threads", "1")
python $ProjectDir/scripts/validate_grafana_dashboards.py
