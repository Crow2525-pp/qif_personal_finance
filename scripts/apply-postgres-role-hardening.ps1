param(
    [string]$ContainerName = "qif_personal_finance-dagster_postgres-1",
    [string]$Database = "personal_finance",
    [string]$AdminUser = "postgres",
    [string]$DagsterUser = "dagster_service",
    [string]$DagsterPassword = "",
    [string]$GrafanaUser = "grafanareader"
)

if (-not $DagsterPassword) {
    Write-Error "DagsterPassword is required."
    exit 1
}

$sql = Get-Content -Raw -Path "scripts/harden_postgres_roles.sql"
$escapedPassword = $DagsterPassword.Replace("'", "''")
$escapedDagsterUser = $DagsterUser.Replace("'", "''")
$escapedGrafanaUser = $GrafanaUser.Replace("'", "''")

@"
SET app.dagster_user = '$escapedDagsterUser';
SET app.dagster_password = '$escapedPassword';
SET app.grafana_user = '$escapedGrafanaUser';
$sql
"@
| docker exec -i $ContainerName psql -v ON_ERROR_STOP=1 -U $AdminUser -d $Database
