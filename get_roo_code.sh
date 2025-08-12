#!/usr/bin/env bash

# Download and prepare Roo-Code from private repository for CI builds

set -ex

# Configuration
# Try to read from version file first
if [ -f "roo-code-version.json" ] && command -v jq &> /dev/null; then
  DEFAULT_VERSION=$(jq -r '.version' roo-code-version.json 2>/dev/null || echo "v3.25.11")
  DEFAULT_REPO=$(jq -r '.repo' roo-code-version.json 2>/dev/null || echo "https://github.com/YourPrivateOrg/roo-code-private")
else
  DEFAULT_VERSION="v3.25.11"
  DEFAULT_REPO="https://github.com/YourPrivateOrg/roo-code-private"
fi

ROO_CODE_VERSION="${ROO_CODE_VERSION:-$DEFAULT_VERSION}"
ROO_CODE_REPO="${ROO_CODE_REPO:-$DEFAULT_REPO}"
ROO_CODE_TOKEN="${ROO_CODE_TOKEN:-${GITHUB_TOKEN}}"

echo "Fetching Roo-Code ${ROO_CODE_VERSION} from private repository..."

# Ensure we have authentication token
if [ -z "${ROO_CODE_TOKEN}" ]; then
  echo "Error: ROO_CODE_TOKEN or GITHUB_TOKEN must be set for private repository access"
  exit 1
fi

# Clone Roo-Code repository with authentication
if [ ! -d "roo-code" ]; then
  # Use token authentication for private repository
  git clone --depth 1 --branch "${ROO_CODE_VERSION}" \
    "https://${ROO_CODE_TOKEN}@${ROO_CODE_REPO#https://}" roo-code
else
  cd roo-code
  # Set authentication for fetch
  git config remote.origin.url "https://${ROO_CODE_TOKEN}@${ROO_CODE_REPO#https://}"
  git fetch --depth 1 origin "${ROO_CODE_VERSION}"
  git checkout "${ROO_CODE_VERSION}"
  cd ..
fi

# Clean up authentication info
cd roo-code
git config --unset remote.origin.url 2>/dev/null || true
git config remote.origin.url "${ROO_CODE_REPO}"
cd ..

# Set the path for build script
export ROO_CODE_PATH="$(pwd)/roo-code"
echo "ROO_CODE_PATH=${ROO_CODE_PATH}" >> $GITHUB_ENV

echo "Roo-Code fetched successfully from private repository!"