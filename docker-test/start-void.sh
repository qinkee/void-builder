#!/bin/bash

# Script to start Void with proper permissions in Docker

# Set environment variables
export DISPLAY=:1
export HOME=/home/void
export USER=void

# Ensure config directory exists with correct permissions
mkdir -p /home/void/.config/Void
chown -R void:void /home/void/.config

# Create a wrapper script to start Void with debugging
cat > /tmp/void-wrapper.sh << 'EOF'
#!/bin/bash

# Enable verbose logging
export ELECTRON_ENABLE_LOGGING=1
export ELECTRON_LOG_FILE=/tmp/void.log

# Disable GPU acceleration if causing issues
export ELECTRON_DISABLE_GPU=1

# Set XDG directories
export XDG_CONFIG_HOME=/home/void/.config
export XDG_DATA_HOME=/home/void/.local/share
export XDG_CACHE_HOME=/home/void/.cache

# Ensure directories exist
mkdir -p "$XDG_CONFIG_HOME/Void"
mkdir -p "$XDG_DATA_HOME"
mkdir -p "$XDG_CACHE_HOME"

echo "Starting Void with debugging enabled..."
echo "Log file: /tmp/void.log"

# Try different launch options
if [ -f /usr/share/void/void ]; then
    echo "Trying: /usr/share/void/void --verbose"
    /usr/share/void/void --verbose --no-sandbox --disable-gpu-sandbox "$@" 2>&1 | tee /tmp/void-startup.log
elif [ -f /opt/void/void ]; then
    echo "Trying: /opt/void/void --verbose"
    /opt/void/void --verbose --no-sandbox --disable-gpu-sandbox "$@" 2>&1 | tee /tmp/void-startup.log
elif [ -f /usr/bin/void ]; then
    echo "Trying: /usr/bin/void --verbose"
    /usr/bin/void --verbose --no-sandbox --disable-gpu-sandbox "$@" 2>&1 | tee /tmp/void-startup.log
else
    echo "Error: Void binary not found!"
    echo "Searching for void..."
    find /usr -name "void" -type f 2>/dev/null
    find /opt -name "void" -type f 2>/dev/null
fi
EOF

chmod +x /tmp/void-wrapper.sh
chown void:void /tmp/void-wrapper.sh

# Run as void user
echo "Starting Void as user 'void'..."
su - void -c "DISPLAY=:1 /tmp/void-wrapper.sh"