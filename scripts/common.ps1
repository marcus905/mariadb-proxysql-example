# Helpers shared by native Windows PowerShell 5.1 / PowerShell 7 scripts.
$ErrorActionPreference = 'Stop'

function Get-LabSetting {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Default
    )

    $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if (-not [string]::IsNullOrEmpty($value)) { return $value }

    if (Test-Path '.env') {
        foreach ($line in (Get-Content '.env')) {
            if ($line -match '^\s*' + [regex]::Escape($Name) + '\s*=\s*(.*?)\s*$') {
                $value = $Matches[1].Trim()
                if ($value -match '^["''](.*)["'']$') { $value = $Matches[1] }
            }
        }
        if (-not [string]::IsNullOrEmpty($value)) { return $value }
    }

    return $Default
}

function Invoke-Compose {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    & docker compose @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose $($Arguments -join ' ') failed (exit code $LASTEXITCODE)."
    }
}

function Get-GaleraStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Node,
        [Parameter(Mandatory = $true)][string]$RootPassword,
        [Parameter(Mandatory = $true)][string]$VariableName,
        [switch]$AllowUnavailable
    )

    # During bootstrap a database that is not yet ready is expected. During
    # diagnostics, preserve the CLI error instead of silently returning blanks.
    # PowerShell 5.1 and 7 handle native stderr slightly differently. Temporarily
    # use Continue so 2>&1 captures both streams regardless of PowerShell version.
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& docker compose exec -T -e "MYSQL_PWD=$RootPassword" $Node mariadb -uroot --batch --skip-column-names -e "SHOW GLOBAL STATUS LIKE '$VariableName';" 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }

    if ($exitCode -ne 0) {
        if ($AllowUnavailable) { return $null }
        $details = ($output | ForEach-Object { [string]$_ }) -join ' | '
        throw "MariaDB query failed on $Node (exit $exitCode) for $VariableName. Details: $details"
    }

    foreach ($line in $output) {
        $parts = ([string]$line).Trim() -split '\s+', 2
        if ($parts.Count -eq 2 -and $parts[0] -eq $VariableName) {
            return $parts[1].Trim()
        }
    }

    if ($AllowUnavailable) { return $null }
    $raw = ($output | ForEach-Object { [string]$_ }) -join ' | '
    throw "No value returned for $VariableName on $Node. Galera may be disabled or not initialized. Raw response: $raw"
}
