# 自动更新系统检查清单

## ✅ 已完成的配置

### 1. Void 项目端 (electron-updater 集成)
- ✅ **VoidUpdateMainServiceV2** 服务已实现并注册
  - 位置: `void/src/vs/workbench/contrib/void/electron-main/voidUpdateMainServiceV2.ts`
  - 已修复 electron-updater 模块加载问题
  - 已修复 GitHub URL 解析问题
  - 已添加开发环境强制更新配置

- ✅ **更新源配置**
  - product.json 中配置了 updateUrl: `https://api.github.com/repos/qinkee/binaries/releases/latest`
  - 服务正确解析为: owner=`qinkee`, repo=`binaries`

- ✅ **版本号标准化**
  - 已从 `1.99.60051` 改为标准语义化版本 `1.99.8`
  - void/package.json 版本已更新为 `1.99.8`

### 2. Void-Builder 构建端
- ✅ **版本管理**
  - 创建了 `void-version.json` 作为中心版本控制文件
  - 创建了 `sync_version.sh` 脚本同步版本
  - `get_repo.sh` 已更新，使用标准版本格式

- ✅ **GitHub Actions 工作流**
  - stable-windows.yml 已配置 prepare_electron_updater 步骤
  - stable-macos.yml 已配置 prepare_electron_updater 步骤
  - stable-linux.yml 已配置 prepare_electron_updater 步骤
  - 环境变量正确传递: RELEASE_VERSION, APP_NAME, VSCODE_ARCH, OS_NAME

- ✅ **构建脚本**
  - `prepare_electron_updater.sh` 生成 latest.yml 文件
  - `release.sh` 支持上传 .yml 文件到 GitHub Release

## ⚠️ 关键检查点

### 构建前检查
1. **版本号一致性**
   ```bash
   # 检查版本号是否同步
   cat void-builder/void-version.json | jq -r '.version'  # 应该是 1.99.8
   cat void/package.json | jq -r '.version'                # 应该是 1.99.8
   ```

2. **确保版本递增**
   - 新版本 (1.99.8) 必须大于当前发布版本 (1.99.7)
   - 否则 electron-updater 不会触发更新

### 构建时监控
1. **GitHub Actions 日志检查**
   - ✅ get_repo.sh 输出正确版本: `RELEASE_VERSION 1.99.8`
   - ✅ prepare_electron_updater.sh 生成 latest.yml
   - ✅ release.sh 上传所有文件包括 .yml

2. **生成的文件**
   - Windows: `latest.yml`, `VoidSetup-x64-1.99.8.exe`
   - macOS: `latest-mac.yml`, `Void-darwin-x64-1.99.8.zip` (如果有构建)
   - Linux: `latest-linux.yml`, `*.AppImage` (如果有构建)

### 构建后验证
1. **GitHub Release 检查**
   ```bash
   # 检查 latest.yml 是否存在
   curl -L https://github.com/qinkee/binaries/releases/latest/download/latest.yml
   
   # 验证版本号
   curl -s https://github.com/qinkee/binaries/releases/latest/download/latest.yml | grep version
   ```

2. **latest.yml 内容验证**
   应包含:
   - version: 1.99.8
   - files 数组包含安装包信息
   - sha512 校验和
   - releaseDate

## 🔍 Windows 客户端调试

### 开发环境调试
1. **启动日志位置**
   - 主进程日志: 控制台输出
   - 查看包含 `[VoidUpdateV2]` 的日志

2. **关键日志点**
   ```
   [VoidUpdateV2] Initializing electron-updater service
   [VoidUpdateV2] Configured GitHub update source: qinkee/binaries
   [VoidUpdateV2] Checking for update...
   [VoidUpdateV2] Update available: 1.99.8 (如果有新版本)
   ```

### 生产环境调试
1. **日志文件位置**
   - Windows: `%APPDATA%\Void\logs\main.log`
   - 搜索 `VoidUpdateV2` 关键字

2. **手动触发更新检查**
   - 菜单: 帮助 → 检查更新
   - 或等待30秒自动检查

## 🚀 发布流程

1. **更新版本号**
   ```bash
   cd void-builder
   ./sync_version.sh 1.99.8
   ```

2. **提交更改**
   ```bash
   git add -A
   git commit -m "发布版本 1.99.8"
   git push
   ```

3. **触发 GitHub Actions**
   - 方式1: 在 Actions 页面手动触发，输入 void_release: `1.99.8`
   - 方式2: 创建并推送 tag
   ```bash
   git tag v1.99.8
   git push --tags
   ```

4. **监控构建**
   - 查看 GitHub Actions 运行状态
   - 确保所有平台构建成功
   - 验证 Release 创建和文件上传

5. **验证更新**
   - 等待构建完成（约30-45分钟）
   - 启动旧版本 Void (1.99.7)
   - 等待30秒或手动检查更新
   - 确认检测到新版本 1.99.8

## ❌ 常见问题

### 问题1: 没有检测到更新
- 检查 latest.yml 是否存在于 GitHub Release
- 验证版本号是否正确递增
- 查看客户端日志是否有错误

### 问题2: latest.yml 未生成
- 检查 GitHub Actions 环境变量是否正确设置
- 验证 prepare_electron_updater.sh 是否执行
- 确认安装包文件存在于 assets 目录

### 问题3: 404 错误
- 确认 GitHub Release 不是 draft 状态
- 验证 URL 格式正确: `https://github.com/qinkee/binaries/releases/latest/download/latest.yml`

### 问题4: 版本比较失败
- 确保使用标准语义化版本 (x.y.z)
- 避免使用非标准格式如 1.99.60051

## 📝 注意事项

1. **版本号格式**
   - ✅ 正确: `1.99.8`, `2.0.0`, `1.100.0`
   - ❌ 错误: `1.99.60051`, `1.99`, `1.99.8.1`

2. **自动更新条件**
   - 新版本号必须大于当前版本
   - latest.yml 必须可访问
   - GitHub Release 必须是正式发布（非 draft）

3. **测试建议**
   - 先在测试环境验证
   - 保留旧版本安装包用于回滚
   - 监控用户反馈和错误报告