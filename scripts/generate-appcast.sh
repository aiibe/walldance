#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

if [[ "$#" != 1 || ! -f "$1" || "$1" != *.dmg ]]; then
    echo "Usage: $0 dist/Walldance-<version>.dmg" >&2
    exit 1
fi

archive="${1:A}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Walldance.app/Contents/Info.plist)"
if [[ "${archive:t}" != "Walldance-$version.dmg" ]]; then
    echo "DMG filename must match the app version" >&2
    exit 1
fi
tools=".build/artifacts/sparkle/Sparkle/bin"
output="$(mktemp -d dist/update-feed.XXXXXX)"
trap 'rm -rf "$output"' EXIT
ditto "$archive" "$output/${archive:t}"
bash scripts/release-notes.sh "$version" > "$output/Walldance-$version.md"

args=(--maximum-deltas 0 --embed-release-notes
    --download-url-prefix "https://github.com/aiibe/walldance/releases/download/v$version/"
    --link "https://walldance.souk.dev")
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    # Keep the signing key off command lines and out of generated files.
    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$tools/generate_appcast" --ed-key-file - "${args[@]}" "$output"
    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$tools/sign_update" --ed-key-file - --verify "$output/appcast.xml"
else
    "$tools/generate_appcast" --account com.walldance.app "${args[@]}" "$output"
    "$tools/sign_update" --account com.walldance.app --verify "$output/appcast.xml"
fi

# Never upload a feed with an unsigned archive, even if generation returned success.
python3 - "$output/appcast.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
items = root.findall("channel/item")
if len(items) != 1:
    raise SystemExit("Expected exactly one release in the appcast")
enclosure = items[0].find("enclosure")
if enclosure is None or not enclosure.get("{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"):
    raise SystemExit("Update archive is unsigned")
PY
cp "$output/appcast.xml" dist/appcast.xml
echo "Verified update feed: dist/appcast.xml"
