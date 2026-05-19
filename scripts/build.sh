#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/dist/ClaudeBar.app"

echo "→ Building ClaudeBar..."
cd "$ROOT"
swift build -c release --arch arm64

echo "→ Assembling app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/ClaudeBar" "$APP_DIR/Contents/MacOS/ClaudeBar"
cp "$BUILD_DIR/claudebar-hook" "$APP_DIR/Contents/Resources/claudebar-hook"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

chmod +x "$APP_DIR/Contents/MacOS/ClaudeBar"
chmod +x "$APP_DIR/Contents/Resources/claudebar-hook"

echo "→ Signing with ad-hoc signature..."
codesign --force --deep --sign - "$APP_DIR"

echo "✓ Built: $APP_DIR"
