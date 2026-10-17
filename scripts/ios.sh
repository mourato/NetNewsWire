#!/usr/bin/env bash
# Project-specific: build or test the iOS target.
#
# The rest of scripts/ drives the macOS app. iOS lives here because it may need
# a different Xcode than the default one: a toolchain whose CoreSimulator
# matches the installed simulator runtime. Point IOS_DEVELOPER_DIR at it; leave
# it unset to use the default toolchain. IOS_SCHEME, IOS_DESTINATION and
# IOS_DERIVED_DATA come from scripts/config/project.env.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/project.sh
source "$SCRIPT_DIR/lib/project.sh"

usage() {
  cat <<'USAGE'
Usage: scripts/ios.sh [options]

Options:
  --test                     Run the iOS tests instead of building
  --configuration Debug|Release
  --clean
  --help
USAGE
}

MODE=build
CONFIGURATION=Debug
CLEAN=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --test) MODE=test; shift ;;
    --configuration|-c) [ "$#" -ge 2 ] || fail "$1 requires a value"; CONFIGURATION="$2"; shift 2 ;;
    --clean) CLEAN=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) fail "unknown option: $1" ;;
  esac
done

case "$CONFIGURATION" in
  Debug|Release) ;;
  *) fail "configuration must be Debug or Release" ;;
esac

[ -n "${IOS_SCHEME:-}" ] || fail "set IOS_SCHEME in $CONFIG_FILE"
[ -n "${IOS_DESTINATION:-}" ] || fail "set IOS_DESTINATION in $CONFIG_FILE"
IOS_DERIVED_DATA="${IOS_DERIVED_DATA:-.xcode-build/ios}"
case "$IOS_DERIVED_DATA" in /*|*..*) fail "unsafe IOS_DERIVED_DATA path: $IOS_DERIVED_DATA" ;; esac
IOS_DERIVED_DATA_PATH="$PROJECT_ROOT/$IOS_DERIVED_DATA"

if [ -n "${IOS_DEVELOPER_DIR:-}" ]; then
  [ -d "$IOS_DEVELOPER_DIR" ] || fail "IOS_DEVELOPER_DIR not found: $IOS_DEVELOPER_DIR"
  export DEVELOPER_DIR="$IOS_DEVELOPER_DIR"
  info "Toolchain: $DEVELOPER_DIR"
fi

if [ "$CLEAN" -eq 1 ]; then rm -rf "$IOS_DERIVED_DATA_PATH"; fi

# Simulator builds need no provisioning, and disabling signing keeps the
# extensions from requiring profiles that only device builds need.
settings=(CODE_SIGNING_ALLOWED=NO)
quiet=-quiet
[ "${SWIFT_XCODEBUILD_VERBOSE:-0}" = 1 ] && quiet=
export OS_ACTIVITY_MODE=disable

case "$MODE" in
  test) info "Testing $IOS_SCHEME ($CONFIGURATION)" ;;
  *) info "Building $IOS_SCHEME ($CONFIGURATION)" ;;
esac
"${XCODEBUILD:-/usr/bin/xcodebuild}" $quiet "$CONTAINER_FLAG" "$CONTAINER_PATH" \
  -scheme "$IOS_SCHEME" -configuration "$CONFIGURATION" \
  -destination "$IOS_DESTINATION" -derivedDataPath "$IOS_DERIVED_DATA_PATH" \
  "$MODE" "${settings[@]}"

if [ "$MODE" = build ]; then
  APP_BUNDLE="$(find "$IOS_DERIVED_DATA_PATH/Build/Products" -maxdepth 2 -type d \
    -name "$APP_NAME.app" -print 2>/dev/null | head -n 1)"
  validate_app_bundle "$APP_BUNDLE" || fail "built iOS app bundle was not found or is invalid"
  info "Built $APP_BUNDLE"
fi
