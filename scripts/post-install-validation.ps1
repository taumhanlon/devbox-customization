#Requires -Version 5.1
<#
.SYNOPSIS
    Validates the required Azure Support workstation components.
#>
[CmdletBinding()]
param(
    [string]$UbuntuDistribution = 'Ubuntu-24.04'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$logRoot = 'C:\DevBoxSetup\Logs'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$logPath = Join-Path $logRoot ("post-install-validation-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $logPath -Append | Out-Null

$results = [System.Collections.Generic.List[object]]::new()

function Add-ValidationResult {
    param(
        [Parameter(Mandatory)][string]$Component,
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Details
    )
    $results.Add([pscustomobject]@{
        Component = $Component
        Status = if ($Passed) { 'PASS' } else { 'FAIL' }
        Details = $Details.Trim()
    })
}

function Test-CommandVersion {
    param(
        [Parameter(Mandatory)][string]$Component,
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    try {
        $resolved = Get-Command $Command -ErrorAction Stop
        $output = (& $resolved.Source @Arguments 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) {
            throw "Exited with code $LASTEXITCODE. $output"
        }
        Add-ValidationResult -Component $Component -Passed $true -Details (($output -split "`r?`n")[0])
    }
    catch {
        Add-ValidationResult -Component $Component -Passed $false -Details $_.Exception.Message
    }
}

try {
    # Refresh PATH so this process sees applications installed earlier in the run.
    $env:Path = @(
        [Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [Environment]::GetEnvironmentVariable('Path', 'User')
    ) -join ';'

    Test-CommandVersion -Component 'PowerShell 7' -Command 'pwsh.exe' -Arguments @('--version')
    Test-CommandVersion -Component 'Azure CLI' -Command 'az.cmd' -Arguments @('version')
    Test-CommandVersion -Component 'Terraform' -Command 'terraform.exe' -Arguments @('version')
    Test-CommandVersion -Component 'Bicep' -Command 'az.cmd' -Arguments @('bicep', 'version')
    Test-CommandVersion -Component 'kubectl' -Command 'kubectl.exe' -Arguments @('version', '--client')
    Test-CommandVersion -Component 'VS Code' -Command 'code.cmd' -Arguments @('--version')

    try {
        $wslOutput = (& wsl.exe --status 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { throw "wsl --status exited with code $LASTEXITCODE. $wslOutput" }
        Add-ValidationResult -Component 'WSL' -Passed $true -Details (($wslOutput -split "`r?`n")[0])
    }
    catch {
        Add-ValidationResult -Component 'WSL' -Passed $false -Details $_.Exception.Message
    }

    try {
        $distributions = @(& wsl.exe --list --quiet 2>&1) -replace "`0", ''
        $match = $distributions | Where-Object { $_.Trim() -eq $UbuntuDistribution }
        if (-not $match) { throw "Distribution '$UbuntuDistribution' was not listed by wsl.exe." }
        Add-ValidationResult -Component 'Ubuntu' -Passed $true -Details $UbuntuDistribution
    }
    catch {
        Add-ValidationResult -Component 'Ubuntu' -Passed $false -Details $_.Exception.Message
    }

    Write-Host "`nAzure Support / HPC Dev Box validation" -ForegroundColor Cyan
    $results | Format-Table -AutoSize -Wrap
    $passed = @($results | Where-Object Status -eq 'PASS').Count
    $failed = @($results | Where-Object Status -eq 'FAIL').Count
    Write-Host "Summary: $passed passed, $failed failed. Log: $logPath"

    if ($failed -gt 0) {
        throw "$failed required component(s) failed validation."
    }
    Write-Host 'All required components passed validation.' -ForegroundColor Green
}
catch {
    Write-Error $_
    exit 1
}
finally {
    Stop-Transcript | Out-Null
}
