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
trap 'rm -rf "$STAGING_DIR"' EXIT
mkdir "$STAGING_DIR/payload"
ditto "$APP" "$STAGING_DIR/payload/Walldance.app"
ln -s /Applications "$STAGING_DIR/payload/Applications"
cp CHANGELOG.md "$STAGING_DIR/payload/CHANGELOG.md"
cat > "$STAGING_DIR/payload/Install.txt" <<'TEXT'
Drag Walldance.app to Applications, then eject this disk image.
Open Walldance from Applications. Requires macOS 14 or later.
TEXT

hdiutil create -volname "Walldance $VERSION" -srcfolder "$STAGING_DIR/payload" \
    -format UDZO -ov "$STAGING_DIR/Walldance.dmg"
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
