#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

APP_VERSION="${APP_VERSION:-0.1.1}"
APP_BUILD_NUMBER="${APP_BUILD_NUMBER:-2}"
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
cp LICENSES/VideoEncoder.txt "$APP/Contents/Resources/VideoEncoder-LICENSE.txt"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$APP/Contents/Resources/AppUpdater-LICENSE.txt"
# SwiftPM links binary frameworks but does not package them into our custom bundle.
UPDATER_FRAMEWORK=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$UPDATER_FRAMEWORK" ]]; then
    echo "Updater framework not found at $UPDATER_FRAMEWORK" >&2
    exit 1
fi
mkdir -p "$APP/Contents/Frameworks"
ditto "$UPDATER_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
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
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>SUFeedURL</key><string>https://walldance.souk.dev/appcast.xml</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUAutomaticallyUpdate</key><false/>
    <key>SUVerifyUpdateBeforeExtraction</key><true/>
    <key>SURequireSignedFeed</key><true/>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD_NUMBER" "$APP/Contents/Info.plist"
public_key="$(tr -d '\n\r' < scripts/update-public-key.txt)"
if [[ ! "$public_key" =~ '^[A-Za-z0-9+/]{43}=$' ]]; then
    echo "scripts/update-public-key.txt must contain the public Ed25519 verification key" >&2
    exit 1
fi
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $public_key" "$APP/Contents/Info.plist"

sign_args=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != - ]]; then
    sign_args+=(--options runtime --timestamp)
fi
if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then
    sign_args+=(--keychain "$SIGNING_KEYCHAIN")
fi
# Sign nested code inside out, including the installer and relaunch helper.
framework="$APP/Contents/Frameworks/Sparkle.framework"
codesign "${sign_args[@]}" "$framework/Versions/B/XPCServices/Installer.xpc"
codesign "${sign_args[@]}" --preserve-metadata=entitlements "$framework/Versions/B/XPCServices/Downloader.xpc"
codesign "${sign_args[@]}" "$framework/Versions/B/Autoupdate"
codesign "${sign_args[@]}" "$framework/Versions/B/Updater.app"
codesign "${sign_args[@]}" "$framework"
codesign "${sign_args[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built $APP"
