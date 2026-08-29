#!/usr/bin/env bash
# Run a command as root when `sudo` fails with "unable to allocate pty".
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="${ROOT_DIR}/scripts/$(basename "${BASH_SOURCE[0]}")"
[[ $# -ge 1 ]] || { echo "Usage: $0 <command> [args...]" >&2; exit 1; }
resolve() {
  local p="$1"
  if [[ -f "$p" && "$p" != /* ]]; then
    printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd)" "$(basename "$p")"
  else
    printf '%s\n' "$p"
  fi
}
CMD="$(resolve "$1")"; shift
ARGS=("$@")
if [[ "${EUID}" -eq 0 ]]; then
  exec "$CMD" "${ARGS[@]}"
fi
if sudo -n true 2>/dev/null; then
  exec sudo -- "$CMD" "${ARGS[@]}"
fi
if command -v pkexec >/dev/null 2>&1; then
  export DISPLAY="${DISPLAY:-:0}"
  exec pkexec env DISPLAY="$DISPLAY" \
    XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}" HOME="$HOME" \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    /usr/bin/bash "$SELF" "$CMD" "${ARGS[@]}"
fi
echo "ERROR: need root (sudo PTY failed, pkexec missing)" >&2
exit 1
