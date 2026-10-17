#!/usr/bin/env bash
# Show or set MARKETING_VERSION and CURRENT_PROJECT_VERSION.
#
# Versions live either in an Xcode project file (project.pbxproj) or, as in
# NetNewsWire, in xcconfig files. All targets must share one value of each; the
# script refuses to guess when they diverge.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/project.sh
source "$SCRIPT_DIR/lib/project.sh"

XCODEPROJ="${VERSION_PROJECT_PATH:-}"
[ -n "$XCODEPROJ" ] || { [ "$CONTAINER_KIND" = project ] && XCODEPROJ="$PROJECT_PATH"; }

VERSION_FILES=()
if [ -n "${VERSION_XCCONFIG_FILES:-}" ]; then
  # shellcheck disable=SC2206
  VERSION_FILES=($VERSION_XCCONFIG_FILES)
fi

if [ "${#VERSION_FILES[@]}" -gt 0 ]; then
  VERSION_MODE=xcconfig
  VERSION_SOURCE_DESC="$CONFIG_FILE (VERSION_XCCONFIG_FILES)"
  for file in "${VERSION_FILES[@]}"; do
    case "$file" in /*|*..*) fail "unsafe relative path in VERSION_XCCONFIG_FILES: $file" ;; esac
    [ -f "$PROJECT_ROOT/$file" ] || fail "missing $PROJECT_ROOT/$file (listed in VERSION_XCCONFIG_FILES)"
  done
else
  VERSION_MODE=pbxproj
  [ -n "$XCODEPROJ" ] || fail "set VERSION_PROJECT_PATH in $CONFIG_FILE, or VERSION_XCCONFIG_FILES"
  PBXPROJ="$PROJECT_ROOT/$XCODEPROJ/project.pbxproj"
  VERSION_SOURCE_DESC="$PBXPROJ"
  [ -f "$PBXPROJ" ] || fail "missing $PBXPROJ"
fi

MARKETING=""
BUILD=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --marketing) [ "$#" -ge 2 ] || fail "--marketing requires X.Y[.Z]"; MARKETING="$2"; shift 2 ;;
    --build) [ "$#" -ge 2 ] || fail "--build requires a number"; BUILD="$2"; shift 2 ;;
    --bump-build) BUILD=bump; shift ;;
    --help|-h) printf 'Usage: scripts/version.sh [--marketing X.Y[.Z]] [--build N|--bump-build]\n'; exit 0 ;;
    *) fail "unknown option: $1" ;;
  esac
done

# Every file that already declares the setting, one path per line.
version_files_declaring() {
  local key="$1" file
  for file in "${VERSION_FILES[@]}"; do
    if grep -Eq "^[[:space:]]*$key[[:space:]]*=" "$PROJECT_ROOT/$file"; then
      printf '%s\n' "$PROJECT_ROOT/$file"
    fi
  done
}

current() {
  local key="$1" values
  if [ "$VERSION_MODE" = xcconfig ]; then
    values="$(version_files_declaring "$key" | while IFS= read -r file; do
      sed -n "s/^[[:space:]]*$key[[:space:]]*=[[:space:]]*\"\{0,1\}\([^\"]*[^\"[:space:]]\)\"\{0,1\}[[:space:]]*$/\1/p" "$file"
    done | sort -u)"
  else
    values="$(sed -n "s/^[[:space:]]*$key = \"\{0,1\}\([^\";]*\)\"\{0,1\};$/\1/p" "$PBXPROJ" | sort -u)"
  fi
  [ -n "$values" ] || fail "$key is not set in $VERSION_SOURCE_DESC"
  [ "$(printf '%s\n' "$values" | wc -l | tr -d ' ')" -eq 1 ] \
    || fail "$key differs between targets: $(printf '%s ' $values)"
  printf '%s\n' "$values"
}

set_setting() {
  local key="$1" value="$2" file
  if [ "$VERSION_MODE" = xcconfig ]; then
    local files
    files="$(version_files_declaring "$key")"
    [ -n "$files" ] || fail "set $key in one of VERSION_XCCONFIG_FILES before updating it"
    while IFS= read -r file; do
      sed -i '' "s|^\([[:space:]]*$key[[:space:]]*=[[:space:]]*\)\"\{0,1\}[^\";]*\"\{0,1\}[[:space:]]*;*[[:space:]]*$|\1$value|" "$file"
    done <<< "$files"
  else
    sed -i '' "s/^\([[:space:]]*$key = \)\"\{0,1\}[^\";]*\"\{0,1\};$/\1$value;/" "$PBXPROJ"
  fi
}

CURRENT_MARKETING="$(current MARKETING_VERSION)"
CURRENT_BUILD="$(current CURRENT_PROJECT_VERSION)"

if [ -n "$MARKETING" ]; then
  [[ "$MARKETING" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || fail "marketing version must be X.Y or X.Y.Z"
  set_setting MARKETING_VERSION "$MARKETING"
fi
if [ "$BUILD" = bump ]; then
  [[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]] || fail "cannot bump non-integer build: $CURRENT_BUILD"
  BUILD=$((CURRENT_BUILD + 1))
fi
if [ -n "$BUILD" ]; then
  [[ "$BUILD" =~ ^[0-9]+$ ]] || fail "build must be a positive integer"
  set_setting CURRENT_PROJECT_VERSION "$BUILD"
fi

info "$(current MARKETING_VERSION) ($(current CURRENT_PROJECT_VERSION))"
