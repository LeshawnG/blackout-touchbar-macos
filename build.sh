#!/bin/zsh
# Builds build/Blackout.app with the command-line Swift compiler (no Xcode project needed).
#
#   ./build.sh           build the app
#   ./build.sh release   build, then zip it as dist/Blackout-<version>.zip for a GitHub release
#   ./build.sh icon      regenerate Resources/AppIcon.icns from tools/make_icon.swift
set -euo pipefail
cd "${0:A:h}"

if [[ "${1:-}" == "icon" ]]; then
  swift tools/make_icon.swift Resources docs
  exit 0
fi

APP="build/Blackout.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O \
  -target arm64-apple-macos11.0 \
  -import-objc-header Sources/Bridge.h \
  Sources/*.swift \
  -framework AppKit -framework Carbon -framework CoreAudio -framework AudioToolbox \
  -o "$APP/Contents/MacOS/Blackout"

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"   # ad-hoc signature, required on Apple Silicon

echo "Built: $PWD/$APP ($VERSION)"

if [[ "${1:-}" == "release" ]]; then
  mkdir -p dist
  ZIP="dist/Blackout-$VERSION.zip"
  rm -f "$ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  echo "Release zip: $PWD/$ZIP"
  shasum -a 256 "$ZIP"
fi
