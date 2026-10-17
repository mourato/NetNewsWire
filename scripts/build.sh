#!/usr/bin/env bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/project.sh
source "$SCRIPT_DIR/lib/project.sh"

CONFIGURATION=""
IDENTITY="${SWIFT_CODE_SIGN_IDENTITY:-}"
NO_INTERACTIVE=0
CLEAN=0
SKIP_OPEN=0

usage() {
  cat <<'USAGE'
Usage: scripts/build.sh [options]

Options:
  --configuration Debug|Release
  --clean
  --identity HASH|NAME|-|automatic
                             Keychain identity, - for ad-hoc, or automatic to
                             let the project's own (Xcode automatic) signing
                             settings apply
  --skip-open
  --no-interactive
  --help
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --configuration|-c) [ "$#" -ge 2 ] || fail "$1 requires a value"; CONFIGURATION="$2"; shift 2 ;;
    --clean) CLEAN=1; shift ;;
    --identity) [ "$#" -ge 2 ] || fail "--identity requires a value"; IDENTITY="$2"; shift 2 ;;
    --skip-open) SKIP_OPEN=1; shift ;;
    --no-interactive) NO_INTERACTIVE=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) fail "unknown option: $1" ;;
  esac
done

if [ "$NO_INTERACTIVE" -eq 0 ] && [ -z "$CONFIGURATION" ]; then
  [ -t 0 ] && [ -t 1 ] || fail "interactive build requires a terminal; pass --no-interactive --configuration Debug|Release"
  printf '1) Debug\n2) Release\n3) Exit\n'
  read -r -p 'Choose [1/2/3] [1]: ' choice < /dev/tty || choice=""
  case "${choice:-1}" in
    1) CONFIGURATION=Debug ;;
    2) CONFIGURATION=Release ;;
    3) exit 0 ;;
    *) fail "invalid choice: $choice" ;;
  esac
  if confirm 'Clean build artifacts first?'; then CLEAN=1; fi
fi
[ -n "$CONFIGURATION" ] || CONFIGURATION=Debug

case "$CONFIGURATION" in
  Debug|Release) ;;
  *) fail "configuration must be Debug or Release" ;;
esac

if [ "$NO_INTERACTIVE" -eq 0 ] && [ "$CONFIGURATION" = Release ] && [ -z "$IDENTITY" ]; then
  printf '1) Unsigned\n2) Automatic (project signing settings)\n3) Ad-hoc\n4) Select a Keychain identity\n5) Cancel\n'
  read -r -p 'Signing [1/2/3/4/5] [1]: ' signing_choice < /dev/tty || signing_choice=""
  case "${signing_choice:-1}" in
    1) ;;
    2) IDENTITY=automatic ;;
    3) IDENTITY=- ;;
    4) IDENTITY="$("$SCRIPT_DIR/identities.sh" --select)" ;;
    5) exit 0 ;;
    *) fail "invalid signing choice: $signing_choice" ;;
  esac
fi

if [ "$CLEAN" -eq 1 ]; then rm -rf "$DERIVED_DATA_PATH"; fi
settings=()
while IFS= read -r setting; do settings+=("$setting"); done < <(signing_settings "$IDENTITY")
extra_flags=()
while IFS= read -r flag; do extra_flags+=("$flag"); done < <(signing_xcodebuild_flags "$IDENTITY")
run_xcodebuild -configuration "$CONFIGURATION" -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination "$DESTINATION" build "${settings[@]}" "${extra_flags[@]}"

APP_BUNDLE="$(find_app_bundle "$CONFIGURATION")"
validate_app_bundle "$APP_BUNDLE" || fail "built $CONFIGURATION app bundle was not found or is invalid"
info "Built $APP_BUNDLE"

if [ "$SKIP_OPEN" -eq 0 ] && [ "$PLATFORM" = macOS ]; then
  /usr/bin/open "$APP_BUNDLE"
fi
