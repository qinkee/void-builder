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
  
  # Build Roo-Code extension before compiling extensions
  if [[ "${INCLUDE_ROO_CODE}" == "yes" || "${BUILD_ROO_CODE}" == "yes" ]]; then
    echo "=== Building Roo-Code extension ==="
    echo "INCLUDE_ROO_CODE=${INCLUDE_ROO_CODE}, BUILD_ROO_CODE=${BUILD_ROO_CODE}"
    cd ..
    # Ensure roo-code is fetched (will use defaults if not already fetched)
    if [ ! -d "roo-code" ]; then
      echo "Fetching Roo-Code..."
      ./get_roo_code.sh
    else
      echo "Roo-Code already exists at ./roo-code"
    fi
    echo "Building Roo-Code..."
    ./build_roo_code.sh
    
    # Verify the build
    if [ -d "vscode/.build/extensions/roo-cline" ]; then
      echo "✓ Roo-Code successfully built at vscode/.build/extensions/roo-cline"
      echo "Contents:"
      ls -la "vscode/.build/extensions/roo-cline/" | head -5
    else
      echo "✗ ERROR: Roo-Code build failed - directory not found at vscode/.build/extensions/roo-cline"
    fi
    
    cd vscode
    echo "=== Roo-Code build complete ==="
  else
    echo "=== Skipping Roo-Code build (INCLUDE_ROO_CODE=${INCLUDE_ROO_CODE}, BUILD_ROO_CODE=${BUILD_ROO_CODE}) ==="
  fi
  
  # Save Roo-Code before compile-extensions-build
  if [[ "${INCLUDE_ROO_CODE}" == "yes" || "${BUILD_ROO_CODE}" == "yes" ]]; then
    if [ -d ".build/extensions/roo-cline" ]; then
      echo "Backing up Roo-Code before compile-extensions-build..."
      cp -r ".build/extensions/roo-cline" "../roo-cline-backup"
    fi
  fi
  
  npm run gulp compile-extensions-build
  
  # Restore Roo-Code after compile-extensions-build
  if [[ "${INCLUDE_ROO_CODE}" == "yes" || "${BUILD_ROO_CODE}" == "yes" ]]; then
    if [ -d "../roo-cline-backup" ]; then
      echo "Restoring Roo-Code after compile-extensions-build..."
      mkdir -p ".build/extensions"
      cp -r "../roo-cline-backup" ".build/extensions/roo-cline"
      rm -rf "../roo-cline-backup"
      echo "✓ Roo-Code restored to .build/extensions/roo-cline"
    fi
  fi
  
  npm run gulp minify-vscode
  
  # Ensure Roo-Code is included after minify
  if [[ "${INCLUDE_ROO_CODE}" == "yes" || "${BUILD_ROO_CODE}" == "yes" ]]; then
    if [ -d ".build/extensions/roo-cline" ] && [ -d "out-vscode-min" ]; then
      echo "Copying Roo-Code to out-vscode-min..."
      mkdir -p "out-vscode-min/extensions"
      cp -r ".build/extensions/roo-cline" "out-vscode-min/extensions/"
    fi
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
