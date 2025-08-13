#!/usr/bin/env bash

# Copy pre-built Roo-Code extension to VSCode extensions directory

set -ex

echo "Copying Roo-Code extension..."

# Default to the path where get_roo_code.sh clones the repository
ROO_CODE_PATH="${ROO_CODE_PATH:-./roo-code}"
VSCODE_PATH="./vscode"
TARGET_DIR="${VSCODE_PATH}/.build/extensions/roo-cline"

# Check if Roo-Code source exists
if [ ! -d "${ROO_CODE_PATH}/src" ]; then
  echo "Roo-Code source not found at ${ROO_CODE_PATH}/src"
  echo "Please run ./get_roo_code.sh first or set ROO_CODE_PATH correctly"
  exit 1
fi

# Create target directory
mkdir -p "${TARGET_DIR}"

# Verify pre-built files exist
if [ ! -d "${ROO_CODE_PATH}/src/dist" ] || [ ! -f "${ROO_CODE_PATH}/src/dist/extension.js" ]; then
  echo "ERROR: Pre-built dist files not found in ${ROO_CODE_PATH}/src/dist!"
  echo "The Roo-Code repository must include pre-built dist files."
  exit 1
fi

if [ ! -d "${ROO_CODE_PATH}/src/webview-ui/build" ] || [ ! -f "${ROO_CODE_PATH}/src/webview-ui/build/index.html" ]; then
  echo "ERROR: Pre-built webview-ui files not found in ${ROO_CODE_PATH}/src/webview-ui/build!"
  echo "The Roo-Code repository must include pre-built webview-ui files."
  exit 1
fi

echo "Using pre-built files from repository..."

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

if [ ! -d "${TARGET_DIR}/webview-ui/build" ] || [ ! -f "${TARGET_DIR}/webview-ui/build/index.html" ]; then
  echo "ERROR: webview-ui/build not found!"
  exit 1
fi

echo "Roo-Code extension built successfully!"
echo "Extension files:"
ls -la "${TARGET_DIR}/" | head -10
echo ""
echo "Dist contents:"
ls -la "${TARGET_DIR}/dist/" | head -5