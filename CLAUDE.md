# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is void-builder, a fork of VSCodium used to build the Void editor. It leverages VSCodium's build pipeline to create Void distributions with telemetry removed and custom branding applied.

## Key Commands

### Building Void
```bash
# Full build (requires vscode source)
./build.sh

# Platform-specific builds
./build/windows/build.sh  # Windows
./build_darwin.sh         # macOS
./build.sh                # Linux (default)
```

### Version Management
```bash
# Update version across all files
./sync_version.sh 1.99.9

# Check current version
cat void-version.json | jq -r '.version'
```

### Roo-Code Integration
```bash
# Fetch Roo-Code (requires auth)
export ROO_CODE_TOKEN="your-github-pat"
export ROO_CODE_REPO="https://github.com/YourOrg/roo-code-private"
export INCLUDE_ROO_CODE=yes
./get_roo_code.sh

# Build Roo-Code extension
./build_roo_code.sh
```

### Testing & Verification
```bash
# Verify patches apply cleanly
./check_tags.sh

# Check build outputs
ls -la build/win32/  # Windows artifacts
ls -la build/linux/  # Linux artifacts
ls -la build/darwin/ # macOS artifacts
```

## Architecture & Structure

### Build Pipeline Flow
1. **prepare_vscode.sh** - Fetches VS Code source and applies patches
2. **patches/** - Contains modifications to remove telemetry and rebrand to Void
3. **build.sh** - Main build orchestrator that:
   - Compiles VS Code with patches
   - Integrates Roo-Code extension if enabled
   - Runs minification and packaging
4. **GitHub Actions** - Automated builds for all platforms via workflows in `.github/workflows/`

### Key Directories
- `patches/` - VS Code modifications (telemetry removal, branding changes)
- `build/` - Platform-specific build scripts and assets
- `.github/workflows/` - CI/CD pipeline definitions
- `vscode/` - VS Code source (created during build)
- `roo-code/` - Roo-Code extension source (when fetched)

### Important Environment Variables
- `INCLUDE_ROO_CODE` - Enable Roo-Code integration
- `BUILD_ROO_CODE` - Force Roo-Code build
- `VSCODE_ARCH` - Target architecture (x64, arm64)
- `OS_NAME` - Target OS (osx, windows, linux)
- `MS_COMMIT` - VS Code commit to build from

### Patch System
Patches in `patches/` directory modify VS Code to:
- Remove telemetry and tracking
- Replace VS Code branding with Void
- Update auto-update URLs to point to Void infrastructure
- Disable certain VS Code features (marketplace, cloud services)

Key patches:
- `brand.patch` - Main branding changes
- `disable-telemetry.patch` - Remove telemetry
- `product-json.patch` - Update product configuration
- `add-remote-url.patch` - Update remote server URLs

### Version Management
Version is maintained in multiple places:
- `void-version.json` - Primary version source
- Build artifacts use this version for releases
- GitHub releases are tagged with version

### Roo-Code Integration
Roo-Code is integrated as a built-in extension:
1. Source fetched from private repository
2. Built during main build process
3. Copied to `.build/extensions/roo-cline`
4. Packaged with final Void distribution

## Development Notes

- All Void-specific changes are marked with "Void" comments in the code
- When rebasing on newer VS Code/VSCodium versions, search for "Void" and "voideditor" to preserve changes
- Build process skips certain VS Code validation steps that fail with patches
- Windows builds require special handling for code signing and packaging