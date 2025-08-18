# Windows PowerShell script for getting Roo-Code from private repository

param(
    [string]$ROO_CODE_VERSION = "v3.25.11",
    [string]$ROO_CODE_REPO = "https://github.com/YourPrivateOrg/roo-code-private",
    [string]$ROO_CODE_TOKEN = $env:ROO_CODE_TOKEN
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "Fetching Roo-Code $ROO_CODE_VERSION from private repository..."

# Ensure we have authentication token
if (-not $ROO_CODE_TOKEN -and -not $env:GITHUB_TOKEN) {
    Write-Error "Error: ROO_CODE_TOKEN or GITHUB_TOKEN must be set for private repository access"
    exit 1
}

if (-not $ROO_CODE_TOKEN) {
    $ROO_CODE_TOKEN = $env:GITHUB_TOKEN
}

# Clone Roo-Code repository with authentication
if (-not (Test-Path "roo-code")) {
    $authUrl = $ROO_CODE_REPO -replace "https://", "https://${ROO_CODE_TOKEN}@"
    git clone --depth 1 --branch $ROO_CODE_VERSION $authUrl roo-code
} else {
    Push-Location roo-code
    $authUrl = $ROO_CODE_REPO -replace "https://", "https://${ROO_CODE_TOKEN}@"
    git config remote.origin.url $authUrl
    git fetch --depth 1 origin $ROO_CODE_VERSION
    git checkout $ROO_CODE_VERSION
    Pop-Location
}

# Clean up authentication info
Push-Location roo-code
git config --unset remote.origin.url 2>$null
git config remote.origin.url $ROO_CODE_REPO
Pop-Location

# Set the path for build script
$ROO_CODE_PATH = Join-Path (Get-Location) "roo-code"
Write-Host "ROO_CODE_PATH=$ROO_CODE_PATH" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append

Write-Host "Roo-Code fetched successfully from private repository!"