# Initial bootstrap of a *new* disposable Galera lab on Windows / Docker Desktop.
# Never run against existing data volumes after a full-cluster outage.
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot
$originalBootstrap = $env:GALERA_BOOTSTRAP
try {
    . (Join-Path $PSScriptRoot 'common.ps1')
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker CLI not found. Start Docker Desktop first.'
    }
    & docker compose version | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Docker Compose v2 is required.' }

    $running = @(& docker compose ps --status running --services)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect running services.' }
    if (@($running | Where-Object { $_ -match '^galera[123]$' }).Count -gt 0) {
        throw 'Galera is already running. Use docker compose up -d for a healthy existing cluster.'
    }

    $volumes = @(& docker volume ls --filter 'label=com.docker.compose.project=mariadb-galera-proxysql' --format '{{.Name}}')
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect Docker volumes.' }
    if (@($volumes | Where-Object { $_ -match 'galera[123]_data$' }).Count -gt 0) {
        throw 'Existing Galera data volumes detected. Refusing automatic bootstrap. See README recovery/reset instructions.'
    }

    $rootPassword = Get-LabSetting -Name 'MARIADB_ROOT_PASSWORD' -Default 'rootpass'
    $env:GALERA_BOOTSTRAP = '1'
    Write-Host 'Bootstrapping galera1...'
    Invoke-Compose -Arguments @('up', '-d', '--no-deps', 'galera1')

    Write-Host 'Waiting for first node to become ready...'
    $ready = $false
    for ($attempt = 1; $attempt -le 90; $attempt++) {
        if ((Get-GaleraStatus -Node 'galera1' -RootPassword $rootPassword -VariableName 'wsrep_ready') -eq 'ON') {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $ready) { throw 'galera1 failed to become ready. Inspect: docker compose logs galera1' }

    $env:GALERA_BOOTSTRAP = '0'
    Write-Host 'Joining galera2 and galera3...'
    Invoke-Compose -Arguments @('up', '-d', '--no-deps', 'galera2', 'galera3')

    $ready = $false
    for ($attempt = 1; $attempt -le 120; $attempt++) {
        if ((Get-GaleraStatus -Node 'galera1' -RootPassword $rootPassword -VariableName 'wsrep_cluster_size') -eq '3') {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $ready) { throw 'Cluster did not reach 3 members. Inspect: docker compose logs galera2 galera3' }

    Write-Host 'Recreating galera1 without the bootstrap option...'
    Invoke-Compose -Arguments @('up', '-d', '--no-deps', '--force-recreate', 'galera1')
    Write-Host 'Starting ProxySQL...'
    Invoke-Compose -Arguments @('up', '-d', '--no-deps', 'proxysql')

    & (Join-Path $PSScriptRoot 'configure-proxysql.ps1')
    Write-Host 'Ready for verification: .\scripts\check.ps1'
}
finally {
    if ($null -eq $originalBootstrap) {
        Remove-Item 'Env:GALERA_BOOTSTRAP' -ErrorAction SilentlyContinue
    }
    else { $env:GALERA_BOOTSTRAP = $originalBootstrap }
    Pop-Location
}
