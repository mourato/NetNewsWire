#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/project.sh
source "$SCRIPT_DIR/lib/project.sh"

[ -f "$PROJECT_ROOT/Modules/Secrets/Sources/Secrets/SecretKey.swift" ] || fail "missing generated SecretKey.swift; run make -C \"$PROJECT_ROOT\" test-account"

swift test --package-path "$PROJECT_ROOT/Modules/Account" "$@"
