#!/usr/bin/env bash

# Ensure Roo-Code extension is included in the final build
# This script should be called after the main build process

set -e

echo "Ensuring Roo-Code extension is included in the build..."

VSCODE_PATH="./vscode"
ROO_CODE_SOURCE="${VSCODE_PATH}/.build/extensions/roo-cline"

# Check if Roo-Code was built
if [ ! -d "${ROO_CODE_SOURCE}" ]; then
  echo "Roo-Code extension not found at ${ROO_CODE_SOURCE}"
  echo "This is expected if INCLUDE_ROO_CODE is not set"
  exit 0
fi

echo "Roo-Code extension found at ${ROO_CODE_SOURCE}"

# Find all VSCode build output directories and copy Roo-Code there
for BUILD_DIR in "${VSCODE_PATH}"/out-vscode*/; do
  if [ -d "${BUILD_DIR}" ]; then
    TARGET="${BUILD_DIR}extensions/roo-cline"
    if [ ! -d "${TARGET}" ]; then
      echo "Copying Roo-Code to ${TARGET}..."
      mkdir -p "$(dirname "${TARGET}")"
      cp -r "${ROO_CODE_SOURCE}" "${TARGET}"
    else
      echo "Roo-Code already exists at ${TARGET}"
    fi
  fi
done

# Also ensure it's in the Electron app resources
for APP_DIR in ../VSCode-*/; do
  if [ -d "${APP_DIR}" ]; then
    RESOURCES_DIR="${APP_DIR}resources/app/extensions"
    if [ -d "${RESOURCES_DIR}" ]; then
      TARGET="${RESOURCES_DIR}/roo-cline"
      if [ ! -d "${TARGET}" ]; then
        echo "Copying Roo-Code to ${TARGET}..."
        cp -r "${ROO_CODE_SOURCE}" "${TARGET}"
      else
        echo "Roo-Code already exists at ${TARGET}"
      fi
    fi
  fi
done

echo "Roo-Code inclusion check complete!"