#!/usr/bin/env bash
# Deck-like: after Plasma desktop login, next greetd session → gaming.
# Do not override when the user explicitly chose Plasma Mobile.
set -euo pipefail

SESSION_FILE=/var/lib/steamos-ubuntu/session
sess=""
[[ -f "$SESSION_FILE" ]] && sess="$(tr -d '[:space:]' < "$SESSION_FILE")"

case "$sess" in
  plasma-mobile|plasma-mobile.desktop)
    exit 0
    ;;
esac

if [[ -f /var/lib/steamos-ubuntu/plasma-handoff ]]; then
  rm -f /var/lib/steamos-ubuntu/plasma-handoff
  exit 0
fi

exec pkexec /usr/lib/steamos/steam-set-session gamescope-session.desktop
