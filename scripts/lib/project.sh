#!/usr/bin/env bash
# Shared helpers for the project scripts. Callers keep their own SCRIPT_DIR.

set -eo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$LIB_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/scripts/config/project.env"

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

confirm() {
  local answer
  read -r -p "$1 [y/N] " answer < /dev/tty || answer=""
  [ "$answer" = y ] || [ "$answer" = Y ]
}

[ -f "$CONFIG_FILE" ] || fail "missing $CONFIG_FILE"
# shellcheck disable=SC1090
source "$CONFIG_FILE"

for name in CONTAINER_KIND PROJECT_PATH SCHEME PLATFORM DESTINATION APP_NAME DERIVED_DATA DIST_DIR; do
  [ -n "${!name}" ] || fail "set $name in $CONFIG_FILE"
  case "${!name}" in *'@'*) fail "replace the @...@ marker for $name in $CONFIG_FILE" ;; esac
done

case "$CONTAINER_KIND" in
  project) CONTAINER_FLAG=-project ;;
  workspace) CONTAINER_FLAG=-workspace ;;
  *) fail "CONTAINER_KIND must be project or workspace" ;;
esac

for path in "$DERIVED_DATA" "$DIST_DIR"; do
  case "$path" in /*|*..*) fail "unsafe relative path in config: $path" ;; esac
done

CONTAINER_PATH="$PROJECT_ROOT/$PROJECT_PATH"
[ -e "$CONTAINER_PATH" ] || fail "project container not found: $CONTAINER_PATH"
DERIVED_DATA_PATH="$PROJECT_ROOT/$DERIVED_DATA"
DIST_PATH="$PROJECT_ROOT/$DIST_DIR"

# Set SWIFT_XCODEBUILD_VERBOSE=1 for full xcodebuild output.
run_xcodebuild() {
  local quiet=-quiet
  [ "${SWIFT_XCODEBUILD_VERBOSE:-0}" = 1 ] && quiet=
  "${XCODEBUILD:-/usr/bin/xcodebuild}" $quiet "$CONTAINER_FLAG" "$CONTAINER_PATH" -scheme "$SCHEME" "$@"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

# Signing build settings for an identity:
#   empty       = unsigned (CODE_SIGNING_ALLOWED=NO)
#   "-"         = ad-hoc
#   "automatic" = emit nothing and let the project's own settings decide, i.e.
#                 Xcode automatic signing. Targets that embed app extensions
#                 need this: xcodebuild then creates the provisioning profiles
#                 those extensions require, which Manual signing with a bare
#                 identity cannot do.
#   otherwise   = a Keychain SHA-1 hash or certificate name (Manual signing).
# Hardened runtime keeps Developer ID artifacts notarizable; entitlements come
# from the target.
signing_settings() {
  if [ -z "$1" ]; then
    printf '%s\n' CODE_SIGNING_ALLOWED=NO
    return
  fi
  if [ "$1" = automatic ]; then
    return 0
  fi
  printf '%s\n' CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$1" ENABLE_HARDENED_RUNTIME=YES
  [ -n "${SWIFT_DEVELOPMENT_TEAM:-}" ] && printf '%s\n' "DEVELOPMENT_TEAM=$SWIFT_DEVELOPMENT_TEAM"
  [ "$1" != - ] && printf '%s\n' 'OTHER_CODE_SIGN_FLAGS=--timestamp'
  return 0
}

# Extra xcodebuild arguments a signing mode needs. Automatic signing may have to
# create or update provisioning profiles, and an Apple Development certificate
# signs for local use only.
signing_xcodebuild_flags() {
  [ "$1" = automatic ] && printf '%s\n' -allowProvisioningUpdates
  return 0
}

# Built product for one configuration; ignores stale products from others.
find_app_bundle() {
  find "$DERIVED_DATA_PATH/Build/Products" -maxdepth 2 -type d \
    -path "*/$1*/$APP_NAME.app" -print 2>/dev/null | head -n 1
}

validate_app_bundle() {
  [ -d "$1" ] || return 1
  [ -f "$1/Contents/Info.plist" ] || [ -f "$1/Info.plist" ]
}
