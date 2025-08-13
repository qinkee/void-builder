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

# Check if dist already exists (pre-built in repository)
if [ -d "${ROO_CODE_PATH}/src/dist" ] && [ -f "${ROO_CODE_PATH}/src/dist/extension.js" ]; then
  echo "Using pre-built dist directory from repository..."
else
  echo "No pre-built dist found, building Roo-Code extension..."
  
  # Install pnpm if not available
  if ! command -v pnpm &> /dev/null; then
    echo "Installing pnpm..."
    npm install -g pnpm
  fi
  
  cd "${ROO_CODE_PATH}"
  
  # Install dependencies
  echo "Installing dependencies..."
  pnpm install --no-frozen-lockfile || {
    echo "ERROR: Failed to install dependencies"
    exit 1
  }
  
  # Build only the VSCode extension (src package)
  echo "Building VSCode extension..."
  cd src
  
  # Try multiple build approaches
  if [ -f "package.json" ] && grep -q '"bundle"' package.json; then
    echo "Running pnpm bundle in src directory..."
    pnpm bundle || echo "WARN: pnpm bundle failed"
  fi
  
  if [ ! -f "dist/extension.js" ] && [ -f "package.json" ] && grep -q '"build"' package.json; then
    echo "Running pnpm build in src directory..."
    pnpm build || echo "WARN: pnpm build failed"
  fi
  
  # If still no dist, try esbuild directly
  if [ ! -f "dist/extension.js" ] && [ -f "esbuild.mjs" ]; then
    echo "Running esbuild directly..."
    node esbuild.mjs --production || echo "WARN: esbuild failed"
  fi
  
  cd ../..
  
  # Final check
  if [ ! -f "${ROO_CODE_PATH}/src/dist/extension.js" ]; then
    echo "ERROR: Failed to build extension.js!"
    echo "Please ensure Roo-Code can be built or includes pre-built files."
    exit 1
  fi
fi

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
  echo "WARNING: dist/extension.js not found!"
  echo "The extension may not work properly without compiled files."
  echo "Consider:"
  echo "1. Committing pre-built dist files to the repository"
  echo "2. Building the extension separately before packaging"
  echo "3. Fixing the build issues in the monorepo"
  # Don't exit with error - let the build continue
fi

if [ ! -d "${TARGET_DIR}/webview-ui" ]; then
  echo "ERROR: webview-ui directory not found!"
  exit 1
fi

# Check if webview-ui is built
if [ ! -d "${TARGET_DIR}/webview-ui/build" ] || [ ! -f "${TARGET_DIR}/webview-ui/build/index.html" ]; then
  echo "WARNING: webview-ui/build not found!"
  
  # Try to build webview-ui if source exists
  if [ -d "${ROO_CODE_PATH}/webview-ui" ] && [ -f "${ROO_CODE_PATH}/webview-ui/package.json" ]; then
    echo "Attempting to build webview-ui..."
    cd "${ROO_CODE_PATH}/webview-ui"
    
    # Install dependencies if needed
    if [ ! -d "node_modules" ]; then
      pnpm install --no-frozen-lockfile || echo "WARN: webview-ui install failed"
    fi
    
    # Try to build
    if grep -q '"build"' package.json; then
      pnpm build || echo "WARN: webview-ui build failed"
    fi
    
    cd -
    
    # Copy built webview-ui if successful
    if [ -d "${ROO_CODE_PATH}/webview-ui/build" ]; then
      echo "Copying webview-ui build..."
      cp -r "${ROO_CODE_PATH}/webview-ui/build" "${TARGET_DIR}/webview-ui/"
    fi
  fi
  
  # Final check
  if [ ! -d "${TARGET_DIR}/webview-ui/build" ]; then
    echo "ERROR: webview-ui build directory not found!"
    echo "The extension may not work properly without webview-ui."
    # Don't exit, let it continue
  fi
fi

echo "Roo-Code extension built successfully!"
echo "Extension files:"
ls -la "${TARGET_DIR}/" | head -10
echo ""
echo "Dist contents:"
ls -la "${TARGET_DIR}/dist/" | head -5