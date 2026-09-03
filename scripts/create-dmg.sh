#!/bin/bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: create-dmg.sh <StillMotion.app> <output.dmg>" >&2
    exit 1
fi

APP=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
OUTPUT=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VOLUME_NAME="StillMotion"
BUILD_VOLUME_NAME="StillMotion Build $$"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/stillmotion-dmg.XXXXXX")
STAGING="$WORK_DIR/staging"
MOUNT_POINT="$WORK_DIR/mount"
RW_DMG="$WORK_DIR/StillMotion-rw.dmg"
MOUNTED=false

cleanup() {
    if [[ "$MOUNTED" == true ]]; then
        hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGING/.background" "$MOUNT_POINT"
ditto "$APP" "$STAGING/StillMotion.app"
ditto "$ROOT/LICENSE" "$STAGING/LICENSE"
ln -s /Applications "$STAGING/Applications"
xcrun swift "$ROOT/scripts/create-dmg-background.swift" "$STAGING/.background/background.png"
chflags hidden "$STAGING/.background"

hdiutil create \
    -volname "$BUILD_VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "$RW_DMG" >/dev/null

hdiutil attach "$RW_DMG" \
    -mountpoint "$MOUNT_POINT" \
    -nobrowse \
    -noverify \
    -noautoopen >/dev/null
MOUNTED=true

osascript <<APPLESCRIPT
set dmgFolder to POSIX file "$MOUNT_POINT" as alias
set backgroundFile to POSIX file "$MOUNT_POINT/.background/background.png" as alias
tell application "Finder"
    open dmgFolder
    delay 1
    set dmgWindow to front window
    set current view of dmgWindow to icon view
    set toolbar visible of dmgWindow to false
    set statusbar visible of dmgWindow to false
    set pathbar visible of dmgWindow to false
    set bounds of dmgWindow to {100, 100, 820, 600}

    set viewOptions to icon view options of dmgWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 104
    set text size of viewOptions to 13
    set background picture of viewOptions to backgroundFile

    set position of item "StillMotion.app" of dmgFolder to {190, 205}
    set position of item "Applications" of dmgFolder to {530, 205}
    set position of item "LICENSE" of dmgFolder to {360, 350}

    update dmgFolder without registering applications
    delay 2
    close dmgWindow
end tell
APPLESCRIPT

sync
diskutil rename "$MOUNT_POINT" "$VOLUME_NAME" >/dev/null
hdiutil detach "$MOUNT_POINT" >/dev/null
MOUNTED=false

rm -f "$OUTPUT"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT" >/dev/null
hdiutil verify "$OUTPUT" >/dev/null
