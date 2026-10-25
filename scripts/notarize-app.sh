#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

: "${NOTARY_KEYCHAIN_PROFILE:?Set NOTARY_KEYCHAIN_PROFILE to a notarytool credentials profile}"
APP="dist/Walldance.app"
ARCHIVE="dist/Walldance.zip"
RESULT="dist/notarization-result.json"
LOG="dist/notarization-log.json"

if [[ ! -d "$APP" ]]; then
    echo "Build $APP with a Developer ID Application certificate first" >&2
    exit 1
fi
codesign --verify --deep --strict --verbose=2 "$APP"
auth_args=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
    auth_args+=(--keychain "$NOTARY_KEYCHAIN")
fi

# Never leave an archive from a previous run available after a failed submission.
rm -f "$ARCHIVE" "$RESULT" "$LOG"
SUBMISSION_DIR="$(mktemp -d "${TMPDIR:-/tmp}/walldance-notary.XXXXXX")"
trap 'rm -rf "$SUBMISSION_DIR"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$APP" "$SUBMISSION_DIR/Walldance.zip"

submit_exit=0
xcrun notarytool submit "$SUBMISSION_DIR/Walldance.zip" "${auth_args[@]}" \
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

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP"

# ZIP files cannot be stapled; recreate the archive with the stapled app inside.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
echo "Notarized archive: $ARCHIVE"
