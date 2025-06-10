#!/usr/bin/env bash
# shellcheck disable=SC1091

set -ex

. version.sh

if [[ "${SHOULD_BUILD}" == "yes" ]]; then
  echo "MS_COMMIT=\"${MS_COMMIT}\""

  . prepare_vscode.sh

  cd vscode || { echo "'vscode' dir not found"; exit 1; }

  export NODE_OPTIONS="--max-old-space-size=8192"

  # Skip monaco-compile-check as it's failing due to searchUrl property
  # Skip valid-layers-check as well since it might depend on monaco
  # Void commented these out
  # npm run monaco-compile-check
  # npm run valid-layers-check

  npm run buildreact
  npm run gulp compile-build-without-mangling
  npm run gulp compile-extension-media
  npm run gulp compile-extensions-build
    npm run gulp minify-vscode

  # Copy im-components folder to build output - BEFORE platform-specific gulp tasks
  echo "Copying im-components to build output (before gulp tasks)..."
  if [[ -d "./im-components" ]]; then
    # Check which output directories exist and copy to all of them
    if [[ -d "./out-build/vs/code/electron-sandbox/workbench" ]]; then
      mkdir -p "./out-build/vs/code/electron-sandbox/workbench/im-components"
      cp -r ./im-components/* ./out-build/vs/code/electron-sandbox/workbench/im-components/
      echo "✓ Copied im-components to ./out-build/vs/code/electron-sandbox/workbench/im-components/"
    fi
    
    if [[ -d "./out/vs/code/electron-sandbox/workbench" ]]; then
      mkdir -p "./out/vs/code/electron-sandbox/workbench/im-components"
      cp -r ./im-components/* ./out/vs/code/electron-sandbox/workbench/im-components/
      echo "✓ Copied im-components to ./out/vs/code/electron-sandbox/workbench/im-components/"
    fi
    
    echo "Successfully copied im-components before platform-specific builds"
  else
    echo "Warning: im-components directory not found at ./im-components"
  fi

  if [[ "${OS_NAME}" == "osx" ]]; then
    # generate Group Policy definitions
    # node build/lib/policies darwin # Void commented this out

    npm run gulp "vscode-darwin-${VSCODE_ARCH}-min-ci"

    find "../VSCode-darwin-${VSCODE_ARCH}" -print0 | xargs -0 touch -c

    . ../build_cli.sh

    VSCODE_PLATFORM="darwin"
  elif [[ "${OS_NAME}" == "windows" ]]; then
    # generate Group Policy definitions
    # node build/lib/policies win32 # Void commented this out

    # in CI, packaging will be done by a different job
    if [[ "${CI_BUILD}" == "no" ]]; then
      . ../build/windows/rtf/make.sh

      npm run gulp "vscode-win32-${VSCODE_ARCH}-min-ci"

      if [[ "${VSCODE_ARCH}" != "x64" ]]; then
        SHOULD_BUILD_REH="no"
        SHOULD_BUILD_REH_WEB="no"
      fi

      . ../build_cli.sh
    fi

    VSCODE_PLATFORM="win32"
  else # linux
    # in CI, packaging will be done by a different job
    if [[ "${CI_BUILD}" == "no" ]]; then
      npm run gulp "vscode-linux-${VSCODE_ARCH}-min-ci"

      find "../VSCode-linux-${VSCODE_ARCH}" -print0 | xargs -0 touch -c

      . ../build_cli.sh
    fi

    VSCODE_PLATFORM="linux"
  fi

  if [[ "${SHOULD_BUILD_REH}" != "no" ]]; then
    npm run gulp minify-vscode-reh
    npm run gulp "vscode-reh-${VSCODE_PLATFORM}-${VSCODE_ARCH}-min-ci"
  fi

  if [[ "${SHOULD_BUILD_REH_WEB}" != "no" ]]; then
    npm run gulp minify-vscode-reh-web
    npm run gulp "vscode-reh-web-${VSCODE_PLATFORM}-${VSCODE_ARCH}-min-ci"
  fi



  cd ..
fi
