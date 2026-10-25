#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

: "${NOTARY_KEYCHAIN_PROFILE:?Set NOTARY_KEYCHAIN_PROFILE to a notarytool credentials profile}"
if [[ "$#" -gt 1 ]]; then
    echo "Usage: $0 [path/to/Walldance.dmg]" >&2
    exit 1
fi
TARGET="${1:-dist/Walldance.app}"
ARCHIVE="dist/Walldance.zip"
RESULT="dist/notarization-result.json"
LOG="dist/notarization-log.json"

if [[ "$#" == 1 && ( "$TARGET" != *.dmg || ! -f "$TARGET" ) ]]; then
    echo "Provide an existing, signed DMG" >&2
    exit 1
fi
if [[ "$#" == 0 && ! -d "$TARGET" ]]; then
    echo "Build $TARGET with a Developer ID Application certificate first" >&2
    exit 1
fi
codesign --verify --deep --strict --verbose=2 "$TARGET"
auth_args=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
    auth_args+=(--keychain "$NOTARY_KEYCHAIN")
fi

rm -f "$RESULT" "$LOG"
SUBMISSION="$TARGET"
if [[ -d "$TARGET" ]]; then
    # Never leave an archive from a previous run after a failed submission.
    rm -f "$ARCHIVE"
    SUBMISSION_DIR="$(mktemp -d "${TMPDIR:-/tmp}/walldance-notary.XXXXXX")"
    trap 'rm -rf "$SUBMISSION_DIR"' EXIT
    SUBMISSION="$SUBMISSION_DIR/Walldance.zip"
    ditto -c -k --sequesterRsrc --keepParent "$TARGET" "$SUBMISSION"
fi

submit_exit=0
xcrun notarytool submit "$SUBMISSION" "${auth_args[@]}" \
    --wait --timeout 30m --output-format json > "$RESULT" || submit_exit=$?
cat "$RESULT"

SUBMISSION_ID="$(plutil -extract id raw -o - "$RESULT" 2>/dev/null || true)"
NOTARY_STATUS="$(plutil -extract status raw -o - "$RESULT" 2>/dev/null || true)"
if [[ -n "$SUBMISSION_ID" ]]; then
    echo "Notarization submission: $SUBMISSION_ID"
    # Keep Apple's diagnostics even for rejected submissions.
    xcrun notarytool log "$SUBMISSION_ID" "${auth_args[@]}" "$LOG" || true
fi
if [[ "$submit_exit" != 0 || "$NOTARY_STATUS" != Accepted ]]; then
    echo "Notarization did not succeed. Check $RESULT and $LOG." >&2
    exit 1
fi

xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
codesign --verify --deep --strict --verbose=2 "$TARGET"

if [[ -d "$TARGET" ]]; then
    spctl --assess --type execute --verbose=2 "$TARGET"
    # ZIP files cannot be stapled; recreate the archive with the stapled app inside.
    ditto -c -k --sequesterRsrc --keepParent "$TARGET" "$ARCHIVE"
    echo "Notarized archive: $ARCHIVE"
else
    spctl --assess --type open --context context:primary-signature --verbose=2 "$TARGET"
    echo "Notarized disk image: $TARGET"
fi
