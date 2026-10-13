#!/bin/bash
# Builds a universal (Apple Silicon + Intel) EVESup.app and wraps it in a DMG
# for sharing: dist/EVESup-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/EVESup-Info.plist)"
app="dist/EVESup.app"
dmg="dist/EVESup-$version.dmg"

swift build -c release --arch arm64 --arch x86_64 --product EVESup
bin="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/EVESup" "$app/Contents/MacOS/EVESup.new"
mv -f "$app/Contents/MacOS/EVESup.new" "$app/Contents/MacOS/EVESup"
cp Resources/EVESup-Info.plist "$app/Contents/Info.plist"
cp Resources/EVESup.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
echo "Built $app ($(lipo -archs "$app/Contents/MacOS/EVESup"))"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
cp "Resources/Read Me First.txt" "$staging/"
hdiutil create -volname "EVESup $version" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
echo "Built $dmg ($(du -h "$dmg" | cut -f1))"
