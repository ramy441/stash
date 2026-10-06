#!/bin/bash
# Builds Stash.app. Pass --install to replace the copy in /Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/Stash.app"

cd "$ROOT"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Stash" "$APP/Contents/MacOS/Stash"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# A stable identity keeps the same designated requirement across rebuilds, so the
# launch-at-login registration survives. Ad-hoc signing gets a fresh hash every build.
IDENTITY="Murmur Local Signing"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    codesign --force --options runtime --sign "$IDENTITY" --identifier com.ramy441.stash "$APP"
else
    codesign --force --options runtime --sign - --identifier com.ramy441.stash "$APP"
    echo "warning: signed ad-hoc — Open at Login must be re-enabled after every build"
fi
echo "built  $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Stash 2>/dev/null || true
    sleep 1
    rm -rf /Applications/Stash.app
    cp -R "$APP" /Applications/Stash.app
    echo "installed  /Applications/Stash.app"
fi
