#!/usr/bin/env bash

# Download and prepare Roo-Code from private repository for CI builds

set -ex

# Configuration
# Try to read from version file first
if [ -f "roo-code-version.json" ] && command -v jq &> /dev/null; then
  DEFAULT_BRANCH=$(jq -r '.branch // .version // "master"' roo-code-version.json 2>/dev/null || echo "master")
  DEFAULT_REPO=$(jq -r '.repo' roo-code-version.json 2>/dev/null || echo "https://github.com/qinkee/Roo-Code.git")
else
  DEFAULT_BRANCH="master"
  DEFAULT_REPO="https://github.com/qinkee/Roo-Code.git"
fi

ROO_CODE_BRANCH="${ROO_CODE_BRANCH:-${ROO_CODE_VERSION:-$DEFAULT_BRANCH}}"
ROO_CODE_REPO="${ROO_CODE_REPO:-$DEFAULT_REPO}"
ROO_CODE_TOKEN="${ROO_CODE_TOKEN:-${GITHUB_TOKEN}}"

echo "Fetching Roo-Code from ${ROO_CODE_BRANCH} branch of private repository..."

# Ensure we have authentication token
if [ -z "${ROO_CODE_TOKEN}" ]; then
  echo "Error: ROO_CODE_TOKEN or GITHUB_TOKEN must be set for private repository access"
  exit 1
fi

# Clean up existing directory
rm -rf roo-code

# Clone Roo-Code repository with authentication
# Use token authentication for private repository
git clone --depth 1 --branch "${ROO_CODE_BRANCH}" \
  "https://${ROO_CODE_TOKEN}@${ROO_CODE_REPO#https://}" roo-code

# Clean up authentication info
cd roo-code
git config --unset remote.origin.url 2>/dev/null || true
git config remote.origin.url "${ROO_CODE_REPO}"
cd ..

# Set the path for build script
export ROO_CODE_PATH="$(pwd)/roo-code"
echo "ROO_CODE_PATH=${ROO_CODE_PATH}" >> $GITHUB_ENV

echo "Roo-Code fetched successfully from private repository!"