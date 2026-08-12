#Requires -RunAsAdministrator
#Requires -Version 5.1
<#
.SYNOPSIS
    Configures a Windows 11 Dev Box for Azure and HPC support work.
.DESCRIPTION
    Installs current WinGet packages, enables WSL 2, bootstraps Ubuntu, installs
    shared VS Code extensions, and records a transcript under C:\DevBoxSetup\Logs.
#>
[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$UbuntuDistribution = 'Ubuntu-24.04',
    [switch]$SkipWslBootstrap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$setupRoot = 'C:\DevBoxSetup'
$scriptRoot = Join-Path $setupRoot 'scripts'
$logRoot = Join-Path $setupRoot 'Logs'
New-Item -ItemType Directory -Path $scriptRoot, $logRoot -Force | Out-Null
$logPath = Join-Path $logRoot ("bootstrap-windows-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $logPath -Append | Out-Null

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "`n[$(Get-Date -Format 's')] $Message" -ForegroundColor Cyan
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [int[]]$AllowedExitCodes = @(0)
    )

    & $FilePath @ArgumentList
    $exitCode = $LASTEXITCODE
    if ($exitCode -notin $AllowedExitCodes) {
        throw "Command '$FilePath $($ArgumentList -join ' ')' failed with exit code $exitCode."
    }
}

function Update-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = @($machinePath, $userPath) -join ';'
}

function Install-WinGetPackage {
    param([Parameter(Mandatory)][string]$Id)

    Write-Step "Installing or upgrading WinGet package: $Id"
    $arguments = @(
        'install', '--id', $Id, '--exact', '--silent',
        '--accept-package-agreements', '--accept-source-agreements',
        '--disable-interactivity', '--source', 'winget'
    )
    # 3010 indicates success with a reboot required. The HRESULT is returned by
    # some WinGet releases when the requested package is already installed.
    Invoke-NativeCommand -FilePath 'winget.exe' -ArgumentList $arguments `
        -AllowedExitCodes @(0, 3010, -1978335189)
}

try {
    Write-Step 'Staging customization scripts'
    $resolvedSource = (Resolve-Path -Path $SourceRoot).Path
    $sourceScripts = Join-Path $resolvedSource 'scripts'
    if (-not (Test-Path -LiteralPath $sourceScripts -PathType Container)) {
        throw "Scripts directory not found: $sourceScripts"
    }
    if ($sourceScripts -ne $scriptRoot) {
        Copy-Item -Path (Join-Path $sourceScripts '*') -Destination $scriptRoot -Recurse -Force
    }

    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw 'WinGet is unavailable. Use a Windows 11 Dev Box image containing Microsoft App Installer.'
    }

    Write-Step 'Refreshing WinGet sources'
    Invoke-NativeCommand -FilePath 'winget.exe' -ArgumentList @('source', 'update')

    $packages = @(
        'Microsoft.PowerShell',
        'Microsoft.AzureCLI',
        'Hashicorp.Terraform',
        'Kubernetes.kubectl',
        'Helm.Helm',
        'Git.Git',
        'Microsoft.VisualStudioCode',
        'Microsoft.WindowsTerminal',
        'Microsoft.Azure.StorageExplorer',
        'Notepad++.Notepad++',
        'WinMerge.WinMerge',
        'Python.Python.3.14',
        'jqlang.jq',
        'MikeFarah.yq'
    )
    foreach ($package in $packages) {
        Install-WinGetPackage -Id $package
    }
    Update-ProcessPath

    Write-Step 'Installing or upgrading the Azure CLI-managed Bicep CLI'
    $azCommand = (Get-Command az.cmd -ErrorAction SilentlyContinue).Source
    if (-not $azCommand) {
        $azCommand = (Get-Command az.exe -ErrorAction Stop).Source
    }
    Invoke-NativeCommand -FilePath $azCommand -ArgumentList @('bicep', 'install')
    Invoke-NativeCommand -FilePath $azCommand -ArgumentList @('bicep', 'upgrade')

    Write-Step 'Enabling Windows Subsystem for Linux and Virtual Machine Platform'
    $features = @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')
    foreach ($feature in $features) {
        Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart | Out-Null
    }

    Write-Step "Ensuring WSL and $UbuntuDistribution are installed"
    Invoke-NativeCommand -FilePath 'wsl.exe' -ArgumentList @('--update')
    Invoke-NativeCommand -FilePath 'wsl.exe' -ArgumentList @('--set-default-version', '2')
    $installedDistributions = @(& wsl.exe --list --quiet 2>$null) -replace "`0", ''
    if ($UbuntuDistribution -notin $installedDistributions) {
        Invoke-NativeCommand -FilePath 'wsl.exe' `
            -ArgumentList @('--install', '--distribution', $UbuntuDistribution, '--no-launch') `
            -AllowedExitCodes @(0, 3010)
    }

    if (-not $SkipWslBootstrap) {
        Write-Step 'Bootstrapping Linux support and HPC packages in Ubuntu'
        $wslScript = '/mnt/c/DevBoxSetup/scripts/bootstrap-wsl.sh'
        Invoke-NativeCommand -FilePath 'wsl.exe' `
            -ArgumentList @('--distribution', $UbuntuDistribution, '--user', 'root', '--', 'bash', $wslScript)
    }

    Write-Step 'Installing shared VS Code extensions'
    & (Join-Path $scriptRoot 'install-vscode-extensions.ps1')

    Write-Step 'Running post-install validation'
    & (Join-Path $scriptRoot 'post-install-validation.ps1')

    Write-Host "`nDev Box bootstrap completed successfully. Log: $logPath" -ForegroundColor Green
}
catch {
    Write-Error "Dev Box bootstrap failed: $($_.Exception.Message). Review $logPath"
    throw
}
finally {
    Stop-Transcript | Out-Null
}
