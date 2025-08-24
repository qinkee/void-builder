# 版本管理指南

## 版本号规范

Void 使用标准的语义化版本号 (Semantic Versioning):

```
MAJOR.MINOR.PATCH
```

例如: `1.99.8`

- **MAJOR**: 主版本号，重大更新
- **MINOR**: 次版本号，功能更新
- **PATCH**: 补丁版本号，bug修复

## 版本号管理

### 1. 版本号存储位置

- `/void-builder/void-version.json` - 主版本控制文件
- `/void/package.json` - Void 项目版本
- GitHub Release Tag - 发布版本标签

### 2. 更新版本号

#### 方法 A: 使用同步脚本（推荐）

```bash
cd void-builder
./sync_version.sh 1.99.9
```

#### 方法 B: 手动更新

1. 编辑 `void-version.json`:
```json
{
  "version": "1.99.9"
}
```

2. 同步到其他文件:
```bash
./sync_version.sh
```

### 3. 发布新版本

#### 通过 GitHub Actions（推荐）

1. 更新版本号
2. 提交更改:
```bash
git add -A
git commit -m "Bump version to 1.99.9"
git push
```

3. 触发构建:
   - 方式1: 在 GitHub Actions 页面手动触发
   - 方式2: 创建 tag 并推送:
   ```bash
   git tag v1.99.9
   git push --tags
   ```

#### 手动指定版本

在 GitHub Actions 运行时，可以在 "void_release" 输入框中指定版本号，如 `1.99.9`

### 4. 版本号规则

- **开发版本**: `1.99.x` (当前系列)
- **正式版本**: `2.0.0` (下一个主版本)
- **紧急修复**: 增加 PATCH 号，如 `1.99.8` -> `1.99.9`
- **功能更新**: 增加 MINOR 号，如 `1.99.9` -> `1.100.0`
- **重大更新**: 增加 MAJOR 号，如 `1.99.9` -> `2.0.0`

### 5. 自动更新兼容性

确保版本号递增以触发自动更新:
- ✅ `1.99.7` -> `1.99.8` (正确)
- ✅ `1.99.9` -> `1.100.0` (正确)
- ❌ `1.99.8` -> `1.99.8` (不会触发更新)
- ❌ `1.99.8` -> `1.99.7` (版本回退)

### 6. 版本检查

运行以下命令检查当前版本:
```bash
# 查看 void-version.json
cat void-version.json | jq -r '.version'

# 查看 void package.json
cat ../void/package.json | jq -r '.version'

# 查看最新发布版本
curl -s https://api.github.com/repos/qinkee/binaries/releases/latest | jq -r '.tag_name'
```

## 故障排除

### 版本号不一致

如果发现版本号不一致，运行同步脚本:
```bash
./sync_version.sh 1.99.8
```

### 自动更新不工作

检查:
1. 新版本号是否大于当前版本
2. `latest.yml` 文件是否正确生成
3. GitHub Release 是否为正式发布（非 draft）

### 版本号格式错误

确保使用标准三段式格式 `x.y.z`，不要使用:
- ❌ `1.99.60051`
- ❌ `1.99`
- ❌ `1.99.8.1`
- ✅ `1.99.8`