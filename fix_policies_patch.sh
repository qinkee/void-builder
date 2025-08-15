#!/bin/bash
set -e

echo "=== Fixing policies.patch ==="

# Check if vscode directory exists
if [ ! -d "vscode" ]; then
    echo "Error: vscode directory not found. This script should be run after cloning VSCode."
    echo "You can test it by running:"
    echo "  ./get_repo.sh"
    echo "  ./fix_policies_patch.sh"
    exit 1
fi

cd vscode

# Find the actual location of @vscode/policy-watcher in package-lock.json
echo "Searching for @vscode/policy-watcher in package-lock.json..."
POLICY_LINE=$(grep -n '"@vscode/policy-watcher"' package-lock.json | head -1 | cut -d: -f1)

if [ -z "$POLICY_LINE" ]; then
    echo "Warning: @vscode/policy-watcher not found in package-lock.json"
    echo "The package might have already been replaced or removed."
else
    echo "Found @vscode/policy-watcher at line $POLICY_LINE"
    
    # Show context around the found line
    echo "Context:"
    sed -n "$((POLICY_LINE-5)),$((POLICY_LINE+25))p" package-lock.json | nl -v $((POLICY_LINE-5))
fi

# Create a temporary patch file to test
cd ..
cp patches/policies.patch patches/policies.patch.backup

# Update the patch file with the correct line number if needed
if [ ! -z "$POLICY_LINE" ] && [ "$POLICY_LINE" != "4700" ]; then
    echo "Updating patch file to use correct line number: $POLICY_LINE"
    sed -i.bak "s/@@ -4700,21 +4700,1 @@/@@ -$POLICY_LINE,21 +$POLICY_LINE,1 @@/" patches/policies.patch
fi

echo ""
echo "=== Testing patch application ==="
cd vscode

# Try to apply the patch
if git apply --check ../patches/policies.patch 2>&1; then
    echo "✓ Patch can be applied successfully!"
else
    echo "✗ Patch still fails. Investigating further..."
    
    # Try to apply with more verbose output
    echo ""
    echo "Detailed error:"
    git apply --verbose --check ../patches/policies.patch 2>&1 || true
    
    echo ""
    echo "=== Attempting to regenerate the patch ==="
    
    # Reset any changes
    git checkout -- .
    
    # Manually apply the changes the patch is trying to make
    echo "Applying changes manually..."
    
    # 1. Update build/.moduleignore
    if [ -f "build/.moduleignore" ]; then
        sed -i.bak 's/@vscode\/policy-watcher/@vscodium\/policy-watcher/g' build/.moduleignore
        sed -i.bak 's/vscode-policy-watcher\.node/vscodium-policy-watcher\.node/g' build/.moduleignore
    fi
    
    # 2. Update build/lib/policies.js
    if [ -f "build/lib/policies.js" ]; then
        sed -i.bak 's/Software\\\\Policies\\\\Microsoft\\\\/Software\\\\Policies\\\\!!ORG_NAME!!\\\\/g' build/lib/policies.js
        sed -i.bak 's/Microsoft\.Policies\./!!ORG_NAME!!\.Policies\./g' build/lib/policies.js
    fi
    
    # 3. Update build/lib/policies.ts
    if [ -f "build/lib/policies.ts" ]; then
        sed -i.bak 's/Software\\\\Policies\\\\Microsoft\\\\/Software\\\\Policies\\\\!!ORG_NAME!!\\\\/g' build/lib/policies.ts
        sed -i.bak 's/Microsoft\.Policies\./!!ORG_NAME!!\.Policies\./g' build/lib/policies.ts
    fi
    
    # 4. Update eslint.config.js
    if [ -f "eslint.config.js" ]; then
        sed -i.bak "s/'@vscode\/policy-watcher',/'@vscodium\/policy-watcher',/g" eslint.config.js
    fi
    
    # 5. Update package.json
    if [ -f "package.json" ]; then
        sed -i.bak 's/"@vscode\/policy-watcher": "\^[^"]*"/"@vscodium\/policy-watcher": "^1.3.2-252465"/g' package.json
    fi
    
    # 6. Update package-lock.json
    if [ -f "package-lock.json" ]; then
        # This is more complex, we need to remove the old entry and add the new one
        echo "Updating package-lock.json..."
        
        # First, let's just replace references
        sed -i.bak 's/"@vscode\/policy-watcher"/"@vscodium\/policy-watcher"/g' package-lock.json
        sed -i.bak 's|https://registry.npmmirror.com/@vscode/policy-watcher/-/policy-watcher-[^"]*|https://registry.npmjs.org/@vscodium/policy-watcher/-/policy-watcher-1.3.2-252465.tgz|g' package-lock.json
        sed -i.bak 's/"version": "1\.3\.2"/"version": "1.3.2-252465"/g' package-lock.json
    fi
    
    # 7. Update test files
    find . -name "*.ts" -o -name "*.js" | xargs grep -l "@vscode/policy-watcher" | while read file; do
        echo "Updating $file"
        sed -i.bak 's/@vscode\/policy-watcher/@vscodium\/policy-watcher/g' "$file"
    done
    
    # 8. Update the createWatcher call
    if [ -f "src/vs/platform/policy/node/nativePolicyService.ts" ]; then
        sed -i.bak "s/createWatcher(this\.productName, policyDefinitions/createWatcher('!!ORG_NAME!!', this.productName, policyDefinitions/g" src/vs/platform/policy/node/nativePolicyService.ts
    fi
    
    # Generate a new patch
    echo ""
    echo "=== Generating new patch ==="
    git add -A
    git diff --cached > ../patches/policies.patch.new
    
    # Clean up
    find . -name "*.bak" -delete
    git reset --hard
    
    echo ""
    echo "New patch generated at: patches/policies.patch.new"
    echo "You can compare it with the original:"
    echo "  diff patches/policies.patch patches/policies.patch.new"
fi

cd ..
echo ""
echo "=== Done ==="