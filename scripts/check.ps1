# Verify all three Galera nodes, ProxySQL routing and the published SQL port.
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot
try {
    . (Join-Path $PSScriptRoot 'common.ps1')
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker CLI not found. Start Docker Desktop first.'
    }
    $rootPassword = Get-LabSetting -Name 'MARIADB_ROOT_PASSWORD' -Default 'rootpass'

    foreach ($node in @('galera1', 'galera2', 'galera3')) {
        Write-Host "=== $node ==="
        $values = @{}
        foreach ($key in @('wsrep_cluster_size', 'wsrep_cluster_status', 'wsrep_local_state_comment', 'wsrep_ready')) {
            $values[$key] = Get-GaleraStatus -Node $node -RootPassword $rootPassword -VariableName $key
            Write-Host ("{0}: {1}" -f $key, $values[$key])
        }
        if ($values['wsrep_cluster_size'] -ne '3' -or
            $values['wsrep_cluster_status'] -ne 'Primary' -or
            $values['wsrep_local_state_comment'] -ne 'Synced' -or
            $values['wsrep_ready'] -ne 'ON') {
            throw "$node is not fully synced in a 3-node primary component."
        }
    }

    Write-Host '=== ProxySQL runtime_mysql_servers ==='
    & docker compose exec -T -e 'MYSQL_PWD=radminpass' galera1 mariadb --protocol=tcp -hproxysql -P6032 -uradmin -e 'SELECT hostgroup_id, hostname, port, status FROM runtime_mysql_servers ORDER BY hostgroup_id, hostname;'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot query ProxySQL Admin interface.' }

    Write-Host '=== Host-published SQL listener ==='
    & (Join-Path $PSScriptRoot 'test-connection.ps1')
    Write-Host 'All checks passed.'
}
finally {
    Pop-Location
}
