#!/bin/bash
# Builds Lull.app (Apple Silicon) into .build/app.
#   --install  copies it to /Applications and opens it
#   --dmg      also makes dist/Lull-<version>.dmg for a GitHub release
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
VERSION="1.0.0"
APP="$ROOT/.build/app/Lull.app"

echo "==> Building (release, Apple Silicon)"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Lull"

echo "==> Icon"
if [ ! -f Resources/AppIcon.icns ]; then
  ICONSET="$ROOT/.build/AppIcon.iconset"
  swift scripts/make-icon.swift "$ICONSET"
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi

echo "==> Assembling app bundle"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Lull"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Lull</string>
  <key>CFBundleDisplayName</key><string>Lull</string>
  <key>CFBundleIdentifier</key><string>com.okba.lull</string>
  <key>CFBundleExecutable</key><string>Lull</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Okba Bouziane</string>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - --options runtime --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
echo "==> Built $APP ($(du -sh "$APP" | cut -f1))"

if [ "${1:-}" = "--dmg" ]; then
  echo "==> Making DMG"
  mkdir -p "$ROOT/dist"
  STAGE=$(mktemp -d)
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  DMG="$ROOT/dist/Lull-$VERSION.dmg"
  rm -f "$DMG"
  hdiutil create -volname "Lull" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
  rm -rf "$STAGE"
  echo "==> $DMG ($(du -h "$DMG" | cut -f1))"
fi

if [ "${1:-}" = "--install" ]; then
  echo "==> Installing to /Applications"
  pkill -x Lull 2>/dev/null && sleep 1 || true
  rm -rf /Applications/Lull.app
  cp -R "$APP" /Applications/Lull.app
  open -g /Applications/Lull.app
  echo "==> Lull is running (look for the gauge in the menu bar)"
fi
