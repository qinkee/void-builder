#!/usr/bin/env bash

APP_NAME="${APP_NAME:-Void}"
APP_NAME_LC="$( echo "${APP_NAME}" | awk '{print tolower($0)}' )"
BINARY_NAME="${BINARY_NAME:-void}"
GH_REPO_PATH="${GH_REPO_PATH:-TIMtechnology/void}"
ORG_NAME="${ORG_NAME:-TIMtechnology}"

echo "---------- utils.sh -----------"
echo "APP_NAME=\"${APP_NAME}\""
echo "APP_NAME_LC=\"${APP_NAME_LC}\""
echo "BINARY_NAME=\"${BINARY_NAME}\""
echo "GH_REPO_PATH=\"${GH_REPO_PATH}\""
echo "ORG_NAME=\"${ORG_NAME}\""

# All common functions can be added to this file

apply_patch() {
  if [[ -z "$2" ]]; then
    echo applying patch: "$1";
  fi
  # grep '^+++' "$1"  | sed -e 's#+++ [ab]/#./vscode/#' | while read line; do shasum -a 256 "${line}"; done

  cp $1{,.bak}

  replace "s|!!APP_NAME!!|${APP_NAME}|g" "$1"
  replace "s|!!APP_NAME_LC!!|${APP_NAME_LC}|g" "$1"
  replace "s|!!BINARY_NAME!!|${BINARY_NAME}|g" "$1"
  replace "s|!!GH_REPO_PATH!!|${GH_REPO_PATH}|g" "$1"
  replace "s|!!ORG_NAME!!|${ORG_NAME}|g" "$1"
  replace "s|!!RELEASE_VERSION!!|${RELEASE_VERSION}|g" "$1"

  if ! git apply --ignore-whitespace "$1"; then
    # Special handling for policies.patch
    if [[ "$(basename "$1")" == "policies.patch" ]]; then
      echo "Warning: policies.patch failed to apply. Attempting manual application..." >&2
      
      # Apply the changes manually
      echo "Applying policies changes manually..."
      
      # Update build/.moduleignore
      if [ -f "build/.moduleignore" ]; then
        replace 's/@vscode\/policy-watcher/@vscodium\/policy-watcher/g' build/.moduleignore
        replace 's/vscode-policy-watcher\.node/vscodium-policy-watcher\.node/g' build/.moduleignore
      fi
      
      # Update build/lib/policies.js
      if [ -f "build/lib/policies.js" ]; then
        replace 's/Software\\\\Policies\\\\Microsoft\\\\/Software\\\\Policies\\\\!!ORG_NAME!!\\\\/g' build/lib/policies.js
        replace 's/Microsoft\.Policies\./!!ORG_NAME!!\.Policies\./g' build/lib/policies.js
      fi
      
      # Update build/lib/policies.ts
      if [ -f "build/lib/policies.ts" ]; then
        replace 's/Software\\\\Policies\\\\Microsoft\\\\/Software\\\\Policies\\\\!!ORG_NAME!!\\\\/g' build/lib/policies.ts
        replace 's/Microsoft\.Policies\./!!ORG_NAME!!\.Policies\./g' build/lib/policies.ts
      fi
      
      # Update eslint.config.js
      if [ -f "eslint.config.js" ]; then
        replace "s/'@vscode\/policy-watcher',/'@vscodium\/policy-watcher',/g" eslint.config.js
      fi
      
      # Update package.json
      if [ -f "package.json" ]; then
        replace 's/"@vscode\/policy-watcher": "[^"]*"/"@vscodium\/policy-watcher": "^1.3.2-252465"/g' package.json
      fi
      
      # Update package-lock.json
      if [ -f "package-lock.json" ]; then
        # Replace all references to @vscode/policy-watcher with @vscodium/policy-watcher
        replace 's/"@vscode\/policy-watcher"/"@vscodium\/policy-watcher"/g' package-lock.json
        # Update the resolved URLs
        replace 's|https://registry.npmmirror.com/@vscode/policy-watcher/-/policy-watcher-[^"]*|https://registry.npmjs.org/@vscodium/policy-watcher/-/policy-watcher-1.3.2-252465.tgz|g' package-lock.json
        # Update version numbers in policy-watcher context
        replace 's/"version": "1\.3\.2"/"version": "1.3.2-252465"/g' package-lock.json
      fi
      
      # Update test files and source files
      find src -name "*.ts" -o -name "*.js" 2>/dev/null | xargs grep -l "@vscode/policy-watcher" 2>/dev/null | while read file; do
        replace 's/@vscode\/policy-watcher/@vscodium\/policy-watcher/g' "$file"
      done
      
      # Update the createWatcher call
      if [ -f "src/vs/platform/policy/node/nativePolicyService.ts" ]; then
        replace "s/createWatcher(this\.productName, policyDefinitions/createWatcher('!!ORG_NAME!!', this.productName, policyDefinitions/g" src/vs/platform/policy/node/nativePolicyService.ts
      fi
      
      # Clean up backup files
      find . -name "*.bak" -delete
      
      echo "Policies changes applied manually"
    else
      echo failed to apply patch "$1" >&2
      exit 1
    fi
  fi

  mv -f $1{.bak,}
}

exists() { type -t "$1" &> /dev/null; }

is_gnu_sed() {
  sed --version &> /dev/null
}

replace() {
  if is_gnu_sed; then
    sed -i -E "${1}" "${2}"
  else
    sed -i '' -E "${1}" "${2}"
  fi
}

if ! exists gsed; then
  if is_gnu_sed; then
    function gsed() {
      sed -i -E "$@"
    }
  else
    function gsed() {
      sed -i '' -E "$@"
    }
  fi
fi
