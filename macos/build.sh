#!/bin/bash
# Build script for AI Balance Monitor (macOS)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR/AI-Balance-Monitor.app"
SRC_DIR="$SCRIPT_DIR"

echo "Building AI Balance Monitor..."

# Compile Swift source to the app bundle
swiftc -O -o "$APP_DIR/Contents/MacOS/AI-Balance-Monitor" \
    "$SRC_DIR/deepseek_monitor.swift"

echo "✅ Build successful!"
echo ""
echo "Output: $APP_DIR/Contents/MacOS/AI-Balance-Monitor"
echo ""
echo "To run:"
echo "  $APP_DIR/Contents/MacOS/AI-Balance-Monitor"
echo ""
echo "Or double-click AI-Balance-Monitor.app in Finder"
