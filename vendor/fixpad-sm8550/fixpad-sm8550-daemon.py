#!/usr/bin/env python3
"""SM8550 fixpad daemon — stick range + Plasma idle wake (desktop only).

1) Rescale rsinput stick ABS range (default ±740) on AYN built-in gamepads.
2) On KDE Plasma desktop, poke idle while the pad moves so the screen does not dim.
   Skipped in Gaming Mode (gamescope / STEAMOS_SESSION).
"""

from __future__ import annotations

import fcntl
import os
import struct
import sys
import time
from select import select

try:
    from evdev import InputDevice, ecodes, list_devices
except ImportError:
    print("fixpad-sm8550: install python3-evdev", file=sys.stderr)
    sys.exit(1)

try:
    import dbus
except ImportError:
    dbus = None  # type: ignore[assignment]

GAMEPAD_NAMES = frozenset(
    {
        "AYN Odin2 Gamepad",
        "AYN Thor Gamepad",
        "RSInput Gamepad",
    }
)
SKIP_SUBSTR = ("Motion", "Touch", "Headset", "mapped", "Mouse", "Keyboard")
PREF_PHYS = "rsinput-gamepad"

DEFAULT_STOCK = int(os.environ.get("FIXPAD_STOCK", "1408"))
TARGET_RANGE = int(os.environ.get("FIXPAD_TARGET", "740"))
STICK_DEADZONE = int(os.environ.get("FIXPAD_WAKE_DEADZONE", "120"))
TRIGGER_PRESS = int(os.environ.get("FIXPAD_WAKE_TRIGGER", "80"))
THROTTLE_S = float(os.environ.get("FIXPAD_WAKE_THROTTLE", "2.0"))
REAPPLY_S = float(os.environ.get("FIXPAD_REAPPLY_INTERVAL", "30.0"))

STICK_AXES = {ecodes.ABS_X, ecodes.ABS_Y, ecodes.ABS_RX, ecodes.ABS_RY}
TRIGGER_AXES = {ecodes.ABS_Z, ecodes.ABS_RZ}
STICK_ABS_CODES = (0, 1, 3, 4)

ABSINFO = "iiiiii"
ABSINFO_SIZE = struct.calcsize(ABSINFO)


def _ioc(dir_: int, nr: int, size: int) -> int:
    return (dir_ << 30) | (ord("E") << 8) | nr | (size << 16)


def eviocgabs(code: int) -> int:
    return _ioc(2, 0x40 + code, ABSINFO_SIZE)


def eviocsabs(code: int) -> int:
    return _ioc(1, 0xC0 + code, ABSINFO_SIZE)


def is_gamepad(name: str) -> bool:
    if name in GAMEPAD_NAMES:
        return True
    if "Gamepad" in name and "AYN" in name:
        return not any(part in name for part in SKIP_SUBSTR)
    if name == "RSInput Gamepad":
        return True
    return False


def is_gaming_session() -> bool:
    if os.environ.get("STEAMOS_SESSION") == "1":
        return True
    desktop = (os.environ.get("XDG_CURRENT_DESKTOP") or "").lower()
    if "gamescope" in desktop:
        return True
    session = (os.environ.get("DESKTOP_SESSION") or "").lower()
    return "gamescope" in session


def open_gamepad() -> InputDevice | None:
    preferred: InputDevice | None = None
    fallback: InputDevice | None = None
    for path in list_devices():
        try:
            dev = InputDevice(path)
        except OSError:
            continue
        name = dev.name or ""
        if not is_gamepad(name):
            try:
                dev.close()
            except OSError:
                pass
            continue
        phys = (dev.phys or "").lower()
        if PREF_PHYS in phys and preferred is None:
            preferred = dev
        elif fallback is None:
            fallback = dev
        else:
            try:
                dev.close()
            except OSError:
                pass
    if preferred is not None:
        if fallback is not None:
            try:
                fallback.close()
            except OSError:
                pass
        return preferred
    return fallback


def read_axis_max(fd: int, code: int) -> int:
    buf = bytearray(ABSINFO_SIZE)
    fcntl.ioctl(fd, eviocgabs(code), buf)
    _value, amin, amax, _fuzz, _flat, _res = struct.unpack(ABSINFO, buf)
    return max(abs(amin), abs(amax))


