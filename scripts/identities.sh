#!/usr/bin/env bash
# List code-signing identities as "SHA1  NAME". With --select, print the menu
# on stderr and only the selected SHA-1 on stdout; hashes stay unambiguous
# when renewed certificates share a name.

set -eo pipefail

MODE=list
while [ "$#" -gt 0 ]; do
  case "$1" in
    --select) MODE=select; shift ;;
    --list) MODE=list; shift ;;
    --help|-h) printf 'Usage: scripts/identities.sh [--list|--select]\n'; exit 0 ;;
    *) printf 'Error: unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
done

IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | \
  sed -n 's/^[[:space:]]*[0-9]*)[[:space:]]*\([A-Fa-f0-9]\{40\}\)[[:space:]]*"\(.*\)"$/\1  \2/p')"
[ -n "$IDENTITIES" ] || {
  printf 'No valid code-signing identities found. Sign in to Xcode > Settings > Accounts\n' >&2
  printf 'with any Apple ID to get a free "Apple Development" identity.\n' >&2
  exit 1
}

if [ "$MODE" = list ]; then
  printf '%s\n' "$IDENTITIES"
  exit 0
fi

[ -t 0 ] || { printf 'Error: identity selection requires a terminal; pass --identity\n' >&2; exit 1; }
printf 'Available code-signing identities:\n' >&2
printf '%s\n' "$IDENTITIES" | nl -w2 -s') ' >&2
read -r -p 'Choose an identity number: ' choice < /dev/tty || choice=""
case "$choice" in ''|*[!0-9]*) printf 'Error: invalid selection\n' >&2; exit 1 ;; esac
selected="$(printf '%s\n' "$IDENTITIES" | sed -n "${choice}p")"
[ -n "$selected" ] || { printf 'Error: invalid selection\n' >&2; exit 1; }
printf '%s\n' "${selected%%  *}"
