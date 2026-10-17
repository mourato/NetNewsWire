#!/usr/bin/env bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/project.sh
source "$SCRIPT_DIR/lib/project.sh"

[ "$PLATFORM" = macOS ] || fail "DMG packaging is only supported for macOS projects"

SIGNING_MODE=""
IDENTITY="${SWIFT_CODE_SIGN_IDENTITY:-}"
NO_INTERACTIVE=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --signing-mode) [ "$#" -ge 2 ] || fail "--signing-mode requires unsigned, adhoc, or identity"; SIGNING_MODE="$2"; shift 2 ;;
    --identity) [ "$#" -ge 2 ] || fail "--identity requires a value"; IDENTITY="$2"; SIGNING_MODE="${SIGNING_MODE:-identity}"; shift 2 ;;
    --no-interactive) NO_INTERACTIVE=1; shift ;;
    --help|-h) printf 'Usage: scripts/create-dmg.sh [--signing-mode unsigned|adhoc|identity] [--identity HASH|NAME|-|automatic] [--no-interactive]\n'; exit 0 ;;
    *) fail "unknown option: $1" ;;
  esac
done

if [ "$NO_INTERACTIVE" -eq 0 ] && [ -z "$SIGNING_MODE" ]; then
  printf '1) Unsigned\n2) Automatic (project signing settings; DMG stays unsigned)\n3) Ad-hoc\n4) Keychain identity\n5) Exit\n'
  read -r -p 'DMG signing [1/2/3/4/5] [1]: ' choice < /dev/tty || choice=""
  case "${choice:-1}" in
    1) SIGNING_MODE=unsigned ;;
    2) SIGNING_MODE=identity; IDENTITY=automatic ;;
    3) SIGNING_MODE=adhoc ;;
    4) SIGNING_MODE=identity ;;
    5) exit 0 ;;
    *) fail "invalid signing choice: $choice" ;;
  esac
fi

case "${SIGNING_MODE:-unsigned}" in
  unsigned) IDENTITY="" ;;
  adhoc) IDENTITY=- ;;
  identity) [ -n "$IDENTITY" ] || IDENTITY="$("$SCRIPT_DIR/identities.sh" --select)" ;;
  *) fail "signing mode must be unsigned, adhoc, or identity" ;;
esac

# The app is signed once by xcodebuild with its own entitlements; never re-sign it here.
"$SCRIPT_DIR/package.sh" --identity "$IDENTITY"

APP_BUNDLE="$DIST_PATH/$APP_NAME.app"
DMG_PATH="$DIST_PATH/$APP_NAME.dmg"
STAGING_DIR="$(mktemp -d "$DIST_PATH/.dmg-staging.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

/usr/bin/ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"
/usr/bin/hdiutil create -quiet -srcfolder "$STAGING_DIR" -volname "$APP_NAME" -format UDZO "$DMG_PATH"

# - and automatic leave the disk image unsigned: an Apple Development
# certificate signs for local use and cannot produce a distributable image.
# Only a real Developer ID Application identity signs the DMG.
case "$IDENTITY" in
  ""|-|automatic) ;;
  *)
    /usr/bin/codesign --sign "$IDENTITY" --timestamp "$DMG_PATH"
    /usr/bin/codesign --verify --verbose=2 "$DMG_PATH"
    ;;
esac
info "Created $DMG_PATH"

if [ "$NO_INTERACTIVE" -eq 0 ] && confirm 'Open the DMG now?'; then
  /usr/bin/open "$DMG_PATH"
fi