def apply_stick_range(dev_path: str, target: int) -> tuple[int, int]:
    fd = os.open(dev_path, os.O_RDWR)
    stock = DEFAULT_STOCK
    try:
        stock = max(read_axis_max(fd, code) for code in STICK_ABS_CODES)
        for code in STICK_ABS_CODES:
            buf = bytearray(ABSINFO_SIZE)
            fcntl.ioctl(fd, eviocgabs(code), buf)
            value, _amin, _amax, fuzz, flat, res = struct.unpack(ABSINFO, buf)
            new = struct.pack(ABSINFO, value, -target, target, fuzz, flat, res)
            fcntl.ioctl(fd, eviocsabs(code), new)
    finally:
        os.close(fd)
    print(
        f"fixpad-sm8550: sticks ±{target} on {dev_path} (was ±{stock})",
        flush=True,
    )
    return stock, target


def meaningful(event) -> bool:
    if event.type == ecodes.EV_KEY:
        return event.value in (0, 1)
    if event.type != ecodes.EV_ABS:
        return False
    if event.code in STICK_AXES:
        return abs(event.value) >= STICK_DEADZONE
    if event.code in TRIGGER_AXES:
        return event.value >= TRIGGER_PRESS
    return event.value != 0


class IdlePoke:
    def __init__(self) -> None:
        self._bus = None
        self._last = 0.0
        self._ss = None
        self._pm = None

    def _bind(self) -> None:
        if dbus is None:
            return
        if self._bus is None:
            self._bus = dbus.SessionBus()
        if self._ss is None:
            obj = self._bus.get_object(
                "org.freedesktop.ScreenSaver",
                "/org/freedesktop/ScreenSaver",
            )
            self._ss = dbus.Interface(obj, "org.freedesktop.ScreenSaver")
        if self._pm is None:
            obj = self._bus.get_object(
                "org.kde.Solid.PowerManagement",
                "/org/kde/Solid/PowerManagement",
            )
            self._pm = dbus.Interface(obj, "org.kde.Solid.PowerManagement")

    def poke(self) -> None:
        if dbus is None or is_gaming_session():
            return
        now = time.monotonic()
        if now - self._last < THROTTLE_S:
            return
        self._last = now
        try:
            self._bind()
            if self._ss is not None:
                self._ss.SimulateUserActivity()
            if self._pm is not None:
                self._pm.wakeup()
        except Exception as exc:  # noqa: BLE001 — dbus errors vary
            self._ss = None
            self._pm = None
            print(f"fixpad-sm8550: idle poke: {exc}", flush=True)


def main() -> int:
    target = TARGET_RANGE
    if target < 64 or target > 32767:
        print(f"fixpad-sm8550: bad FIXPAD_TARGET={target}", file=sys.stderr)
        return 1

    gaming = is_gaming_session()
    poke = IdlePoke()
    print(
        f"fixpad-sm8550: target=±{target} gaming={gaming} "
        f"wake={'off' if gaming else 'on'} throttle={THROTTLE_S}s",
        flush=True,
    )

    last_reapply = 0.0
    while True:
        dev = open_gamepad()
        if dev is None:
            time.sleep(1.0)
            continue

        try:
            apply_stick_range(dev.path, target)
            last_reapply = time.monotonic()
        except OSError as exc:
            print(f"fixpad-sm8550: abs set failed: {exc}", flush=True)

        print(f"fixpad-sm8550: listening on {dev.path} ({dev.name})", flush=True)
        try:
            while True:
                timeout = 5.0
                if time.monotonic() - last_reapply >= REAPPLY_S:
                    timeout = 0.1
                r, _, _ = select([dev.fd], [], [], timeout)
                if time.monotonic() - last_reapply >= REAPPLY_S:
                    try:
                        apply_stick_range(dev.path, target)
                    except OSError:
                        pass
                    last_reapply = time.monotonic()
                if not r:
                    if not os.path.exists(dev.path):
                        break
                    continue
                for event in dev.read():
                    if meaningful(event):
                        poke.poke()
        except OSError as exc:
            print(f"fixpad-sm8550: device lost: {exc}", flush=True)
        finally:
            try:
                dev.close()
            except OSError:
                pass
        time.sleep(0.5)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(0)
