#!/bin/bash
# Builds build/EVESup.app (and build/MockEVEClient.app with --mock).
set -euo pipefail
cd "$(dirname "$0")/.."

with_mock=false
for arg in "$@"; do
  if [[ "$arg" == "--mock" ]]; then with_mock=true; fi
done

swift build -c release --product EVESup
if $with_mock; then swift build -c release --product MockEVEClient; fi
bin="$(swift build -c release --show-bin-path)"

# Sign with the release certificate when it's in the keychain, so macOS keeps
# this build's permissions across rebuilds; otherwise fall back to ad-hoc.
identity="${EVESUP_SIGN_IDENTITY:-EVESup Signing}"
if security find-certificate -c "$identity" >/dev/null 2>&1; then sign="$identity"; else sign="-"; fi

make_app() {
  local name="$1"
  local app="build/$name.app"
  # The bundle layout never changes, so files are replaced in place. The
  # binary goes through a rename so a copy that's already running isn't hurt.
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp "$bin/$name" "$app/Contents/MacOS/$name.new"
  mv -f "$app/Contents/MacOS/$name.new" "$app/Contents/MacOS/$name"
  cp "Resources/$name-Info.plist" "$app/Contents/Info.plist"
  if [[ -f "Resources/$name.icns" ]]; then cp "Resources/$name.icns" "$app/Contents/Resources/AppIcon.icns"; fi
  codesign --force --sign "$sign" "$app"
  echo "Built $app"
}

make_app EVESup
if $with_mock; then make_app MockEVEClient; fi
