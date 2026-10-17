#!/usr/bin/env bash
# Notarize and staple dist/APP.dmg. Requires a Developer ID Application signed
# DMG and a notarytool Keychain profile created once with:
#   xcrun notarytool store-credentials PROFILE_NAME

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/project.sh
source "$SCRIPT_DIR/lib/project.sh"

PROFILE="${SWIFT_NOTARY_PROFILE:-}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile) [ "$#" -ge 2 ] || fail "--profile requires a value"; PROFILE="$2"; shift 2 ;;
    --help|-h) printf 'Usage: scripts/notarize.sh [--profile KEYCHAIN_PROFILE]\n'; exit 0 ;;
    *) fail "unknown option: $1" ;;
  esac
done

[ -n "$PROFILE" ] || fail "pass --profile or set SWIFT_NOTARY_PROFILE (see: xcrun notarytool store-credentials)"
DMG_PATH="$DIST_PATH/$APP_NAME.dmg"
[ -f "$DMG_PATH" ] || fail "missing $DMG_PATH; run make dmg ARGS='--identity <Developer ID Application>' first"
/usr/bin/codesign -dvv "$DMG_PATH" 2>&1 | grep -q 'Authority=Developer ID Application' \
  || fail "$DMG_PATH is not signed with a Developer ID Application identity"

/usr/bin/xcrun notarytool submit "$DMG_PATH" --keychain-profile "$PROFILE" --wait
/usr/bin/xcrun stapler staple "$DMG_PATH"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"
info "Notarized $DMG_PATH"
