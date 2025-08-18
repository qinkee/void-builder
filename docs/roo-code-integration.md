# Roo-Code Integration in Void Builder

This document explains how Roo-Code is integrated as a built-in extension in Void builds.

## Overview

Roo-Code is included as a built-in extension through a three-step process:
1. `get_roo_code.sh` - Fetches Roo-Code from private repository
2. `build_roo_code.sh` - Builds the extension (compiles TypeScript to JavaScript) and copies to `.build/extensions/roo-code`
3. Standard void build process packages the compiled extension

This ensures Roo-Code gets packaged with all other built-in extensions during the build process.

## Prerequisites

- **pnpm**: Required for building Roo-Code (install with `npm install -g pnpm`)

## Private Repository Configuration

Roo-Code is fetched from a private repository. You need to configure the following:

### GitHub Secrets (Required)

In your GitHub repository settings, add these secrets:

1. **`ROO_CODE_TOKEN`**: Personal Access Token or GitHub Token with read access to the private Roo-Code repository
2. **`ROO_CODE_REPO`**: The private repository URL (e.g., `https://github.com/YourOrg/roo-code-private`)

### GitHub Variables (Optional)

1. **`ROO_CODE_VERSION`**: The version/tag to use (default: `v3.25.11`)

### Local Development Configuration

For local development with private repository:

```bash
# Set authentication token
export ROO_CODE_TOKEN="your-github-personal-access-token"

# Set private repository URL
export ROO_CODE_REPO="https://github.com/YourOrg/roo-code-private"

# Run the fetch script
./get_roo_code.sh
```

## Local Development

To include Roo-Code in your local build:

1. Set the environment variable:
   ```bash
   export INCLUDE_ROO_CODE=yes
   ```

2. Fetch Roo-Code from private repository:
   ```bash
   # This will clone to ./roo-code directory
   ./get_roo_code.sh
   ```

3. Run the build as usual:
   ```bash
   ./build.sh
   ```

## CI/CD Integration

The GitHub Actions workflows automatically include Roo-Code by:

1. Setting `INCLUDE_ROO_CODE=yes` in the workflow environment
2. Running `get_roo_code.sh` to fetch the Roo-Code repository
3. Running `build_roo_code.sh` during the build process to copy files to the extensions directory

## Configuration

### Environment Variables

- `INCLUDE_ROO_CODE`: Set to `yes` to include Roo-Code in the build
- `ROO_CODE_PATH`: Path to Roo-Code source (default: `./roo-code` after running `get_roo_code.sh`)
- `ROO_CODE_VERSION`: Git tag/branch to use (for CI builds, default: `v3.25.11`)
- `ROO_CODE_REPO`: Repository URL (for CI builds, default: `https://github.com/RooVeterinaryInc/roo-code`)

### Files Modified

- `build.sh`: Added Roo-Code build step before extension compilation
- `.github/workflows/stable-*.yml`: Added environment variable and Roo-Code fetch step
- `build_roo_code.sh`: Script to copy and prepare Roo-Code files
- `get_roo_code.sh`: Script to fetch Roo-Code for CI builds

## Disabling Roo-Code

To build without Roo-Code, simply don't set `INCLUDE_ROO_CODE` or set it to `no`:

```bash
INCLUDE_ROO_CODE=no ./build.sh
```

## Troubleshooting

1. **Build fails with "Roo-Code source not found"**
   - Ensure `ROO_CODE_PATH` points to the correct directory
   - For CI, check that `get_roo_code.sh` ran successfully

2. **Extension not appearing in final build**
   - Check that files were copied to `vscode/.build/extensions/roo-code`
   - Verify package.json exists in the target directory

3. **Workspace protocol errors**
   - The build script automatically removes workspace protocol dependencies
   - Ensure `jq` is installed for proper package.json cleanup