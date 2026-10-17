#!/usr/bin/env bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/project.sh
source "$SCRIPT_DIR/lib/project.sh"

[ "$PLATFORM" = macOS ] || fail "packaging is only supported for macOS projects"

IDENTITY="${SWIFT_CODE_SIGN_IDENTITY:-}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --identity) [ "$#" -ge 2 ] || fail "--identity requires a value"; IDENTITY="$2"; shift 2 ;;
    --help|-h) printf 'Usage: scripts/package.sh [--identity HASH|NAME|-|automatic]\n'; exit 0 ;;
    *) fail "unknown option: $1" ;;
  esac
done

SWIFT_CODE_SIGN_IDENTITY="$IDENTITY" "$SCRIPT_DIR/build.sh" \
  --no-interactive --configuration Release --skip-open

APP_BUNDLE="$(find_app_bundle Release)"
validate_app_bundle "$APP_BUNDLE" || fail "Release app bundle was not found or is invalid"
mkdir -p "$DIST_PATH"
OUTPUT="$DIST_PATH/$APP_NAME.app"
rm -rf "$OUTPUT"
/usr/bin/ditto "$APP_BUNDLE" "$OUTPUT"
validate_app_bundle "$OUTPUT" || fail "packaged app bundle was not valid"
if [ -n "$IDENTITY" ]; then
  /usr/bin/codesign --verify --deep --strict "$OUTPUT" || fail "packaged app signature is invalid"
fi
info "Packaged $OUTPUT"
