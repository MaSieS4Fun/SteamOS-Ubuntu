#!/usr/bin/env python3
"""Odin2 fixpad daemon — installed copy; safe to delete the original fixpad/ folder.

1) Sets stick ABS range (±740 by default) so games feel responsive.
2) While you use the built-in pad, pokes Plasma idle so battery dimming
   does not kick in mid-game. Idle dimming still works when the pad is still.
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
    print("odin2-fixpad: needs python3-evdev", file=sys.stderr)
    sys.exit(1)

try:
    import dbus
except ImportError:
    print("odin2-fixpad: needs python3-dbus", file=sys.stderr)
    sys.exit(1)

DEVICE_SUBSTR = "AYN Odin2 Gamepad"
SKIP_SUBSTR = ("Motion", "Touch", "Headset", "mapped", "Mouse", "Keyboard")
PREF_PHYS = "rsinput-gamepad"

STOCK_RANGE = 1408
TARGET_RANGE = int(os.environ.get("FIXPAD_TARGET", "740"))
STICK_DEADZONE = int(os.environ.get("FIXPAD_WAKE_DEADZONE", "120"))
TRIGGER_PRESS = int(os.environ.get("FIXPAD_WAKE_TRIGGER", "80"))
THROTTLE_S = float(os.environ.get("FIXPAD_WAKE_THROTTLE", "2.0"))

STICK_AXES = {ecodes.ABS_X, ecodes.ABS_Y, ecodes.ABS_RX, ecodes.ABS_RY}
TRIGGER_AXES = {ecodes.ABS_Z, ecodes.ABS_RZ}
# ABS_X, ABS_Y, ABS_RX, ABS_RY
STICK_ABS_CODES = (0, 1, 3, 4)

ABSINFO = "iiiiii"
ABSINFO_SIZE = struct.calcsize(ABSINFO)


def _ioc(dir_: int, nr: int, size: int) -> int:
    return (dir_ << 30) | (ord("E") << 8) | nr | (size << 16)


def eviocgabs(code: int) -> int:
    return _ioc(2, 0x40 + code, ABSINFO_SIZE)


def eviocsabs(code: int) -> int:
    return _ioc(1, 0xc0 + code, ABSINFO_SIZE)


def is_gamepad(name: str) -> bool:
    if DEVICE_SUBSTR not in name:
        return False
    return not any(s in name for s in SKIP_SUBSTR)


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


def apply_stick_range(dev_path: str, target: int) -> None:
    fd = os.open(dev_path, os.O_RDWR)
    try:
        for code in STICK_ABS_CODES:
            buf = bytearray(ABSINFO_SIZE)
            fcntl.ioctl(fd, eviocgabs(code), buf)
            value, _amin, _amax, fuzz, flat, res = struct.unpack(ABSINFO, buf)
            new = struct.pack(ABSINFO, value, -target, target, fuzz, flat, res)
            fcntl.ioctl(fd, eviocsabs(code), new)
    finally:
        os.close(fd)
    print(f"odin2-fixpad: sticks ±{target} on {dev_path}", flush=True)


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
        self._bus = dbus.SessionBus()
        self._last = 0.0
        self._ss = None
        self._pm = None

    def _bind(self) -> None:
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
        now = time.monotonic()
        if now - self._last < THROTTLE_S:
            return
        self._last = now
        try:
            self._bind()
            assert self._ss is not None and self._pm is not None
            self._ss.SimulateUserActivity()
            self._pm.wakeup()
        except dbus.DBusException as exc:
            self._ss = None
            self._pm = None
            print(f"odin2-fixpad: dbus: {exc}", flush=True)


def main() -> int:
    target = TARGET_RANGE
    if target < 64 or target > 32767:
        print(f"odin2-fixpad: bad FIXPAD_TARGET={target}", file=sys.stderr)
        return 1

    poke = IdlePoke()
    print(
        f"odin2-fixpad: range=±{target} deadzone={STICK_DEADZONE} "
        f"throttle={THROTTLE_S}s",
        flush=True,
    )

    while True:
        dev = open_gamepad()
        if dev is None:
            time.sleep(1.0)
            continue

        try:
            apply_stick_range(dev.path, target)
        except OSError as exc:
            print(f"odin2-fixpad: abs set failed: {exc}", flush=True)

        print(f"odin2-fixpad: listening on {dev.path} ({dev.name})", flush=True)
        try:
            while True:
                r, _, _ = select([dev.fd], [], [], 5.0)
                if not r:
                    if not os.path.exists(dev.path):
                        break
                    continue
                for event in dev.read():
                    if meaningful(event):
                        poke.poke()
        except OSError as exc:
            print(f"odin2-fixpad: device lost: {exc}", flush=True)
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
