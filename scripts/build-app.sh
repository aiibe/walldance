#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

APP_VERSION="${APP_VERSION:-0.1.0}"
APP_BUILD_NUMBER="${APP_BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
if [[ ! "$APP_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "APP_VERSION must have the form 1.2.3" >&2
    exit 1
fi
if [[ ! "$APP_BUILD_NUMBER" =~ '^[1-9][0-9]*$' ]]; then
    echo "APP_BUILD_NUMBER must be a positive integer" >&2
    exit 1
fi

build_args=(-c release)
if [[ "${UNIVERSAL_BUILD:-0}" == 1 ]]; then
    build_args+=(--arch arm64 --arch x86_64)
fi
swift build "${build_args[@]}"
BIN_PATH="$(swift build "${build_args[@]}" --show-bin-path)"
APP="dist/Walldance.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/Walldance" "$APP/Contents/MacOS/Walldance"
cp Sources/Walldance/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleName</key><string>Walldance</string>
    <key>CFBundleDisplayName</key><string>Walldance</string>
    <key>CFBundleIdentifier</key><string>com.walldance.app</string>
    <key>CFBundleExecutable</key><string>Walldance</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD_NUMBER" "$APP/Contents/Info.plist"

sign_args=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != - ]]; then
    sign_args+=(--options runtime --timestamp)
fi
if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then
    sign_args+=(--keychain "$SIGNING_KEYCHAIN")
fi
codesign "${sign_args[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built $APP"
