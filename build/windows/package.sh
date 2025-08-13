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

npm run gulp "vscode-win32-${VSCODE_ARCH}-min-ci"

# Ensure Roo-Code is included in Windows build
if [[ "${INCLUDE_ROO_CODE}" == "yes" || "${BUILD_ROO_CODE}" == "yes" ]]; then
  if [ -d ".build/extensions/roo-cline" ]; then
    echo "Ensuring Roo-Code is included in Windows package..."
    # The gulp task should have already included it, but let's verify
    if [ -d "../VSCode-win32-${VSCODE_ARCH}/resources/app/extensions" ]; then
      if [ ! -d "../VSCode-win32-${VSCODE_ARCH}/resources/app/extensions/roo-cline" ]; then
        echo "Copying Roo-Code to Windows package..."
        cp -r ".build/extensions/roo-cline" "../VSCode-win32-${VSCODE_ARCH}/resources/app/extensions/"
      fi
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
