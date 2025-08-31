#!/usr/bin/env bash
# 准备 electron-updater 所需的文件

set -e

echo "Preparing electron-updater files..."

# 确保 assets 目录存在
mkdir -p assets

# 函数：生成 latest.yml 文件
generate_latest_yml() {
  local platform=$1
  local arch=$2
  local exe_file=$3
  local yml_file=$4
  
  if [[ ! -f "${exe_file}" ]]; then
    echo "Warning: ${exe_file} not found, skipping ${yml_file}"
    return
  fi
  
  # 获取文件信息
  local file_size=$(stat -f%z "${exe_file}" 2>/dev/null || stat -c%s "${exe_file}" 2>/dev/null || echo "0")
  local file_name=$(basename "${exe_file}")
  local release_date=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  
  # 读取 SHA512 校验和
  local sha512=""
  if [[ -f "${exe_file}.sha512" ]]; then
    sha512=$(cat "${exe_file}.sha512" | awk '{print $1}')
  else
    # 如果没有 .sha512 文件，生成一个
    echo "Generating SHA512 for ${exe_file}..."
    if command -v shasum >/dev/null 2>&1; then
      sha512=$(shasum -a 512 "${exe_file}" | awk '{print $1}')
    elif command -v sha512sum >/dev/null 2>&1; then
      sha512=$(sha512sum "${exe_file}" | awk '{print $1}')
    else
      echo "Warning: Cannot generate SHA512, neither shasum nor sha512sum found"
    fi
  fi
  
  # 生成 latest.yml
  cat > "${yml_file}" << EOF
version: ${RELEASE_VERSION}
files:
  - url: ${file_name}
    sha512: ${sha512}
    size: ${file_size}
path: ${file_name}
sha512: ${sha512}
releaseDate: '${release_date}'
EOF
  
  echo "Generated ${yml_file}"
}

# 为 Windows 构建生成 latest.yml
if [[ "${OS_NAME}" == "windows" ]]; then
  # 系统安装包
  if [[ -f "assets/${APP_NAME}Setup-${VSCODE_ARCH}-${RELEASE_VERSION}.exe" ]]; then
    generate_latest_yml "win32" "${VSCODE_ARCH}" \
      "assets/${APP_NAME}Setup-${VSCODE_ARCH}-${RELEASE_VERSION}.exe" \
      "assets/latest.yml"
  fi
  
  # 用户安装包
  if [[ -f "assets/${APP_NAME}UserSetup-${VSCODE_ARCH}-${RELEASE_VERSION}.exe" ]]; then
    generate_latest_yml "win32" "${VSCODE_ARCH}" \
      "assets/${APP_NAME}UserSetup-${VSCODE_ARCH}-${RELEASE_VERSION}.exe" \
      "assets/latest-user.yml"
  fi
  
  # 为不同架构生成特定的 yml 文件
  if [[ "${VSCODE_ARCH}" == "x64" ]]; then
    if [[ -f "assets/latest.yml" ]]; then
      cp "assets/latest.yml" "assets/latest-x64.yml"
    fi
    if [[ -f "assets/latest-user.yml" ]]; then
      cp "assets/latest-user.yml" "assets/latest-user-x64.yml"
    fi
  elif [[ "${VSCODE_ARCH}" == "arm64" ]]; then
    if [[ -f "assets/latest.yml" ]]; then
      cp "assets/latest.yml" "assets/latest-arm64.yml"
    fi
    if [[ -f "assets/latest-user.yml" ]]; then
      cp "assets/latest-user.yml" "assets/latest-user-arm64.yml"
    fi
  fi
fi

# 为 macOS 构建生成 latest-mac.yml
if [[ "${OS_NAME}" == "macos" ]] || [[ "${OS_NAME}" == "osx" ]] || [[ "${OS_NAME}" == "darwin" ]]; then
  if [[ -f "assets/${APP_NAME}-darwin-${VSCODE_ARCH}-${RELEASE_VERSION}.zip" ]]; then
    generate_latest_yml "darwin" "${VSCODE_ARCH}" \
      "assets/${APP_NAME}-darwin-${VSCODE_ARCH}-${RELEASE_VERSION}.zip" \
      "assets/latest-mac.yml"
    
    # 为不同架构生成特定的 yml 文件
    if [[ "${VSCODE_ARCH}" == "x64" ]]; then
      cp "assets/latest-mac.yml" "assets/latest-mac-x64.yml"
    elif [[ "${VSCODE_ARCH}" == "arm64" ]]; then
      cp "assets/latest-mac.yml" "assets/latest-mac-arm64.yml"
    fi
  fi
fi

# 为 Linux 构建生成 latest-linux.yml
if [[ "${OS_NAME}" == "linux" ]]; then
  # AppImage 是 electron-updater 在 Linux 上的推荐格式
  appimage_file=""
  for file in assets/*.AppImage; do
    if [[ -f "${file}" ]]; then
      appimage_file="${file}"
      break
    fi
  done
  
  if [[ -n "${appimage_file}" ]]; then
    generate_latest_yml "linux" "${VSCODE_ARCH}" \
      "${appimage_file}" \
      "assets/latest-linux.yml"
    
    # 为不同架构生成特定的 yml 文件
    if [[ "${VSCODE_ARCH}" == "x64" ]]; then
      cp "assets/latest-linux.yml" "assets/latest-linux-x64.yml"
    elif [[ "${VSCODE_ARCH}" == "arm64" ]]; then
      cp "assets/latest-linux.yml" "assets/latest-linux-arm64.yml"
    fi
  fi
fi

# 生成 SHA512 校验和文件（如果还没有）
echo "Generating SHA512 checksums for electron-updater..."
cd assets
for file in *.exe *.zip *.AppImage *.dmg; do
  if [[ -f "${file}" ]] && [[ ! -f "${file}.sha512" ]]; then
    echo "Generating SHA512 for ${file}..."
    if command -v shasum >/dev/null 2>&1; then
      shasum -a 512 "${file}" > "${file}.sha512"
    elif command -v sha512sum >/dev/null 2>&1; then
      sha512sum "${file}" > "${file}.sha512"
    fi
  fi
done
cd ..

echo "Electron-updater preparation completed!"
echo "Generated files:"
ls -la assets/*.yml 2>/dev/null || echo "No .yml files generated"