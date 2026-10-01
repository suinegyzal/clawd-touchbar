#!/bin/bash
# Clawd Touch Bar 빌드: build/ClawdTouchBar.app 을 만든다.
set -euo pipefail
cd "$(dirname "$0")"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Swift 컴파일러가 없습니다. 먼저 'xcode-select --install' 로 Command Line Tools를 설치하세요." >&2
  exit 1
fi

APP="build/ClawdTouchBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun swiftc -O -parse-as-library \
  -target "$(uname -m)-apple-macos12.0" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/ClawdTouchBar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Clawd Touch Bar</string>
  <key>CFBundleDisplayName</key><string>Clawd Touch Bar</string>
  <key>CFBundleIdentifier</key><string>com.local.ClawdTouchBar</string>
  <key>CFBundleExecutable</key><string>ClawdTouchBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "빌드 완료: $APP"
