#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-debug}"
BUILD_DIR="$ROOT_DIR/.build/$CONFIGURATION"
APP_DIR="$ROOT_DIR/dist/TempSweep.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_FILE="$ROOT_DIR/Sources/TempSweepApp/Resources/AppIcon.icns"

cd "$ROOT_DIR"
if [[ ! -f "$ICON_FILE" ]]; then
  swift scripts/generate_app_icon.swift
fi
swift build -c "$CONFIGURATION" --product TempSweepApp

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/TempSweepApp" "$MACOS_DIR/TempSweep"
cp "$ICON_FILE" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TempSweep</string>
    <key>CFBundleIdentifier</key>
    <string>local.tempsweep.app</string>
    <key>CFBundleName</key>
    <string>TempSweep</string>
    <key>CFBundleDisplayName</key>
    <string>TempSweep</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSHumanReadableCopyright</key>
    <string>Creator: buhussy - Contact: x.com/buhusa</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

chmod +x "$MACOS_DIR/TempSweep"
echo "Created $APP_DIR"
