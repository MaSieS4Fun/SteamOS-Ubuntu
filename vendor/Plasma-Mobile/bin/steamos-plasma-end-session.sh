#!/usr/bin/env bash
# End current Plasma desktop/mobile user session so greetd can start the next one.
set +e

LOG=/var/log/steamos-session.log
log() {
  printf 'plasma-end-session: %s\n' "$*"
  printf 'plasma-end-session: %s\n' "$*" >>"$LOG" 2>/dev/null || true
}

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
LOCK="${RUNTIME_DIR}/steamos-plasma-switch.lock"
mkdir -p "$RUNTIME_DIR" 2>/dev/null || true

exec 9>"$LOCK"
if ! flock -n 9; then
  log "switch already in progress — skip"
  exit 0
fi

plasma_still_running() {
  pgrep -x kwin_wayland >/dev/null 2>&1 && return 0
  pgrep -x plasmashell >/dev/null 2>&1 && return 0
  pgrep -f 'startplasma|startplasmamobile' >/dev/null 2>&1 && return 0
  return 1
}

log "request (XDG_SESSION_ID=${XDG_SESSION_ID:-} DESKTOP=${DESKTOP_SESSION:-})"

if command -v qdbus6 >/dev/null 2>&1; then
  qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout 2>/dev/null || true
elif command -v qdbus >/dev/null 2>&1; then
  qdbus org.kde.Shutdown /Shutdown org.kde.Shutdown.logout 2>/dev/null || true
fi

for _ in 1 2 3 4 5 6 8 10; do
  plasma_still_running || { log "Plasma exited after KDE logout"; exit 0; }
  sleep 0.5
done

if [[ -n "${XDG_SESSION_ID:-}" ]]; then
  log "KDE still up — loginctl terminate-session ${XDG_SESSION_ID}"
  loginctl terminate-session "$XDG_SESSION_ID" 2>/dev/null || true
  sleep 1
fi

if plasma_still_running; then
  log "hard fallback — loginctl terminate-user ${USER:-steam}"
  loginctl terminate-user "${USER:-steam}" 2>/dev/null || true
fi
