#!/usr/bin/env bash

# 强制在压缩前确保 Roo-Code 存在
set -ex

echo "=== FORCE INCLUDING ROO-CODE ==="

# 检查是否应该包含 Roo-Code
if [[ "${INCLUDE_ROO_CODE}" != "yes" ]]; then
  echo "INCLUDE_ROO_CODE is not 'yes', skipping..."
  exit 0
fi

# 确保 roo-code 源码存在
if [ ! -d "./roo-code" ]; then
  echo "ERROR: ./roo-code directory not found!"
  echo "Current directory: $(pwd)"
  echo "Directory contents:"
  ls -la
  exit 1
fi

# 创建目标目录
mkdir -p vscode/.build/extensions/roo-cline

# 直接复制所有需要的文件（不包括 node_modules）
echo "Copying Roo-Code files..."
rsync -av --exclude='node_modules' --exclude='__tests__' --exclude='__mocks__' --exclude='.turbo' \
  ./roo-code/src/ vscode/.build/extensions/roo-cline/

echo "Roo-Code files copied successfully!"
echo "Contents of roo-cline:"
ls -la vscode/.build/extensions/roo-cline/ | head -10

echo "=== FORCE INCLUDING COMPLETE ==="