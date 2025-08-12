#!/usr/bin/env bash

# Build Roo-Code extension and copy to VSCode extensions directory

set -ex

echo "Building Roo-Code extension..."

# Default to the path where get_roo_code.sh clones the repository
ROO_CODE_PATH="${ROO_CODE_PATH:-./roo-code}"
VSCODE_PATH="./vscode"
TARGET_DIR="${VSCODE_PATH}/.build/extensions/roo-code"

# Check if Roo-Code source exists
if [ ! -d "${ROO_CODE_PATH}/src" ]; then
  echo "Roo-Code source not found at ${ROO_CODE_PATH}/src"
  echo "Please run ./get_roo_code.sh first or set ROO_CODE_PATH correctly"
  exit 1
fi

# Create target directory
mkdir -p "${TARGET_DIR}"

# Build Roo-Code extension first
echo "Building Roo-Code extension..."
cd "${ROO_CODE_PATH}"

# Check if we should force rebuild
FORCE_REBUILD="${FORCE_REBUILD:-false}"

# Check if dist already exists (for local development)
if [ -d "src/dist" ] && [ -f "src/dist/extension.js" ] && [ "$FORCE_REBUILD" != "true" ]; then
  echo "Dist directory already exists, skipping build..."
  echo "To force rebuild, set FORCE_REBUILD=true"
else
  echo "Dist directory not found, building extension..."
  
  # Install dependencies using pnpm (Roo-Code uses pnpm workspace)
  echo "Installing dependencies..."
  if ! command -v pnpm &> /dev/null; then
    echo "ERROR: pnpm is required but not installed!"
    echo "Please install pnpm: npm install -g pnpm"
    exit 1
  fi
  
  pnpm install --frozen-lockfile
  
  # Build the extension
  echo "Compiling extension..."
  pnpm build || {
    echo "ERROR: Failed to build Roo-Code extension"
    exit 1
  }
  
  # Verify dist was created
  if [ ! -f "src/dist/extension.js" ]; then
    echo "ERROR: Build completed but src/dist/extension.js not found!"
    exit 1
  fi
fi

cd -

# Copy extension files
echo "Copying Roo-Code files..."
cp -r "${ROO_CODE_PATH}/src/"* "${TARGET_DIR}/"

# Remove development files
rm -rf "${TARGET_DIR}/node_modules"
rm -rf "${TARGET_DIR}/__tests__"
rm -rf "${TARGET_DIR}/__mocks__"
rm -rf "${TARGET_DIR}/.turbo"

# Clean up package.json
if [ -f "${TARGET_DIR}/package.json" ]; then
  echo "Cleaning package.json..."
  # Remove workspace protocol dependencies using jq
  if command -v jq &> /dev/null; then
    jq 'del(.scripts) | del(.devDependencies) | 
        if .dependencies then 
          .dependencies |= with_entries(select(.value | type == "string" and (startswith("workspace:") | not)))
        else . end' "${TARGET_DIR}/package.json" > "${TARGET_DIR}/package.json.tmp" && \
    mv "${TARGET_DIR}/package.json.tmp" "${TARGET_DIR}/package.json"
  else
    echo "Warning: jq not found, skipping package.json cleanup"
  fi
fi

# Verify critical files exist
echo "Verifying extension files..."
if [ ! -f "${TARGET_DIR}/package.json" ]; then
  echo "ERROR: package.json not found!"
  exit 1
fi

if [ ! -f "${TARGET_DIR}/dist/extension.js" ]; then
  echo "ERROR: dist/extension.js not found!"
  exit 1
fi

if [ ! -d "${TARGET_DIR}/webview-ui" ]; then
  echo "ERROR: webview-ui directory not found!"
  exit 1
fi

echo "Roo-Code extension built successfully!"
echo "Extension files:"
ls -la "${TARGET_DIR}/" | head -10
echo ""
echo "Dist contents:"
ls -la "${TARGET_DIR}/dist/" | head -5