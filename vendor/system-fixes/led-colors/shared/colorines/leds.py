"""Sysfs RGB LED backend for pwm-leds-multicolor (AYN Odin 2 / sm8550 family)."""

from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path
from typing import Any

LEDS_ROOT = Path("/sys/class/leds")

LED_ZONES = (
    "left-joystick",
    "left-side",
    "right-joystick",
    "right-side",
)

_ZONE_ALIASES = {
    "left-joystick": ("left_joystick",),
    "left-side": ("left_side",),
    "right-joystick": ("right_joystick",),
    "right-side": ("right_side",),
}

# Order used for Plasma Mobile cycle and "first colour"
PRESET_ORDER = (
    "red",
    "green",
    "blue",
    "cyan",
    "magenta",
    "yellow",
    "orange",
    "purple",
    "white",
    "warm",
)

PRESETS: dict[str, tuple[int, int, int]] = {
    "red": (255, 0, 0),
    "green": (0, 255, 0),
    "blue": (0, 0, 255),
    "cyan": (0, 220, 255),
    "magenta": (255, 0, 200),
    "yellow": (255, 200, 0),
    "orange": (255, 100, 0),
    "purple": (160, 0, 255),
    "white": (255, 255, 255),
    "warm": (255, 160, 60),
}

PRESET_LABELS: dict[str, str] = {
    "red": "Red",
    "green": "Green",
    "blue": "Blue",
    "cyan": "Cyan",
    "magenta": "Magenta",
    "yellow": "Yellow",
    "orange": "Orange",
    "purple": "Purple",
    "white": "White",
    "warm": "Warm",
}

STATE_DIR = Path(os.environ.get("COLORINES_STATE_DIR", "/var/lib/colorines"))
STATE_FILE = STATE_DIR / "state.json"
ARMBIAN_LEDS_CONF = Path("/etc/armbian-leds.conf")


def _ensure_sysfs_writable() -> None:
    """Remount /sys rw when needed (root)."""
    try:
        test = next(
            (
                LEDS_ROOT / z / "brightness"
                for z in LED_ZONES
                if (LEDS_ROOT / z / "brightness").exists()
            ),
            None,
        )
        if test is None:
            return
        cur = test.read_text()
        test.write_text(cur)
        return
    except OSError as exc:
        if getattr(exc, "errno", None) not in (30, 13):
            return
    if os.geteuid() != 0:
        return
    try:
        subprocess.run(
            ["mount", "-o", "remount,rw", "/sys"],
            check=False,
            capture_output=True,
        )
    except OSError:
        pass


def _zone_dir(name: str) -> Path | None:
    direct = LEDS_ROOT / name
    if (direct / "brightness").exists():
        return direct
    for alias in _ZONE_ALIASES.get(name, ()):
        alt = LEDS_ROOT / alias
        if (alt / "brightness").exists():
            return alt
    return None


def discover_zones() -> list[str]:
    return [name for name in LED_ZONES if _zone_dir(name) is not None]


def available() -> bool:
    return bool(discover_zones())


def _read_int(path: Path, default: int = 0) -> int:
    try:
        return int(path.read_text().strip().split()[0])
    except (OSError, ValueError, IndexError):
        return default


def _read_rgb(path: Path) -> tuple[int, int, int]:
    try:
        parts = path.read_text().strip().split()
        if len(parts) >= 3:
            return int(parts[0]), int(parts[1]), int(parts[2])
    except (OSError, ValueError):
        pass
    return 0, 0, 0


def _write_text(path: Path, value: str) -> None:
    path.write_text(value if value.endswith("\n") else value + "\n")


def _hex_of(r: int, g: int, b: int) -> str:
    return f"#{r:02x}{g:02x}{b:02x}"


def preset_catalog() -> list[dict[str, Any]]:
    out = []
    for name in PRESET_ORDER:
        r, g, b = PRESETS[name]
        out.append(
            {
                "id": name,
                "label": PRESET_LABELS.get(name, name),
                "r": r,
                "g": g,
                "b": b,
                "hex": _hex_of(r, g, b),
            }
        )
    return out


def get_zone(name: str) -> dict[str, Any] | None:
    zdir = _zone_dir(name)
    if zdir is None:
        return None
    brightness = _read_int(zdir / "brightness")
    max_b = _read_int(zdir / "max_brightness", 255)
    r = g = b = 0
    multi = zdir / "multi_intensity"
    has_rgb = multi.exists()
    if has_rgb:
        r, g, b = _read_rgb(multi)
    on = brightness > 0 and (not has_rgb or (r + g + b) > 0)
    return {
        "name": name,
        "path": str(zdir),
        "on": on,
        "brightness": brightness,
        "max_brightness": max_b,
        "r": r,
        "g": g,
        "b": b,
        "rgb": has_rgb,
        "hex": _hex_of(r, g, b),
    }


