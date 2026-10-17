#!/usr/bin/env bash
# Run only the formatters/linters the project already declares.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/project.sh
source "$SCRIPT_DIR/lib/project.sh"

ran=0
if [ -f "$PROJECT_ROOT/.swiftformat" ]; then
  require_command swiftformat
  swiftformat --lint "$PROJECT_ROOT"
  ran=1
fi
if [ -f "$PROJECT_ROOT/.swiftlint.yml" ]; then
  require_command swiftlint
  swiftlint lint --quiet --config "$PROJECT_ROOT/.swiftlint.yml"
  ran=1
fi
[ "$ran" -eq 1 ] || info "No .swiftformat or .swiftlint.yml; lint skipped."
