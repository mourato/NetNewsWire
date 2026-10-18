#!/bin/bash
set -euo pipefail

# Build an arm64-only Debug build of NetNewsWire
# and copy it to the Desktop for testing on Apple silicon Macs.

PROJECT_PATH="NetNewsWire.xcodeproj"
SCHEME="NetNewsWire"
DESTINATION="platform=macOS,arch=arm64"
DESKTOP="$HOME/Desktop"
APP_NAME="NetNewsWire.app"

check_bundle_executable() {
  local BUNDLE="$1"
  local INFO_PLIST="$BUNDLE/Contents/Info.plist"
  local EXECUTABLE_NAME
  local EXECUTABLE
  local ARCHS

  if [ ! -f "$INFO_PLIST" ]; then
    echo "Error: missing bundle Info.plist: $INFO_PLIST" >&2
    return 1
  fi

  EXECUTABLE_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")
  EXECUTABLE="$BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
  if [ ! -f "$EXECUTABLE" ]; then
    echo "Error: could not find bundle executable $EXECUTABLE" >&2
    return 1
  fi

  ARCHS=$(lipo -archs "$EXECUTABLE")
  echo "$ARCHS: $EXECUTABLE"
  if [ "$ARCHS" != "arm64" ]; then
    echo "Error: bundle executable is not arm64-only: $EXECUTABLE" >&2
    return 1
  fi
}

echo "Building arm64-only binary..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  ARCHS=arm64 \
  build | xcbeautify

# Find the built app in DerivedData.
BUILD_DIR=$(xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  ARCHS=arm64 \
  -showBuildSettings 2>/dev/null \
  | grep -m1 '^\\s*BUILT_PRODUCTS_DIR' \
  | sed 's/.*= //')

BUILT_APP="$BUILD_DIR/$APP_NAME"

if [ ! -d "$BUILT_APP" ]; then
  echo "Error: could not find $BUILT_APP" >&2
  exit 1
fi

# Check the app and every bundled macOS app extension; leave frameworks and
# their helper executables alone because dependencies may ship universal slices.
check_bundle_executable "$BUILT_APP"
while IFS= read -r -d '' BUNDLE; do
  check_bundle_executable "$BUNDLE"
done < <(find "$BUILT_APP/Contents/PlugIns" -type d -name '*.appex' -prune -print0)

# Also check standalone extension products in the build products directory.
for BUNDLE in "$BUILD_DIR"/*.appex; do
  [ -d "$BUNDLE" ] || continue
  check_bundle_executable "$BUNDLE"
done

# Copy to Desktop, replacing any existing copy.
rm -rf "$DESKTOP/$APP_NAME"
cp -R "$BUILT_APP" "$DESKTOP/$APP_NAME"

echo "Copied $APP_NAME to $DESKTOP"
echo "Remember: on the test machine, right-click > Open or run: xattr -cr $APP_NAME"
