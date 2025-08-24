#!/usr/bin/env bash
# 同步版本号到各个地方

set -e

# 读取版本号
if [[ -f "void-version.json" ]]; then
  VERSION=$( jq -r '.version' "void-version.json" )
elif [[ -n "$1" ]]; then
  VERSION="$1"
else
  echo "Usage: ./sync_version.sh [version]"
  echo "Or create void-version.json with version field"
  exit 1
fi

# 验证版本号格式
if ! echo "${VERSION}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Error: Version ${VERSION} does not follow semver format (x.y.z)"
  exit 1
fi

echo "Syncing version ${VERSION} to all locations..."

# 1. 更新 void-version.json
if [[ -f "void-version.json" ]]; then
  jq --arg v "${VERSION}" '.version = $v' void-version.json > tmp.json && mv tmp.json void-version.json
else
  echo "{\"version\": \"${VERSION}\"}" | jq '.' > void-version.json
fi

# 2. 更新 void 项目的 package.json
if [[ -f "../void/package.json" ]]; then
  echo "Updating ../void/package.json"
  jq --arg v "${VERSION}" '.version = $v' ../void/package.json > tmp.json && mv tmp.json ../void/package.json
fi

# 3. 如果在 void 项目目录下
if [[ -f "vscode/package.json" ]]; then
  echo "Updating vscode/package.json"
  jq --arg v "${VERSION}" '.version = $v' vscode/package.json > tmp.json && mv tmp.json vscode/package.json
fi

echo "Version ${VERSION} synced successfully!"
echo ""
echo "Next steps:"
echo "1. Commit changes: git add -A && git commit -m \"Bump version to ${VERSION}\""
echo "2. Tag release: git tag v${VERSION}"
echo "3. Push to trigger build: git push && git push --tags"