def _match_preset(r: int, g: int, b: int) -> str | None:
    for name, (pr, pg, pb) in PRESETS.items():
        if (pr, pg, pb) == (r, g, b):
            return name
    return None


def get_state(zones: list[str] | None = None) -> dict[str, Any]:
    names = zones or discover_zones()
    zone_data = []
    for name in names:
        info = get_zone(name)
        if info:
            zone_data.append(info)
    any_on = any(z["on"] for z in zone_data)
    rep = next((z for z in zone_data if z["on"]), zone_data[0] if zone_data else None)
    saved = load_saved()
    r = rep["r"] if rep else 0
    g = rep["g"] if rep else 0
    b = rep["b"] if rep else 0
    preset = saved.get("preset") if isinstance(saved.get("preset"), str) else None
    if any_on:
        preset = _match_preset(r, g, b) or preset
    return {
        "available": bool(zone_data),
        "on": any_on,
        "zones": zone_data,
        "r": r,
        "g": g,
        "b": b,
        "brightness": rep["brightness"] if rep else 0,
        "hex": rep["hex"] if rep else "#000000",
        "preset": preset,
        "preset_label": PRESET_LABELS.get(preset or "", ""),
        "saved": saved,
        "presets": preset_catalog(),
    }


def set_color(
    r: int,
    g: int,
    b: int,
    brightness: int | None = None,
    zones: list[str] | None = None,
    persist: bool = True,
    preset: str | None = None,
) -> dict[str, Any]:
    _ensure_sysfs_writable()
    r = max(0, min(255, int(r)))
    g = max(0, min(255, int(g)))
    b = max(0, min(255, int(b)))
    if brightness is None:
        brightness = 255 if (r + g + b) > 0 else 0
    brightness = max(0, min(255, int(brightness)))

    names = zones or discover_zones()
    if not names:
        raise RuntimeError("No LED zones found under /sys/class/leds")

    errors: list[str] = []
    for name in names:
        zdir = _zone_dir(name)
        if zdir is None:
            errors.append(f"missing:{name}")
            continue
        try:
            trigger = zdir / "trigger"
            if trigger.exists():
                try:
                    _write_text(trigger, "none")
                except OSError:
                    pass
            multi = zdir / "multi_intensity"
            if multi.exists():
                _write_text(multi, f"{r} {g} {b}")
            _write_text(zdir / "brightness", str(0 if (r + g + b) == 0 else brightness))
        except OSError as exc:
            errors.append(f"{name}:{exc}")

    if errors and all(e.startswith("missing:") is False for e in errors):
        # If every zone failed to write, surface a clear error
        if len(errors) >= len(names):
            raise RuntimeError(
                "Cannot write LED sysfs (need root/sudo or remount /sys rw). "
                + "; ".join(errors[:3])
            )

    if persist:
        if preset is None:
            preset = _match_preset(r, g, b)
        save_state(
            r,
            g,
            b,
            brightness,
            on=(r + g + b) > 0 and brightness > 0,
            preset=preset,
        )
        update_armbian_leds_conf(r, g, b, brightness, names)

    state = get_state(names)
    if errors:
        state["errors"] = errors
    return state


def set_off(zones: list[str] | None = None, persist: bool = True) -> dict[str, Any]:
    saved = load_saved()
    r = int(saved.get("r", 0) or 0)
    g = int(saved.get("g", 0) or 0)
    b = int(saved.get("b", 0) or 0)
    brightness = int(saved.get("brightness", 255) or 255)
    preset = saved.get("preset") if isinstance(saved.get("preset"), str) else None
    _ensure_sysfs_writable()
    names = zones or discover_zones()
    errors: list[str] = []
    for name in names:
        zdir = _zone_dir(name)
        if zdir is None:
            continue
        try:
            multi = zdir / "multi_intensity"
            if multi.exists():
                _write_text(multi, "0 0 0")
            _write_text(zdir / "brightness", "0")
        except OSError as exc:
            errors.append(f"{name}:{exc}")
    if errors and len(errors) >= max(1, len(names)):
        raise RuntimeError(
            "Cannot write LED sysfs (need root/sudo or remount /sys rw). "
            + "; ".join(errors[:3])
        )
    if persist:
        # Keep last colour + preset so On restores them
        if r + g + b == 0 and preset in PRESETS:
            r, g, b = PRESETS[preset]
        elif r + g + b == 0:
            r, g, b = PRESETS[PRESET_ORDER[0]]
            preset = PRESET_ORDER[0]
        save_state(r, g, b, brightness, on=False, preset=preset)
        update_armbian_leds_conf(0, 0, 0, 0, names)
    return get_state(names)


