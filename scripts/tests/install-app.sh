#!/usr/bin/env bash
# Public installer contract: real temporary filesystem, fake platform boundaries.
set -eo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/install-app-tests.XXXXXX")"
TEMP="$(cd "$TEMP" && pwd -P)"
trap 'rm -rf "$TEMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$TEMP/repo/scripts/lib" "$TEMP/repo/scripts/config" "$TEMP/bin" "$TEMP/apps" "$TEMP/seed/Contents/MacOS"
cp "$ROOT/scripts/install-app.sh" "$ROOT/scripts/build.sh" "$TEMP/repo/scripts/"
cp "$ROOT/scripts/lib/project.sh" "$TEMP/repo/scripts/lib/"
touch "$TEMP/repo/Test.xcodeproj"
cat > "$TEMP/repo/scripts/config/project.env" <<'CONFIG'
CONTAINER_KIND=project
PROJECT_PATH=Test.xcodeproj
SCHEME=Test
PLATFORM=macOS
DESTINATION=platform=macOS
APP_NAME=NetNewsWire
DERIVED_DATA=.build
DIST_DIR=dist
CONFIG
cat > "$TEMP/seed/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>test.netnewswire</string><key>CFBundleExecutable</key><string>NetNewsWire</string></dict></plist>
PLIST
printf '#!/bin/sh\nexit 0\n' > "$TEMP/seed/Contents/MacOS/NetNewsWire"
chmod +x "$TEMP/seed/Contents/MacOS/NetNewsWire"
echo new > "$TEMP/seed/version"
cat > "$TEMP/bin/xcodebuild" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_ROOT/build-args"
[ "${FAIL_AT:-}" != build ] || exit 1
mkdir -p "$TEST_ROOT/repo/.build/Build/Products/Release"
cp -R "$TEST_ROOT/seed" "$TEST_ROOT/repo/.build/Build/Products/Release/NetNewsWire.app"
STUB
cat > "$TEMP/bin/codesign" <<'STUB'
#!/bin/bash
[ "${FAIL_AT:-}" != signature ] || exit 1
if [ "$1" = --display ]; then
  if [ "${FAIL_AT:-}" = adhoc ]; then echo Signature=adhoc; else printf 'Authority=Apple Development: Fixture\nTeamIdentifier=TEST123\n'; fi
fi
STUB
cat > "$TEMP/bin/ditto" <<'STUB'
#!/bin/bash
[ "${FAIL_AT:-}" != staging ] || exit 1
cp -R "$1" "$2"
STUB
cat > "$TEMP/bin/mv" <<'STUB'
#!/bin/bash
if [ "${FAIL_AT:-}" = publish ] && [[ "$1" == *install-stage* ]]; then exit 1; fi
/bin/mv "$@"
if [ "${FAIL_AT:-}" = term ] && [[ "$2" == *install-backup* ]]; then kill -TERM "$PPID"; fi
STUB
cat > "$TEMP/bin/open" <<'STUB'
#!/bin/bash
[ "${FAIL_AT:-}" != launch ]
STUB
cat > "$TEMP/bin/rm" <<'STUB'
#!/bin/bash
if [ "${FAIL_AT:-}" = cleanup ] && [[ "$*" == *install-backup* ]]; then exit 1; fi
/bin/rm "$@"
STUB
cat > "$TEMP/bin/ps" <<'STUB'
#!/bin/bash
[ "${FAIL_AT:-}" != ps ] || exit 1
if [ "${PROCESS_CASE:-}" = large ] && [ ! -e "$TEST_ROOT/quit-requested" ]; then
  echo "$TEST_ROOT/apps/NetNewsWire.app/Contents/MacOS/NetNewsWire"
  awk 'BEGIN { for (i=0; i<100000; i++) print "/other/process" }'
fi
STUB
cat > "$TEMP/bin/osascript" <<'STUB'
#!/bin/bash
[ "$2" = "$TEST_ROOT/apps/NetNewsWire.app" ] || exit 1
touch "$TEST_ROOT/quit-requested"
STUB
chmod +x "$TEMP/bin/"*
export TEST_ROOT="$TEMP" PATH="$TEMP/bin:$PATH" XCODEBUILD="$TEMP/bin/xcodebuild" SWIFT_CODE_SIGN_IDENTITY=-
INSTALL="$TEMP/repo/scripts/install-app.sh"
DEST="$TEMP/apps/NetNewsWire.app"
reset_old() {
  rm -rf "$DEST" "$TEMP/repo/.build"
  cp -R "$TEMP/seed" "$DEST"
  echo old > "$DEST/version"
}
assert_old() {
  [ "$(cat "$DEST/version")" = old ] || { echo 'previous installation changed' >&2; exit 1; }
  [ ! -e "$TEMP/apps/.NetNewsWire.install-lock" ]
  [ ! -e "$TEMP/apps/.NetNewsWire.install-backup.app" ]
}
run_install() { "$INSTALL" --applications-dir "$TEMP/apps" --yes "$@" > "$TEMP/output" 2>&1; }
for failure in build signature adhoc staging publish launch ps term; do
  reset_old
  export FAIL_AT="$failure"
  if run_install; then echo "expected $failure rejection" >&2; exit 1; fi
  assert_old
done
unset FAIL_AT
reset_old
export PROCESS_CASE=large
run_install --skip-open
[ -f "$TEMP/quit-requested" ] || { echo 'running app was replaced without requesting quit' >&2; exit 1; }
[ "$(cat "$DEST/version")" = new ]
unset PROCESS_CASE
reset_old
run_install --skip-open
[ "$(cat "$DEST/version")" = new ]
# Build arguments are a public signing/configuration contract, even with an ad-hoc environment override.
grep -Fxq Release "$TEMP/build-args"
! grep -Fxq CODE_SIGNING_ALLOWED=NO "$TEMP/build-args"
! grep -Fxq CODE_SIGN_IDENTITY=- "$TEMP/build-args"
grep -Fxq -- -allowProvisioningUpdates "$TEMP/build-args"
run_install --skip-open
[ "$(cat "$DEST/version")" = new ]
reset_old
export FAIL_AT=cleanup
if run_install --skip-open; then echo 'expected cleanup failure' >&2; exit 1; fi
[ "$(cat "$DEST/version")" = new ]
[ "$(cat "$TEMP/apps/.NetNewsWire.install-backup.app/version")" = old ]
unset FAIL_AT
rm -rf "$TEMP/apps/.NetNewsWire.install-backup.app"
reset_old
mkdir "$TEMP/apps/.NetNewsWire.install-lock"
if run_install --skip-open; then echo 'overlapping installation accepted' >&2; exit 1; fi
[ ! -e "$TEMP/repo/.build" ]
rmdir "$TEMP/apps/.NetNewsWire.install-lock"
assert_old
# Unknown backups and symlinks are operator-owned recovery state.
mkdir "$TEMP/apps/.NetNewsWire.install-backup.app"
if run_install --skip-open; then exit 1; fi
[ -d "$TEMP/apps/.NetNewsWire.install-backup.app" ]
rmdir "$TEMP/apps/.NetNewsWire.install-backup.app"
rm -rf "$DEST"
ln -s "$TEMP/seed" "$DEST"
if run_install --skip-open; then exit 1; fi
[ -L "$DEST" ]
echo 'PASS install-app: Release signing, repeat install, eight failure rollbacks, large process output, lock and recovery guards'
