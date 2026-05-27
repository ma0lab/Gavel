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

if [ -f "$ROOT/Resources/whisper-cli" ]; then
    cp "$ROOT/Resources/whisper-cli" "$APP_DIR/Contents/Resources/whisper-cli"
    chmod +x "$APP_DIR/Contents/Resources/whisper-cli"
fi

echo "→ Signing with Developer ID..."
codesign --force --deep --sign "Developer ID Application: Tsubasa Takematsu (B64Q2S6VL5)" "$APP_DIR"

echo "✓ Built: $APP_DIR"
