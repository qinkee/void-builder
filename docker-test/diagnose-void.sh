#!/bin/bash

echo "=== Void Configuration Diagnostic ==="
echo ""

# Check Void installation
echo "1. Checking Void installation..."
if dpkg -l | grep -q void; then
    echo "✓ Void package is installed"
    dpkg -l | grep void
else
    echo "✗ Void package not found"
fi
echo ""

# Find Void binary
echo "2. Locating Void binary..."
VOID_PATHS=(
    "/usr/share/void/void"
    "/opt/void/void"
    "/usr/bin/void"
    "/usr/local/bin/void"
)

VOID_BIN=""
for path in "${VOID_PATHS[@]}"; do
    if [ -f "$path" ]; then
        echo "✓ Found Void at: $path"
        VOID_BIN="$path"
        break
    fi
done

if [ -z "$VOID_BIN" ]; then
    echo "✗ Void binary not found"
    echo "Searching for void files..."
    find /usr -name "*void*" -type f 2>/dev/null | head -10
fi
echo ""

# Check Void config directory
echo "3. Checking Void configuration directory..."
CONFIG_DIR="/home/void/.config/Void"
if [ -d "$CONFIG_DIR" ]; then
    echo "✓ Config directory exists: $CONFIG_DIR"
    echo "Contents:"
    ls -la "$CONFIG_DIR" | head -10
    
    # Check for settings file
    if [ -f "$CONFIG_DIR/User/settings.json" ]; then
        echo "✓ Settings file exists"
        echo "Settings preview:"
        head -20 "$CONFIG_DIR/User/settings.json" 2>/dev/null || echo "Cannot read settings"
    else
        echo "✗ Settings file not found"
    fi
else
    echo "✗ Config directory not found"
    echo "Creating config directory..."
    mkdir -p "$CONFIG_DIR"
    chown -R void:void "$CONFIG_DIR"
fi
echo ""

# Check permissions
echo "4. Checking permissions..."
echo "Home directory:"
ls -ld /home/void
echo "Config directory:"
ls -ld /home/void/.config
echo ""

# Check network
echo "5. Testing network connectivity..."
echo -n "Google: "
curl -s -o /dev/null -w '%{http_code}\n' https://google.com 2>/dev/null || echo "Failed"
echo -n "Anthropic API: "
curl -s -o /dev/null -w '%{http_code}\n' https://api.anthropic.com 2>/dev/null || echo "Failed"
echo -n "OpenAI API: "
curl -s -o /dev/null -w '%{http_code}\n' https://api.openai.com 2>/dev/null || echo "Failed"
echo ""

# Check display
echo "6. Checking display..."
echo "DISPLAY=$DISPLAY"
if [ -n "$DISPLAY" ]; then
    echo "✓ DISPLAY is set"
else
    echo "✗ DISPLAY not set"
fi
echo ""

# Check for Roo-Code extension
echo "7. Checking for Roo-Code extension..."
if [ -n "$VOID_BIN" ]; then
    VOID_DIR=$(dirname "$VOID_BIN")
    EXTENSIONS_DIR="$VOID_DIR/resources/app/extensions"
    
    if [ -d "$EXTENSIONS_DIR" ]; then
        echo "Extensions directory: $EXTENSIONS_DIR"
        if ls "$EXTENSIONS_DIR" | grep -i roo > /dev/null 2>&1; then
            echo "✓ Roo-Code extension found:"
            ls -la "$EXTENSIONS_DIR" | grep -i roo
        else
            echo "✗ Roo-Code extension NOT found"
            echo "Available extensions:"
            ls "$EXTENSIONS_DIR" | head -10
        fi
    else
        echo "✗ Extensions directory not found"
    fi
fi
echo ""

echo "=== Diagnostic Complete ==="