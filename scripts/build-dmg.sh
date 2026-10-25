#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

if [[ "$#" == 0 ]]; then
    zsh scripts/build-app.sh
elif [[ "$#" != 1 || "$1" != --skip-build ]]; then
    echo "Usage: $0 [--skip-build]" >&2
    exit 1
fi

APP="dist/Walldance.app"
if [[ ! -d "$APP" ]]; then
    echo "Build $APP before using --skip-build" >&2
    exit 1
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "App version must have the form 1.2.3" >&2
    exit 1
fi
codesign --verify --deep --strict --verbose=2 "$APP"

DMG="dist/Walldance-$VERSION.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/walldance-dmg.XXXXXX")"
MOUNT_POINT="$STAGING_DIR/mount"
MOUNTED=0
cleanup() {
    if [[ "$MOUNTED" == 1 ]]; then
        hdiutil detach "$MOUNT_POINT" -force || return
    fi
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT
mkdir -p "$STAGING_DIR/payload/.background"
ditto "$APP" "$STAGING_DIR/payload/Walldance.app"
ln -s /Applications "$STAGING_DIR/payload/Applications"
swift scripts/InstallerBackground.swift "$STAGING_DIR/payload/.background/installer.png"

hdiutil create -volname "Walldance $VERSION" -srcfolder "$STAGING_DIR/payload" \
    -fs HFS+ -format UDRW "$STAGING_DIR/layout.dmg"
hdiutil attach "$STAGING_DIR/layout.dmg" -nobrowse -noverify -mountpoint "$MOUNT_POINT"
MOUNTED=1
osascript scripts/layout-dmg.applescript "$MOUNT_POINT"
if [[ ! -f "$MOUNT_POINT/.DS_Store" ]]; then
    echo "Finder did not save the installer layout" >&2
    exit 1
fi
hdiutil detach "$MOUNT_POINT"
MOUNTED=0
hdiutil convert "$STAGING_DIR/layout.dmg" -format UDZO -o "$STAGING_DIR/Walldance.dmg"
if [[ "${SIGNING_IDENTITY:--}" != - ]]; then
    sign_args=(--sign "$SIGNING_IDENTITY" --timestamp)
    if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then
        sign_args+=(--keychain "$SIGNING_KEYCHAIN")
    fi
    codesign "${sign_args[@]}" "$STAGING_DIR/Walldance.dmg"
    codesign --verify --strict --verbose=2 "$STAGING_DIR/Walldance.dmg"
fi
hdiutil verify "$STAGING_DIR/Walldance.dmg"
mv -f "$STAGING_DIR/Walldance.dmg" "$DMG"
echo "Built $DMG"
