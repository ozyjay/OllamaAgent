Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    xcodebuild `
        -project OllamaDashboard.xcodeproj `
        -scheme OllamaDashboard `
        -destination 'platform=macOS' `
        -derivedDataPath ./.DerivedData `
        test `
        CODE_SIGNING_ALLOWED=NO
}
finally {
    Pop-Location
}
