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

$sqlPath = "postgres/init/02-role-hardening.sql"
if (-not (Test-Path $sqlPath)) {
    Write-Error "Hardening SQL file not found at $sqlPath"
    exit 1
}

# Ensure service role exists and rotate password before applying grants/ownership.
$escapedPassword = $DagsterPassword.Replace("'", "''")
$escapedUser = $DagsterUser.Replace("""", """""")
$roleUpsert = @"
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$DagsterUser') THEN
        EXECUTE 'CREATE ROLE ""$escapedUser"" LOGIN PASSWORD ''$escapedPassword''';
    ELSE
        EXECUTE 'ALTER ROLE ""$escapedUser"" WITH LOGIN PASSWORD ''$escapedPassword''';
    END IF;
END
\$\$;
"@

$roleUpsert | docker exec -i $ContainerName psql -v ON_ERROR_STOP=1 -U $AdminUser -d $Database

Get-Content -Raw -Path $sqlPath |
docker exec -i $ContainerName psql -v ON_ERROR_STOP=1 -U $AdminUser -d $Database `
    -v dagster_user="$DagsterUser" `
    -v grafana_user="$GrafanaUser"
