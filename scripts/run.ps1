Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$AppPath = Join-Path $RepoRoot ".DerivedData/Build/Products/Debug/OllamaAgent.app"

if (-not (Test-Path $AppPath)) {
    & (Join-Path $PSScriptRoot "build.ps1")
}

open $AppPath
