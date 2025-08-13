# Windows PowerShell script for building Roo-Code extension

param(
    [string]$ROO_CODE_PATH = ".\roo-code"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "Building Roo-Code extension..."

$VSCODE_PATH = ".\vscode"
$TARGET_DIR = Join-Path $VSCODE_PATH ".build\extensions\roo-code"

# Check if Roo-Code source exists
$srcPath = Join-Path $ROO_CODE_PATH "src"
if (-not (Test-Path $srcPath)) {
    Write-Error "Roo-Code source not found at $srcPath"
    Write-Error "Please run .\get_roo_code.ps1 first or set ROO_CODE_PATH correctly"
    exit 1
}

# Create target directory
New-Item -ItemType Directory -Force -Path $TARGET_DIR | Out-Null

# Build Roo-Code extension first
Write-Host "Building Roo-Code extension..."
Push-Location $ROO_CODE_PATH

# Check if dist already exists
$distPath = Join-Path "src" "dist"
$extensionJsPath = Join-Path $distPath "extension.js"

if ((Test-Path $distPath) -and (Test-Path $extensionJsPath)) {
    Write-Host "Dist directory already exists, skipping build..."
} else {
    Write-Host "Dist directory not found, building extension..."
    
    # Check if pnpm is available
    if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
        Write-Error "ERROR: pnpm is required but not installed!"
        Write-Error "Please install pnpm: npm install -g pnpm"
        exit 1
    }
    
    # Try frozen lockfile first, fallback to regular install if it fails
    $installSuccess = $false
    try {
        pnpm install --frozen-lockfile
        $installSuccess = $true
    } catch {
        Write-Host "Frozen lockfile failed, trying without frozen-lockfile..."
    }
    
    if (-not $installSuccess) {
        pnpm install
        if ($LASTEXITCODE -ne 0) {
            Write-Error "ERROR: Failed to install dependencies"
            exit 1
        }
    }
    
    pnpm build
    if ($LASTEXITCODE -ne 0) {
        Write-Error "ERROR: Failed to build Roo-Code extension"
        exit 1
    }
    
    if (-not (Test-Path $extensionJsPath)) {
        Write-Error "ERROR: Build completed but src\dist\extension.js not found!"
        exit 1
    }
}

Pop-Location

# Copy extension files
Write-Host "Copying Roo-Code files..."
Copy-Item -Path "$srcPath\*" -Destination $TARGET_DIR -Recurse -Force

# Remove development files
Remove-Item -Path "$TARGET_DIR\node_modules" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$TARGET_DIR\__tests__" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$TARGET_DIR\__mocks__" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$TARGET_DIR\.turbo" -Recurse -Force -ErrorAction SilentlyContinue

# Clean up package.json
$packageJsonPath = Join-Path $TARGET_DIR "package.json"
if (Test-Path $packageJsonPath) {
    Write-Host "Cleaning package.json..."
    $packageJson = Get-Content $packageJsonPath -Raw | ConvertFrom-Json
    $packageJson.PSObject.Properties.Remove('scripts')
    $packageJson.PSObject.Properties.Remove('devDependencies')
    
    if ($packageJson.dependencies) {
        $newDeps = @{}
        $packageJson.dependencies.PSObject.Properties | ForEach-Object {
            if ($_.Value -notlike "workspace:*") {
                $newDeps[$_.Name] = $_.Value
            }
        }
        $packageJson.dependencies = $newDeps
    }
    
    $packageJson | ConvertTo-Json -Depth 10 | Set-Content $packageJsonPath
}

# Verify critical files exist
Write-Host "Verifying extension files..."
if (-not (Test-Path $packageJsonPath)) {
    Write-Error "ERROR: package.json not found!"
    exit 1
}

$distExtPath = Join-Path $TARGET_DIR "dist\extension.js"
if (-not (Test-Path $distExtPath)) {
    Write-Error "ERROR: dist\extension.js not found!"
    exit 1
}

$webviewPath = Join-Path $TARGET_DIR "webview-ui"
if (-not (Test-Path $webviewPath)) {
    Write-Error "ERROR: webview-ui directory not found!"
    exit 1
}

Write-Host "Roo-Code extension built successfully!"
Write-Host "Extension files:"
Get-ChildItem $TARGET_DIR | Select-Object -First 10 | Format-Table -AutoSize