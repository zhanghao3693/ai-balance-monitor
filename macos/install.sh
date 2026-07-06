#!/bin/bash
set -e

echo "============================================"
echo "  AI Balance Monitor - macOS Installer"
echo "============================================"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR/AI-Balance-Monitor.app"
ICONS_SRC="$SCRIPT_DIR/../icons"

# Copy app to /Applications if desired
read -p "Install to /Applications? [Y/n] " choice
choice=${choice:-Y}

if [[ "$choice" =~ ^[Yy]$ ]]; then
    if [ -d "/Applications/AI-Balance-Monitor.app" ]; then
        echo "Removing old installation..."
        rm -rf "/Applications/AI-Balance-Monitor.app"
    fi
    cp -R "$APP_DIR" "/Applications/"
    echo "✅ Installed to /Applications/AI-Balance-Monitor.app"
    echo ""
    echo "To start the monitor:"
    echo "  open /Applications/AI-Balance-Monitor.app"
    echo ""
    echo "Or double-click AI-Balance-Monitor.app in Finder → Applications."
else
    echo "App bundle is at: $APP_DIR"
    echo ""
    echo "To start the monitor:"
    echo "  double-click AI-Balance-Monitor.app"
fi

# Copy platform icons to config directory
CONFIG_DIR="$HOME/.deepseek_monitor"
mkdir -p "$CONFIG_DIR"
if [ -d "$ICONS_SRC" ]; then
    cp "$ICONS_SRC"/*_icon.png "$CONFIG_DIR/" 2>/dev/null || true
    echo "✅ Platform icons copied to $CONFIG_DIR"
fi

echo ""
echo "First run: click the menu bar icon → ⚙️ Manage API Keys to add your keys."
