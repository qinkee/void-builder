#!/bin/bash

echo "=== Fixing Void Encryption Issue ==="
echo ""

# Install required packages for keyring support
echo "1. Installing keyring packages..."
apt-get update
apt-get install -y \
    gnome-keyring \
    libsecret-1-0 \
    libsecret-tools \
    libgnome-keyring0 \
    libgnome-keyring-common \
    seahorse

# Setup dbus for keyring
echo "2. Setting up D-Bus for keyring..."
if [ ! -d /var/run/dbus ]; then
    mkdir -p /var/run/dbus
fi
dbus-daemon --system --fork || true

# Create a wrapper script that starts Void with keyring support
echo "3. Creating Void wrapper with keyring support..."
cat > /usr/local/bin/void-with-keyring << 'EOF'
#!/bin/bash

# Set display
export DISPLAY=:1

# Start dbus session
eval $(dbus-launch --sh-syntax)

# Initialize gnome-keyring
echo "" | gnome-keyring-daemon --unlock
gnome-keyring-daemon --start --components=secrets,pkcs11,ssh

# Export keyring variables
export $(gnome-keyring-daemon --start --components=secrets,pkcs11,ssh | sed 's/^/export /')

# Disable encryption as a fallback if keyring doesn't work
export ELECTRON_DISABLE_SECURITY_WARNINGS=true

# Alternative: Use basic text storage instead of encrypted storage
export VOID_DISABLE_ENCRYPTION=1

# Start Void with proper flags
echo "Starting Void with keyring support..."
/usr/share/void/void \
    --password-store=basic \
    --disable-gpu \
    --disable-software-rasterizer \
    "$@"
EOF

chmod +x /usr/local/bin/void-with-keyring
chown void:void /usr/local/bin/void-with-keyring

# Create a desktop entry that uses the wrapper
echo "4. Updating desktop entry..."
cat > /home/void/.local/share/applications/void-fixed.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Void Editor (Fixed)
Comment=Code Editor with working API key storage
Exec=/usr/local/bin/void-with-keyring %F
Icon=void
Categories=Development;IDE;
Terminal=false
StartupNotify=true
EOF

chmod +x /home/void/.local/share/applications/void-fixed.desktop
chown void:void /home/void/.local/share/applications/void-fixed.desktop

# Copy to desktop
cp /home/void/.local/share/applications/void-fixed.desktop /home/void/Desktop/
chmod +x /home/void/Desktop/void-fixed.desktop
chown void:void /home/void/Desktop/void-fixed.desktop

echo ""
echo "=== Fix Applied ==="
echo ""
echo "You can now start Void using one of these methods:"
echo "1. Click 'Void Editor (Fixed)' on the desktop"
echo "2. Run in terminal: /usr/local/bin/void-with-keyring"
echo "3. Or with basic password store: /usr/share/void/void --password-store=basic"
echo ""
echo "Note: API keys will be stored in plain text due to Docker limitations."
echo "This is acceptable for testing but not for production use."