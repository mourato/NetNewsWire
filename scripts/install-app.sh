#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/project.sh"

APPLICATIONS_DIR=/Applications
YES=0
SKIP_OPEN=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --applications-dir) [ "$#" -ge 2 ] || fail "$1 requires a directory"; APPLICATIONS_DIR="$2"; shift 2 ;;
    --yes) YES=1; shift ;;
    --skip-open) SKIP_OPEN=1; shift ;;
    --help|-h) echo 'Usage: scripts/install-app.sh [--applications-dir DIR] [--yes] [--skip-open]'; exit 0 ;;
    *) fail "unknown option: $1" ;;
  esac
done
[ "$PLATFORM" = macOS ] || fail 'install-app requires macOS'
[ -d "$APPLICATIONS_DIR" ] && [ -w "$APPLICATIONS_DIR" ] || fail 'applications directory must exist and be writable (no sudo is used)'
APPLICATIONS_DIR="$(cd "$APPLICATIONS_DIR" && pwd -P)"
DEST="$APPLICATIONS_DIR/$APP_NAME.app"
LOCK="$APPLICATIONS_DIR/.$APP_NAME.install-lock"
BACKUP="$APPLICATIONS_DIR/.$APP_NAME.install-backup.app"
STAGE=""
OLD_MOVED=0
PUBLISHING=0
SUCCESS=0
mkdir "$LOCK" 2>/dev/null || fail "installation locked: $LOCK; inspect any running installer before manually removing a stale lock"
cleanup() {
  local status=$?
  set +e
  trap - EXIT INT TERM
  if [ "$SUCCESS" -eq 0 ]; then
    if [ "$PUBLISHING" -eq 1 ] && [ ! -e "$STAGE/$APP_NAME.app" ]; then rm -rf "$DEST" || status=1; fi
    if [ "$OLD_MOVED" -eq 1 ] && [ -d "$BACKUP" ]; then
      if [ ! -e "$DEST" ] && mv "$BACKUP" "$DEST"; then :; else
        echo "Recovery required: previous app preserved at $BACKUP" >&2
        status=1
      fi
    fi
  fi
  [ -z "$STAGE" ] || rm -rf "$STAGE"
  rmdir "$LOCK" || status=1
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
[ ! -e "$BACKUP" ] && [ ! -L "$BACKUP" ] || fail "stale backup at $BACKUP; recover it manually before installing"
[ ! -L "$DEST" ] || fail "destination is a symlink: $DEST"
plist_value() { plutil -extract "$2" raw -o - "$1/Contents/Info.plist"; }
validate() {
  local app="$1" executable signature
  [ -d "$app" ] && [ ! -L "$app" ] || return 1
  [ "$(plist_value "$app" CFBundleIdentifier)" = "$BUNDLE_ID" ] || return 1
  executable="$(plist_value "$app" CFBundleExecutable)" || return 1
  case "$executable" in ''|*/*|.|..) return 1 ;; esac
  [ ! -L "$app/Contents" ] && [ ! -L "$app/Contents/Info.plist" ] && [ ! -L "$app/Contents/MacOS" ] || return 1
  [ ! -L "$app/Contents/MacOS/$executable" ] && [ -x "$app/Contents/MacOS/$executable" ] || return 1
  codesign --verify --deep --strict "$app" || return 1
  signature="$(codesign --display --verbose=4 "$app" 2>&1)" || return 1
  printf '%s\n' "$signature" | grep -q '^Authority=.' || return 1
  printf '%s\n' "$signature" | grep -Eq '^TeamIdentifier=[A-Za-z0-9]+$' || return 1
  ! printf '%s\n' "$signature" | grep -q '^Signature=adhoc'
}
"$SCRIPT_DIR/build.sh" --no-interactive --configuration Release --identity automatic --skip-open
CANDIDATE="$DERIVED_DATA_PATH/Build/Products/Release/$APP_NAME.app"
BUNDLE_ID="$(plist_value "$CANDIDATE" CFBundleIdentifier)" || fail 'missing Release bundle identifier'
[ -n "$BUNDLE_ID" ] || fail 'empty Release bundle identifier'
validate "$CANDIDATE" || fail 'Release app must be executable and validly certificate signed'
if [ -e "$DEST" ]; then
  [ "$(plist_value "$DEST" CFBundleIdentifier)" = "$BUNDLE_ID" ] || fail "refusing to replace an unrelated app: $DEST"
fi
if [ "$YES" -eq 0 ]; then
  confirm "Install Release app at $DEST?" || exit 0
fi
STAGE="$(mktemp -d "$APPLICATIONS_DIR/.$APP_NAME.install-stage.XXXXXX")"
ditto "$CANDIDATE" "$STAGE/$APP_NAME.app"
validate "$STAGE/$APP_NAME.app" || fail 'staged app validation failed'
# Match the full executable path, so another copy of the app is unaffected.
running() {
  ps -axo comm= | grep -Fxq "$DEST/Contents/MacOS/$(plist_value "$DEST" CFBundleExecutable)"
}
if [ -e "$DEST" ] && running; then
  osascript - "$DEST" <<'APPLESCRIPT'
on run argv
  tell application (item 1 of argv) to quit
end run
APPLESCRIPT
  for ((attempt=0; attempt<30; attempt++)); do
    running || break
    sleep 1
  done
  running && fail 'installed app did not quit within 30 seconds; quit it manually and retry'
fi
if [ -e "$DEST" ]; then
  OLD_MOVED=1
  mv "$DEST" "$BACKUP"
fi
PUBLISHING=1
mv "$STAGE/$APP_NAME.app" "$DEST"
validate "$DEST" || fail 'installed app validation failed'
if [ "$SKIP_OPEN" -eq 0 ]; then open "$DEST"; fi
SUCCESS=1
if [ "$OLD_MOVED" -eq 1 ]; then
  rm -rf "$BACKUP" || fail "installed app is valid, but backup cleanup failed at $BACKUP; inspect it manually"
fi
info "Installed Release app at $DEST"