def set_on(zones: list[str] | None = None, persist: bool = True) -> dict[str, Any]:
    """Turn on: first time = colour 1; later = last colour before Off."""
    saved = load_saved()
    preset = saved.get("preset") if isinstance(saved.get("preset"), str) else None
    if preset in PRESETS:
        return apply_preset(preset, zones=zones)
    r = int(saved.get("r", 0) or 0)
    g = int(saved.get("g", 0) or 0)
    b = int(saved.get("b", 0) or 0)
    brightness = int(saved.get("brightness", 255) or 255)
    if r + g + b == 0:
        return apply_preset(PRESET_ORDER[0], zones=zones)
    return set_color(r, g, b, brightness=brightness, zones=zones, persist=persist)


def toggle(zones: list[str] | None = None) -> dict[str, Any]:
    if get_state(zones)["on"]:
        return set_off(zones)
    return set_on(zones)


def apply_preset(
    name: str, brightness: int = 255, zones: list[str] | None = None
) -> dict[str, Any]:
    key = name.strip().lower()
    if key in ("off", "none"):
        return set_off(zones)
    if key not in PRESETS:
        raise ValueError(f"Unknown preset: {name}")
    r, g, b = PRESETS[key]
    return set_color(r, g, b, brightness=brightness, zones=zones, preset=key)


def cycle(zones: list[str] | None = None) -> dict[str, Any]:
    """Plasma Mobile: Off → colour1 → … → colourN → Off → …"""
    state = get_state(zones)
    saved = load_saved()
    if not state["on"]:
        return apply_preset(PRESET_ORDER[0], zones=zones)

    cur = saved.get("preset") if isinstance(saved.get("preset"), str) else None
    if cur not in PRESET_ORDER:
        cur = _match_preset(state["r"], state["g"], state["b"])
    if cur not in PRESET_ORDER:
        return apply_preset(PRESET_ORDER[0], zones=zones)

    nxt = PRESET_ORDER.index(cur) + 1
    if nxt >= len(PRESET_ORDER):
        return set_off(zones)
    return apply_preset(PRESET_ORDER[nxt], zones=zones)


def load_saved() -> dict[str, Any]:
    for path in (STATE_FILE, Path.home() / ".local/state/colorines/state.json"):
        try:
            if path.is_file():
                data = json.loads(path.read_text())
                if isinstance(data, dict):
                    return data
        except (OSError, json.JSONDecodeError):
            continue
    return {
        "r": 0,
        "g": 0,
        "b": 0,
        "brightness": 255,
        "on": False,
        "preset": None,
    }


def save_state(
    r: int,
    g: int,
    b: int,
    brightness: int,
    on: bool,
    preset: str | None = None,
) -> None:
    prev: dict[str, Any] = {}
    try:
        if STATE_FILE.is_file():
            prev = json.loads(STATE_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        pass

    payload: dict[str, Any] = {
        "r": r,
        "g": g,
        "b": b,
        "brightness": brightness,
        "on": on,
    }
    if preset is not None:
        payload["preset"] = preset
    elif isinstance(prev.get("preset"), str):
        payload["preset"] = prev["preset"]

    written = False
    for directory in (STATE_DIR, Path.home() / ".local/state/colorines"):
        try:
            directory.mkdir(parents=True, exist_ok=True)
            (directory / "state.json").write_text(json.dumps(payload, indent=2) + "\n")
            written = True
            if directory == STATE_DIR:
                break
        except OSError:
            continue
    if not written:
        pass


def update_armbian_leds_conf(
    r: int,
    g: int,
    b: int,
    brightness: int,
    zones: list[str],
) -> None:
    if not ARMBIAN_LEDS_CONF.is_file() or not os.access(ARMBIAN_LEDS_CONF, os.W_OK):
        return
    try:
        text = ARMBIAN_LEDS_CONF.read_text()
    except OSError:
        return

    for name in zones:
        zdir = _zone_dir(name)
        if zdir is None:
            continue
        section = f"[{zdir}]"
        block = (
            f"{section}\n"
            f"trigger=none\n"
            f"brightness={brightness}\n"
            f"multi_intensity={r} {g} {b}\n"
        )
        pattern = re.compile(
            rf"^{re.escape(section)}\n(?:(?!\[).*\n?)*",
            re.MULTILINE,
        )
        if pattern.search(text):
            text = pattern.sub(block + "\n", text, count=1)
        else:
            if not text.endswith("\n"):
                text += "\n"
            text += "\n" + block

    try:
        ARMBIAN_LEDS_CONF.write_text(text)
    except OSError:
        pass
