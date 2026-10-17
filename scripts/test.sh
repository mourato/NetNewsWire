#!/usr/bin/env bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/project.sh
source "$SCRIPT_DIR/lib/project.sh"

if [ -z "${TEST_SCHEME:-}" ] || [ -z "${TEST_DESTINATION:-}" ]; then
  info "No test scheme configured."
  exit 0
fi
case "$TEST_SCHEME$TEST_DESTINATION" in *'@'*) fail "replace the TEST_* markers in $CONFIG_FILE or leave them empty" ;; esac

"${XCODEBUILD:-/usr/bin/xcodebuild}" -quiet "$CONTAINER_FLAG" "$CONTAINER_PATH" -scheme "$TEST_SCHEME" \
  -destination "$TEST_DESTINATION" -derivedDataPath "$DERIVED_DATA_PATH" test CODE_SIGNING_ALLOWED=NO "$@"
