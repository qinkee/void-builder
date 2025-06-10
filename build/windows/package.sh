#!/usr/bin/env bash
# shellcheck disable=SC1091

set -ex

if [[ "${CI_BUILD}" == "no" ]]; then
  exit 1
fi

tar -xzf ./vscode.tar.gz

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

# Copy im-components folder to build output (Windows packaging stage) - BEFORE gulp tasks
echo "Copying im-components to build output (Windows packaging)..."
if [[ -d "./im-components" ]]; then
  # Ensure out-build directory structure exists first
  mkdir -p "./out-build/vs/code/electron-sandbox/workbench/im-components"
  cp -r ./im-components/* ./out-build/vs/code/electron-sandbox/workbench/im-components/
  echo "✓ Copied im-components to ./out-build/vs/code/electron-sandbox/workbench/im-components/ (before gulp)"
else
  echo "Warning: im-components directory not found at ./im-components (Windows packaging)"
fi

npm run gulp "vscode-win32-${VSCODE_ARCH}-min-ci"


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
