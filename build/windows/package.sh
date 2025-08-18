#!/usr/bin/env bash
# shellcheck disable=SC1091

set -ex

if [[ "${CI_BUILD}" == "no" ]]; then
  exit 1
fi

tar -xzf ./vscode.tar.gz

# Debug: Check if Roo-Code was included in the artifact
if [ -d "vscode/.build/extensions/roo-cline" ]; then
  echo "✓ Roo-Code extension found in extracted artifact"
  ls -la "vscode/.build/extensions/roo-cline/" | head -5
else
  echo "✗ Roo-Code extension NOT found in extracted artifact!"
  echo "Available extensions:"
  ls "vscode/.build/extensions/" | head -10
fi

cd vscode || { echo "'vscode' dir not found"; exit 1; }

for i in {1..5}; do # try 5 times
  npm ci && break
  if [[ $i -eq 3 ]]; then
    echo "Npm install failed too many times" >&2
    exit 1
  fi
  echo "Npm install failed $i, trying again..."
done

node build/azure-pipelines/distro/mixin-npm

. ../build/windows/rtf/make.sh

npm run gulp "vscode-win32-${VSCODE_ARCH}-min-ci"

# Ensure Roo-Code is included in Windows build
if [[ "${INCLUDE_ROO_CODE}" == "yes" || "${BUILD_ROO_CODE}" == "yes" ]]; then
  echo "Checking Roo-Code integration..."
  
  # First check if it's in .build/extensions
  if [ -d ".build/extensions/roo-cline" ]; then
    echo "✓ Roo-Code found in .build/extensions/roo-cline"
  else
    echo "✗ Roo-Code NOT found in .build/extensions/roo-cline"
  fi
  
  # Then check if gulp task included it in the final package
  if [ -d "../VSCode-win32-${VSCODE_ARCH}/resources/app/extensions/roo-cline" ]; then
    echo "✓ Roo-Code successfully included in final package"
    ls -la "../VSCode-win32-${VSCODE_ARCH}/resources/app/extensions/roo-cline/" | head -5
  else
    echo "✗ Roo-Code NOT in final package, attempting manual copy..."
    if [ -d ".build/extensions/roo-cline" ] && [ -d "../VSCode-win32-${VSCODE_ARCH}/resources/app/extensions" ]; then
      cp -r ".build/extensions/roo-cline" "../VSCode-win32-${VSCODE_ARCH}/resources/app/extensions/"
      echo "✓ Manually copied Roo-Code to final package"
    else
      echo "✗ Failed to copy Roo-Code - source or destination not found"
    fi
  fi
fi

. ../build_cli.sh

if [[ "${VSCODE_ARCH}" == "x64" ]]; then
  if [[ "${SHOULD_BUILD_REH}" != "no" ]]; then
    echo "Building REH"
    npm run gulp minify-vscode-reh
    npm run gulp "vscode-reh-win32-${VSCODE_ARCH}-min-ci"
  fi

  if [[ "${SHOULD_BUILD_REH_WEB}" != "no" ]]; then
    echo "Building REH-web"
    npm run gulp minify-vscode-reh-web
    npm run gulp "vscode-reh-web-win32-${VSCODE_ARCH}-min-ci"
  fi
fi

cd ..
