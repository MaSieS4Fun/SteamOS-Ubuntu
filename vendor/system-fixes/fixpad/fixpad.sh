#!/usr/bin/env bash
# fixpad.sh — AYN Odin 2: sticks + pantalla al jugar
#
# Uso:
#   ./fixpad.sh              # instala y aplica todo (±740)
#   ./fixpad.sh 700          # mismo, con otro rango de sticks
#   ./fixpad.sh restore      # sticks a ±1408 (stock) y deja el wake
#   ./fixpad.sh uninstall    # quita el servicio instalado
#
# Tras ejecutarlo puedes borrar esta carpeta: lo permanente vive en
#   ~/.local/bin/odin2-gamepad-wake
#   ~/.config/systemd/user/odin2-gamepad-wake.service

set -euo pipefail

STOCK=1408
CMD="${1:-740}"
GAMEPAD_NAME="AYN Odin2 Gamepad"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DAEMON="$HERE/gamepad-wake.py"
INSTALL_BIN="${XDG_BIN_HOME:-$HOME/.local/bin}/odin2-gamepad-wake"
USER_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT_NAME="odin2-gamepad-wake.service"
UNIT_PATH="$USER_UNIT_DIR/$UNIT_NAME"

usage() {
  echo "Uso: $0 [rango|restore|uninstall]" >&2
  echo "  rango      instala daemon + sticks ±N (default: 740). Stock: $STOCK" >&2
  echo "  restore    sticks ±$STOCK; mantiene anti-atenuado al jugar" >&2
  echo "  uninstall  para y elimina lo instalado en ~/.local y systemd --user" >&2
}

uninstall() {
  systemctl --user disable --now "$UNIT_NAME" 2>/dev/null || true
  rm -f "$UNIT_PATH" "$USER_UNIT_DIR/default.target.wants/$UNIT_NAME"
  rm -f "$INSTALL_BIN"
  systemctl --user daemon-reload 2>/dev/null || true
  echo "Desinstalado. Sticks vuelven al stock del kernel en el próximo reboot"
  echo "(o ejecuta de nuevo fixpad.sh restore antes si quieres ±$STOCK ya)."
}

find_event() {
  local name_file name
  for name_file in /sys/class/input/event*/device/name; do
    [[ -f "$name_file" ]] || continue
    name=$(<"$name_file")
    if [[ "$name" == "$GAMEPAD_NAME" ]]; then
      echo "/dev/input/$(basename "$(dirname "$(dirname "$name_file")")")"
      return 0
    fi
  done
  return 1
}

apply_sticks_now() {
  local target="$1"
  local event
  event="$(find_event)" || {
    echo "No encuentro «$GAMEPAD_NAME» en /dev/input." >&2
    return 1
  }
  export FIXPAD_EVENT="$event"
  export FIXPAD_TARGET="$target"
  export FIXPAD_STOCK="$STOCK"
  python3 - <<'PY'
import fcntl, os, struct

EVENT = os.environ["FIXPAD_EVENT"]
TARGET = int(os.environ["FIXPAD_TARGET"])
STOCK = int(os.environ["FIXPAD_STOCK"])
ABSINFO = "iiiiii"
ABSINFO_SIZE = struct.calcsize(ABSINFO)

def _ioc(dir_, nr, size):
    return (dir_ << 30) | (ord("E") << 8) | nr | (size << 16)

def eviocgabs(code):
    return _ioc(2, 0x40 + code, ABSINFO_SIZE)

def eviocsabs(code):
    return _ioc(1, 0xc0 + code, ABSINFO_SIZE)

AXES = ((0, "leftx "), (1, "lefty "), (3, "rightx"), (4, "righty"))
fd = os.open(EVENT, os.O_RDWR)
try:
    print(f"Mando  {EVENT}")
    print(f"Rango  ±{TARGET}" + ("  (stock)" if TARGET == STOCK else f"  (stock era ±{STOCK})"))
    print()
    for code, label in AXES:
        buf = bytearray(ABSINFO_SIZE)
        fcntl.ioctl(fd, eviocgabs(code), buf)
        value, amin, amax, fuzz, flat, res = struct.unpack(ABSINFO, buf)
        before = f"±{amax}" if -amin == amax else f"{amin}..{amax}"
        fcntl.ioctl(fd, eviocsabs(code), struct.pack(ABSINFO, value, -TARGET, TARGET, fuzz, flat, res))
        buf2 = bytearray(ABSINFO_SIZE)
        fcntl.ioctl(fd, eviocgabs(code), buf2)
        _, nmin, nmax, *_ = struct.unpack(ABSINFO, buf2)
        after = f"±{nmax}" if -nmin == nmax else f"{nmin}..{nmax}"
        print(f"  {label}  {before}  →  {after}")
finally:
    os.close(fd)
PY
}

install_daemon() {
  local target="$1"
  [[ -f "$SRC_DAEMON" ]] || {
    echo "Falta $SRC_DAEMON (junto a fixpad.sh)." >&2
    exit 1
  }
  mkdir -p "$(dirname "$INSTALL_BIN")" "$USER_UNIT_DIR"
  install -m 755 "$SRC_DAEMON" "$INSTALL_BIN"

  # Copia real en systemd --user (no symlink a esta carpeta).
  cat >"$UNIT_PATH" <<EOF
[Unit]
Description=Odin2 fixpad (sticks + keep screen awake while playing)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=$INSTALL_BIN
Restart=on-failure
RestartSec=2
Environment=FIXPAD_TARGET=$target

[Install]
WantedBy=default.target
EOF

  # Por si quedó un symlink viejo hacia ~/fixpad/
  if [[ -L "$USER_UNIT_DIR/default.target.wants/$UNIT_NAME" ]]; then
    rm -f "$USER_UNIT_DIR/default.target.wants/$UNIT_NAME"
  fi

  systemctl --user daemon-reload
  systemctl --user enable --now "$UNIT_NAME"
  systemctl --user restart "$UNIT_NAME"
}

# --- main ---
if [[ "$CMD" == "-h" || "$CMD" == "--help" || "$CMD" == "help" ]]; then
  usage
  exit 0
fi

if [[ "$CMD" == "uninstall" ]]; then
  uninstall
  exit 0
fi

TARGET="$CMD"
if [[ "$TARGET" == "restore" || "$TARGET" == "stock" || "$TARGET" == "reset" ]]; then
  TARGET="$STOCK"
fi

if ! [[ "$TARGET" =~ ^[0-9]+$ ]] || (( TARGET < 64 || TARGET > 32767 )); then
  usage
  exit 1
fi

echo "== Sticks =="
apply_sticks_now "$TARGET"
echo
echo "== Servicio permanente =="
install_daemon "$TARGET"
echo
echo "Instalado en:"
echo "  $INSTALL_BIN"
echo "  $UNIT_PATH"
echo
echo "Ya puedes borrar esta carpeta ($HERE); el arreglo sigue activo"
echo "tras reiniciar. Para quitarlo: vuelve a tener fixpad.sh y ./fixpad.sh uninstall"
echo "(o: systemctl --user disable --now $UNIT_NAME && rm -f $INSTALL_BIN $UNIT_PATH)"
