#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
APP="$ROOT/dist/ClaudeBar.app"
DMG="$ROOT/dist/ClaudeBar.dmg"

if [ ! -d "$APP" ]; then
    echo "Run scripts/build.sh first"
    exit 1
fi

echo "→ Creating DMG..."
rm -f "$DMG"

hdiutil create \
    -volname "ClaudeBar" \
    -srcfolder "$APP" \
    -ov \
    -format UDZO \
    "$DMG"

echo "✓ DMG: $DMG"
