#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the Azure Support extension set into a shared VS Code directory.
#>
[CmdletBinding()]
param(
    [string]$ExtensionsDirectory = 'C:\DevBoxSetup\VSCodeExtensions'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$logRoot = 'C:\DevBoxSetup\Logs'
New-Item -ItemType Directory -Path $logRoot, $ExtensionsDirectory -Force | Out-Null
$logPath = Join-Path $logRoot ("install-vscode-extensions-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $logPath -Append | Out-Null

function Get-CodeCommand {
    $command = Get-Command code.cmd -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'Microsoft VS Code\bin\code.cmd'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft VS Code\bin\code.cmd'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }
    throw 'VS Code command-line interface was not found.'
}

try {
    $codeCommand = Get-CodeCommand
    # VS Code reads this machine variable on future launches, allowing every Dev
    # Box user to use extensions installed during LocalSystem provisioning.
    [Environment]::SetEnvironmentVariable('VSCODE_EXTENSIONS', $ExtensionsDirectory, 'Machine')
    $env:VSCODE_EXTENSIONS = $ExtensionsDirectory

    $extensions = @(
        'ms-azuretools.vscode-bicep',
        'ms-vscode.azurecli',
        'ms-kubernetes-tools.vscode-kubernetes-tools',
        'hashicorp.terraform',
        'redhat.vscode-yaml',
        'ms-python.python',
        'ms-python.vscode-pylance',
        'GitHub.copilot',
        'GitHub.copilot-chat',
        'ms-vscode.powershell'
    )

    foreach ($extension in $extensions) {
        Write-Host "Installing VS Code extension: $extension" -ForegroundColor Cyan
        & $codeCommand '--install-extension' $extension '--force' '--extensions-dir' $ExtensionsDirectory
        if ($LASTEXITCODE -ne 0) {
            throw "VS Code extension installation failed for '$extension' with exit code $LASTEXITCODE."
        }
    }

    Write-Host "VS Code extensions installed successfully. Log: $logPath" -ForegroundColor Green
}
catch {
    Write-Error "VS Code extension setup failed: $($_.Exception.Message). Review $logPath"
    throw
}
finally {
    Stop-Transcript | Out-Null
}
