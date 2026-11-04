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
        [Parameter(Mandatory = $true)][string]$VariableName
    )
    $result = & docker compose exec -T -e "MYSQL_PWD=$RootPassword" $Node mariadb -uroot --batch --skip-column-names -e "SHOW GLOBAL STATUS LIKE '$VariableName';" 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $text = $result -join "`n"
    if ($text -match "(?m)^$([regex]::Escape($VariableName))\s+(\S+)\s*$") {
        return $Matches[1]
    }
    return $null
}
