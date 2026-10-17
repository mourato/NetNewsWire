#!/usr/bin/env bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/project.sh
source "$SCRIPT_DIR/lib/project.sh"

require_command xcodebuild
info "Xcode: $(xcode-select -p) ($(xcodebuild -version | sed -n 1p))"

info "Resolving packages..."
run_xcodebuild -derivedDataPath "$DERIVED_DATA_PATH" -resolvePackageDependencies

info "Building $APP_NAME (Debug, unsigned)..."
run_xcodebuild -configuration Debug -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination "$DESTINATION" build CODE_SIGNING_ALLOWED=NO

info "Testing..."
"$SCRIPT_DIR/test.sh"

info "Linting..."
"$SCRIPT_DIR/lint.sh"

info "Health checks passed."
