#!/bin/zsh
# Builds PSR Banks.app in the repo root. Usage: Scripts/build_app.sh [--open]
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP="PSR Banks.app"
VERSION="${PSRBANKS_VERSION:-$(Scripts/version.sh)}"
BUILD="$(date +%Y%m%d%H%M)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PSRBanks" "$APP/Contents/MacOS/PSRBanks"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Sources/PSRCore/Resources/voices_e483.json Sources/PSRCore/Resources/default_header.bin "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>PSR Banks</string>
  <key>CFBundleDisplayName</key><string>PSR Banks</string>
  <key>CFBundleIdentifier</key><string>com.srivas.psrbanks</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>PSRBanks</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>__VERSION__</string>
  <key>CFBundleVersion</key><string>__BUILD__</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
sed -i '' "s/__VERSION__/$VERSION/; s/__BUILD__/$BUILD/" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built: $PWD/$APP  (version $VERSION, build $BUILD)"
if [[ "${1:-}" == "--open" ]]; then open "$APP"; fi
