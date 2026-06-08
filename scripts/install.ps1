param(
    [string]$Destination = (Join-Path $HOME "Applications"),
    [switch]$Launch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$BuiltAppPath = Join-Path $RepoRoot ".DerivedData/Build/Products/Debug/OllamaDashboard.app"
$InstallPath = Join-Path $Destination "OllamaDashboard.app"

& (Join-Path $PSScriptRoot "build.ps1")

if (-not (Test-Path $BuiltAppPath)) {
    throw "Built app was not found at $BuiltAppPath"
}

New-Item -ItemType Directory -Path $Destination -Force | Out-Null

$running = Get-Process -Name "OllamaDashboard" -ErrorAction SilentlyContinue
if ($running) {
    $running | Stop-Process
}

if (Test-Path $InstallPath) {
    Remove-Item -Path $InstallPath -Recurse -Force
}

Copy-Item -Path $BuiltAppPath -Destination $InstallPath -Recurse

Write-Host "Installed OllamaDashboard to $InstallPath"

if ($Launch) {
    open $InstallPath
}
