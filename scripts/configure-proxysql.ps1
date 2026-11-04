# Apply ProxySQL Galera hostgroups after the backend cluster is online.
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot
try {
    . (Join-Path $PSScriptRoot 'common.ps1')
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker CLI not found. Start Docker Desktop first.'
    }

    Write-Host 'Waiting for ProxySQL Admin on the Docker network...'
    $ready = $false
    for ($attempt = 1; $attempt -le 60; $attempt++) {
        & docker compose exec -T -e 'MYSQL_PWD=radminpass' galera1 mariadb --protocol=tcp -hproxysql -P6032 -uradmin -Nse 'SELECT 1;' 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep -Seconds 2
    }
    if (-not $ready) { throw 'ProxySQL Admin is not responding on port 6032.' }

    $sql = @'
DELETE FROM mysql_galera_hostgroups WHERE writer_hostgroup=10;
INSERT INTO mysql_galera_hostgroups
(writer_hostgroup, backup_writer_hostgroup, reader_hostgroup, offline_hostgroup, active, max_writers, writer_is_also_reader, max_transactions_behind)
VALUES (10, 20, 30, 40, 1, 1, 1, 100);
LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
'@

    & docker compose exec -T -e 'MYSQL_PWD=radminpass' galera1 mariadb --protocol=tcp -hproxysql -P6032 -uradmin -e $sql
    if ($LASTEXITCODE -ne 0) { throw 'Unable to apply ProxySQL Galera hostgroups.' }
    Write-Host 'ProxySQL Galera hostgroups configured.'
}
finally {
    Pop-Location
}
