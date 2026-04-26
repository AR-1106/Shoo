#!/bin/bash
# Shoo Installer
# Downloads and installs Shoo, bypassing macOS Gatekeeper quarantine.

set -e

APP_NAME="Shoo"
DMG_URL="https://github.com/AR-1106/Shoo/releases/latest/download/Shoo.dmg"
INSTALL_DIR="/Applications"
TMP_DMG="/tmp/Shoo.dmg"
MOUNT_POINT="/tmp/shoo_mount"

echo "🚀 Installing $APP_NAME..."
echo ""

# Download
echo "⬇️  Downloading from GitHub..."
curl -L -o "$TMP_DMG" "$DMG_URL"

# Mount DMG
echo "📦 Mounting disk image..."
hdiutil attach "$TMP_DMG" -mountpoint "$MOUNT_POINT" -nobrowse -quiet

# Copy app
echo "📂 Installing to $INSTALL_DIR..."
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$MOUNT_POINT/$APP_NAME.app" "$INSTALL_DIR/"

# Unmount
hdiutil detach "$MOUNT_POINT" -quiet

# Remove quarantine flag (this is the key step!)
echo "🔓 Removing quarantine flag..."
xattr -cr "$INSTALL_DIR/$APP_NAME.app"

# Clean up
rm -f "$TMP_DMG"

echo ""
echo "✅ $APP_NAME installed successfully!"
echo "   You can now open it from your Applications folder."
echo ""

# Offer to launch
read -p "Launch $APP_NAME now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open "$INSTALL_DIR/$APP_NAME.app"
fi
