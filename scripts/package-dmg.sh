#!/bin/bash
#
# package-dmg.sh — turn an exported, notarized BookTracker.app into a
# signed + notarized + stapled .dmg with a drag-to-Applications layout.
#
# Prerequisites (one-time):
#   brew install create-dmg
#   # Store notary credentials in the keychain so notarytool can find them:
#   xcrun notarytool store-credentials "BookTrackerNotary" \
#       --apple-id "shearm@mac.com" \
#       --team-id "95E9CZ9HW6" \
#       --password "<app-specific-password>"   # from appleid.apple.com
#
# Usage:
#   ./scripts/package-dmg.sh /path/to/exported/BookTracker.app
#
# The .app you pass MUST already be Developer-ID signed, notarized, and
# stapled (i.e. the output of Xcode's "Direct Distribution" export).

set -euo pipefail

# ---- Config -----------------------------------------------------------------
APP_NAME="BookTracker"
TEAM_ID="95E9CZ9HW6"
SIGN_IDENTITY="Developer ID Application: ${DEVID_NAME:-} (${TEAM_ID})"
NOTARY_PROFILE="${NOTARY_PROFILE:-BookTrackerNotary}"   # keychain profile name
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKGROUND="$SCRIPT_DIR/assets/dmg-background.png"

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "error: pass the path to your exported ${APP_NAME}.app" >&2
  echo "usage: $0 /path/to/${APP_NAME}.app" >&2
  exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "error: create-dmg not found. Install with: brew install create-dmg" >&2
  exit 1
fi

# Resolve the Developer ID identity automatically if DEVID_NAME wasn't set,
# so you don't have to hardcode your name.
if [[ -z "${DEVID_NAME:-}" ]]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" | head -1 \
    | sed -E 's/.*"(Developer ID Application: .*)"/\1/')
  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "error: no 'Developer ID Application' identity found in keychain." >&2
    exit 1
  fi
fi
echo "==> Signing identity: $SIGN_IDENTITY"

WORKDIR="$(mktemp -d)"
STAGE="$WORKDIR/stage"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
DMG_PATH="$(pwd)/${APP_NAME}.dmg"
rm -f "$DMG_PATH"

# Pull the .icns out of the app bundle to use as the volume icon (optional).
VOLICON_ARG=()
ICNS=$(/usr/bin/find "$APP_PATH/Contents/Resources" -maxdepth 1 -name '*.icns' | head -1 || true)
[[ -n "$ICNS" ]] && VOLICON_ARG=(--volicon "$ICNS")

# Use the arrow background if it's present; otherwise fall back to a plain DMG.
BACKGROUND_ARG=()
if [[ -f "$BACKGROUND" ]]; then
  BACKGROUND_ARG=(--background "$BACKGROUND")
else
  echo "warning: background not found at $BACKGROUND — building without it." >&2
fi

echo "==> Building DMG with drag-to-Applications layout..."
create-dmg \
  --volname "$APP_NAME" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "${APP_NAME}.app" 150 190 \
  --hide-extension "${APP_NAME}.app" \
  --app-drop-link 450 190 \
  "${BACKGROUND_ARG[@]}" \
  "${VOLICON_ARG[@]}" \
  "$DMG_PATH" \
  "$STAGE"

echo "==> Signing the DMG..."
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"

echo "==> Submitting DMG for notarization (this can take a few minutes)..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo "==> Verifying..."
xcrun stapler validate "$DMG_PATH"
spctl -a -vvv -t open --context context:primary-signature "$DMG_PATH" || true

rm -rf "$WORKDIR"
echo ""
echo "Done. Ship it: $DMG_PATH"
