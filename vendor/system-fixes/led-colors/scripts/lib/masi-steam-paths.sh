#!/bin/bash
# Copy shared steam path helpers (same as Power-FEX).
# Source this file; do not execute directly.

masi_resolve_target_user() {
  if [[ -n "${MASI_USER:-}" ]]; then
    TARGET_USER="$MASI_USER"
  elif [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    TARGET_USER="$SUDO_USER"
  else
    TARGET_USER="$(id -un)"
  fi

  if ! id "$TARGET_USER" &>/dev/null; then
    echo "User not found: $TARGET_USER" >&2
    return 1
  fi

  TARGET_UID="$(id -u "$TARGET_USER")"
  TARGET_GID="$(id -g "$TARGET_USER")"
  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
    echo "Home directory not found for user: $TARGET_USER" >&2
    return 1
  fi
}
