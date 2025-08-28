#!/usr/bin/env bash
# shellcheck disable=SC2129

set -e

# Echo all environment variables used by this script
echo "----------- get_repo -----------"
echo "Environment variables:"
echo "CI_BUILD=${CI_BUILD}"
echo "GITHUB_REPOSITORY=${GITHUB_REPOSITORY}"
echo "RELEASE_VERSION=${RELEASE_VERSION}"
echo "VSCODE_LATEST=${VSCODE_LATEST}"
echo "VSCODE_QUALITY=${VSCODE_QUALITY}"
echo "GITHUB_ENV=${GITHUB_ENV}"
echo "GITHUB_TOKEN=${GITHUB_TOKEN}"

echo "SHOULD_DEPLOY=${SHOULD_DEPLOY}"
echo "SHOULD_BUILD=${SHOULD_BUILD}"
echo "-------------------------"

# git workaround
if [[ "${CI_BUILD}" != "no" ]]; then
  git config --global --add safe.directory "/__w/$( echo "${GITHUB_REPOSITORY}" | awk '{print tolower($0)}' )"
fi

VOID_BRANCH="master"
echo "Cloning void ${VOID_BRANCH}..."

mkdir -p vscode
cd vscode || { echo "'vscode' dir not found"; exit 1; }

git init -q

# Use authenticated URL if GITHUB_TOKEN is available (for private repos)
if [[ -n "${GITHUB_TOKEN}" ]]; then
  echo "Using authenticated clone with GitHub token"
  git remote add origin https://${GITHUB_TOKEN}@github.com/qinkee/ShadanAI-Workbench.git
else
  echo "Using public clone (no token provided)"
  git remote add origin https://github.com/qinkee/ShadanAI-Workbench.git
fi


# Allow callers to specify a particular commit to checkout via the
# environment variable VOID_COMMIT.  We still default to the tip of the
# ${VOID_BRANCH} branch when the variable is not provided.  Keeping
# VOID_BRANCH as "main" ensures the rest of the script (and downstream
# consumers) behave exactly as before.
if [[ -n "${VOID_COMMIT}" ]]; then
  echo "Using explicit commit ${VOID_COMMIT}"
  # Fetch just that commit to keep the clone shallow.
  git fetch --depth 1 origin "${VOID_COMMIT}"
  git checkout "${VOID_COMMIT}"
else
  git fetch --depth 1 origin "${VOID_BRANCH}"
  git checkout FETCH_HEAD
fi

MS_TAG=$( jq -r '.version' "package.json" )
MS_COMMIT=$VOID_BRANCH # Void - MS_COMMIT doesn't seem to do much

# Void - 使用标准三段式版本号
# 版本号优先级: GitHub Actions 输入 > void-version.json > package.json
if [[ -n "${VOID_RELEASE}" ]]; then 
  # 优先使用 GitHub Actions 输入的自定义版本号
  RELEASE_VERSION="${VOID_RELEASE}"
  echo "Using custom version from GitHub Actions input: ${RELEASE_VERSION}"
else
  # 默认使用 package.json 中的版本
  RELEASE_VERSION="${MS_TAG}"
  echo "Using package.json version: ${RELEASE_VERSION}"
fi

# 验证版本号格式 (major.minor.patch)
if ! echo "${RELEASE_VERSION}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Warning: Version ${RELEASE_VERSION} does not follow semver format (x.y.z)"
fi

VOID_VERSION="${RELEASE_VERSION}" # 保持 VOID_VERSION 与 RELEASE_VERSION 一致


echo "RELEASE_VERSION=\"${RELEASE_VERSION}\""
echo "MS_COMMIT=\"${MS_COMMIT}\""
echo "MS_TAG=\"${MS_TAG}\""

cd ..

# for GH actions
if [[ "${GITHUB_ENV}" ]]; then
  echo "MS_TAG=${MS_TAG}" >> "${GITHUB_ENV}"
  echo "MS_COMMIT=${MS_COMMIT}" >> "${GITHUB_ENV}"
  echo "RELEASE_VERSION=${RELEASE_VERSION}" >> "${GITHUB_ENV}"
  echo "VOID_VERSION=${VOID_VERSION}" >> "${GITHUB_ENV}" # Void added this
fi



echo "----------- get_repo exports -----------"
echo "MS_TAG ${MS_TAG}"
echo "MS_COMMIT ${MS_COMMIT}"
echo "RELEASE_VERSION ${RELEASE_VERSION}"
echo "VOID VERSION ${VOID_VERSION}"
echo "----------------------"


export MS_TAG
export MS_COMMIT
export RELEASE_VERSION
export VOID_VERSION
