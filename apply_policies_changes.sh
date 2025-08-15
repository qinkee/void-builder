#!/bin/bash
set -e

echo "=== Applying policies changes manually ==="

# This script applies the policies changes without relying on exact line numbers

cd vscode

# 1. Update build/.moduleignore
echo "Updating build/.moduleignore..."
if [ -f "build/.moduleignore" ]; then
    sed -i.bak 's/@vscode\/policy-watcher/@vscodium\/policy-watcher/g' build/.moduleignore
    sed -i.bak 's/vscode-policy-watcher\.node/vscodium-policy-watcher\.node/g' build/.moduleignore
fi

# 2. Update build/lib/policies.js
echo "Updating build/lib/policies.js..."
if [ -f "build/lib/policies.js" ]; then
    sed -i.bak 's/Software\\\\Policies\\\\Microsoft\\\\/Software\\\\Policies\\\\!!ORG_NAME!!\\\\/g' build/lib/policies.js
    sed -i.bak 's/Microsoft\.Policies\./!!ORG_NAME!!\.Policies\./g' build/lib/policies.js
fi

# 3. Update build/lib/policies.ts
echo "Updating build/lib/policies.ts..."
if [ -f "build/lib/policies.ts" ]; then
    sed -i.bak 's/Software\\\\Policies\\\\Microsoft\\\\/Software\\\\Policies\\\\!!ORG_NAME!!\\\\/g' build/lib/policies.ts
    sed -i.bak 's/Microsoft\.Policies\./!!ORG_NAME!!\.Policies\./g' build/lib/policies.ts
fi

# 4. Update eslint.config.js
echo "Updating eslint.config.js..."
if [ -f "eslint.config.js" ]; then
    sed -i.bak "s/'@vscode\/policy-watcher',/'@vscodium\/policy-watcher',/g" eslint.config.js
fi

# 5. Update package.json
echo "Updating package.json..."
if [ -f "package.json" ]; then
    sed -i.bak 's/"@vscode\/policy-watcher": "[^"]*"/"@vscodium\/policy-watcher": "^1.3.2-252465"/g' package.json
fi

# 6. Update package-lock.json
echo "Updating package-lock.json..."
if [ -f "package-lock.json" ]; then
    # First remove the old @vscode/policy-watcher entry
    # This is tricky because it spans multiple lines, so we'll use a different approach
    
    # Create a temporary file without the @vscode/policy-watcher section
    awk '
    /"node_modules\/@vscode\/policy-watcher"/ { skip = 1 }
    skip && /^    },?$/ { skip = 0; next }
    !skip { print }
    ' package-lock.json > package-lock.json.tmp
    
    # Now add the @vscodium/policy-watcher entry
    # Find where to insert it (after @vscode/proxy-agent or similar)
    awk '
    /"node_modules\/@vscode\/proxy-agent"/ { found = 1 }
    found && /^    },?$/ {
        print $0
        print "    \"node_modules/@vscodium/policy-watcher\": {"
        print "      \"version\": \"1.3.2-252465\","
        print "      \"resolved\": \"https://registry.npmjs.org/@vscodium/policy-watcher/-/policy-watcher-1.3.2-252465.tgz\","
        print "      \"integrity\": \"sha512-kpnb656HMteBIm8d9LhBpQ5gL2A/4rJrsaLCF0D8IWyrZAQ0UR9EzXM6tZ6p5H+KWot3QUjm0Gry6vMV1yye5Q==\","
        print "      \"hasInstallScript\": true,"
        print "      \"license\": \"MIT\","
        print "      \"dependencies\": {"
        print "        \"bindings\": \"^1.5.0\","
        print "        \"node-addon-api\": \"^8.2.0\""
        print "      }"
        print "    },"
        print "    \"node_modules/@vscodium/policy-watcher/node_modules/node-addon-api\": {"
        print "      \"version\": \"8.4.0\","
        print "      \"resolved\": \"https://registry.npmjs.org/node-addon-api/-/node-addon-api-8.4.0.tgz\","
        print "      \"integrity\": \"sha512-D9DI/gXHvVmjHS08SVch0Em8G5S1P+QWtU31appcKT/8wFSPRcdHadIFSAntdMMVM5zz+/DL+bL/gz3UDppqtg==\","
        print "      \"license\": \"MIT\","
        print "      \"engines\": {"
        print "        \"node\": \"^18 || ^20 || >= 21\""
        print "      }"
        print "    },"
        found = 0
        next
    }
    { print }
    ' package-lock.json.tmp > package-lock.json.tmp2
    
    # Also update the dependencies section
    sed -i.bak 's/"@vscode\/policy-watcher": "[^"]*"/"@vscodium\/policy-watcher": "^1.3.2-252465"/g' package-lock.json.tmp2
    
    mv package-lock.json.tmp2 package-lock.json
    rm -f package-lock.json.tmp
fi

# 7. Update test files
echo "Updating test files..."
find src -name "*.ts" -o -name "*.js" | xargs grep -l "@vscode/policy-watcher" 2>/dev/null | while read file; do
    echo "  Updating $file"
    sed -i.bak 's/@vscode\/policy-watcher/@vscodium\/policy-watcher/g' "$file"
done

# 8. Update the createWatcher call
echo "Updating createWatcher calls..."
if [ -f "src/vs/platform/policy/node/nativePolicyService.ts" ]; then
    sed -i.bak "s/createWatcher(this\.productName, policyDefinitions/createWatcher('!!ORG_NAME!!', this.productName, policyDefinitions/g" src/vs/platform/policy/node/nativePolicyService.ts
fi

# Clean up backup files
find . -name "*.bak" -delete

echo "=== Done applying policies changes ==="