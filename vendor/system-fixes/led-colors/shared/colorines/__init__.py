"""Colorines — RGB LED control for AYN / sm8xxx handhelds."""

from .leds import (
    LED_ZONES,
    PRESET_ORDER,
    PRESETS,
    apply_preset,
    available,
    cycle,
    discover_zones,
    get_state,
    set_color,
    set_off,
    set_on,
    toggle,
)

__all__ = [
    "LED_ZONES",
    "PRESET_ORDER",
    "PRESETS",
    "apply_preset",
    "available",
    "cycle",
    "discover_zones",
    "get_state",
    "set_color",
    "set_off",
    "set_on",
    "toggle",
]
