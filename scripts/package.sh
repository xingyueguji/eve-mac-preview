#!/bin/bash
# Builds a universal (Apple Silicon + Intel) EVESup.app and packages it for a
# release: dist/EVESup-<version>.dmg for new installs and dist/EVESup-<version>.zip
# for the in-app updater. The app itself only lives inside those, so no extra
# copy is left lying around for Spotlight to find.
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/EVESup-Info.plist)"
dmg="dist/EVESup-$version.dmg"
zip="dist/EVESup-$version.zip"

# Every release must be signed with the same certificate: the updater only
# installs updates that match it, and macOS keeps permissions across updates
# because of it. See "Releasing" in the README.
identity="${EVESUP_SIGN_IDENTITY:-EVESup Signing}"
if ! security find-certificate -c "$identity" >/dev/null 2>&1; then
  echo "Signing certificate \"$identity\" isn't in the keychain; see \"Releasing\" in the README." >&2
  exit 1
fi

swift build -c release --arch arm64 --arch x86_64 --product EVESup
bin="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
app="$staging/EVESup.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/EVESup" "$app/Contents/MacOS/EVESup"
cp Resources/EVESup-Info.plist "$app/Contents/Info.plist"
cp Resources/EVESup.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign "$identity" "$app"
codesign --verify --strict "$app"
echo "Built EVESup $version ($(lipo -archs "$app/Contents/MacOS/EVESup")), signed with \"$identity\""

mkdir -p dist
ditto -c -k --keepParent "$app" "$zip"
echo "Built $zip ($(du -h "$zip" | cut -f1))"

ln -s /Applications "$staging/Applications"
cp "Resources/Read Me First.txt" "$staging/"
hdiutil create -volname "EVESup $version" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
echo "Built $dmg ($(du -h "$dmg" | cut -f1))"
