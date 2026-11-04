<#
.SYNOPSIS
    Test the exposed ProxySQL TCP listener and perform an actual SQL login.
.DESCRIPTION
    Runs from Windows PowerShell 5.1 or PowerShell 7.
    Uses a local MariaDB client if found; otherwise Docker Desktop runs a
    temporary MariaDB client container. Docker Desktop resolves
    host.docker.internal to the Windows host (not the Docker network).
.EXAMPLE
    .\scripts\test-connection.ps1
.EXAMPLE
    .\scripts\test-connection.ps1 -HostName 192.168.1.50 -Port 6033
#>
param(
    [string]$HostName = '127.0.0.1',
    [int]$Port = 0,
    [string]$Username = 'labuser',
    [string]$Password = 'labpass',
    [string]$Database = 'labdb',
    [switch]$TcpOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot
try {
    . (Join-Path $PSScriptRoot 'common.ps1')
    if ($Port -eq 0) {
        $Port = [int](Get-LabSetting -Name 'PROXYSQL_PORT' -Default '6033')
    }
    if ($Port -lt 1 -or $Port -gt 65535) { throw 'Invalid TCP port.' }

    Write-Host "Testing TCP $($HostName):$Port ..."
    $client = New-Object System.Net.Sockets.TcpClient
    $async = $null
    try {
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(5000, $false)) {
            throw 'TCP connection timed out. Check firewall, IP address and published port.'
        }
        $client.EndConnect($async)
        Write-Host 'TCP port reachable.'
    }
    finally {
        if ($null -ne $async) { $async.AsyncWaitHandle.Close() }
        $client.Dispose()
    }

    if ($TcpOnly) {
        Write-Host 'TCP-only check complete. SQL authentication was not tested.'
        return
    }

    $previousPassword = [Environment]::GetEnvironmentVariable('MYSQL_PWD', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('MYSQL_PWD', $Password, 'Process')
        $sql = 'SELECT @@hostname AS backend, DATABASE() AS database_name;'
        if (Get-Command mariadb -ErrorAction SilentlyContinue) {
            Write-Host 'Testing SQL authentication with local MariaDB client...'
            & mariadb --protocol=tcp "-h$HostName" "-P$Port" "-u$Username" $Database -e $sql
        }
        elseif (Get-Command docker -ErrorAction SilentlyContinue) {
            $sqlHost = $HostName
            if ($HostName -in @('localhost', '127.0.0.1', '::1')) {
                $sqlHost = 'host.docker.internal'
            }
            Write-Host "Testing SQL authentication via a temporary MariaDB client container ($sqlHost)..."
            & docker run --rm -e MYSQL_PWD mariadb:11.4 mariadb --protocol=tcp "-h$sqlHost" "-P$Port" "-u$Username" $Database -e $sql
        }
        else {
            Write-Warning 'No local MariaDB client or Docker CLI detected. Only the TCP reachability check was performed.'
            return
        }
        if ($LASTEXITCODE -ne 0) {
            throw "ProxySQL SQL login failed (exit code $LASTEXITCODE). Check mysql_users, runtime_mysql_servers and credentials."
        }
        Write-Host 'ProxySQL SQL login and query succeeded.'
    }
    finally {
        [Environment]::SetEnvironmentVariable('MYSQL_PWD', $previousPassword, 'Process')
    }
}
finally {
    Pop-Location
}
