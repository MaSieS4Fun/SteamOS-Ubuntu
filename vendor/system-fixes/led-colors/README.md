# Led Colors — gamepad RGB LEDs (sm8xxx)

Control gamepad LED colors from **three places**, same backend:

| Place | What | ID / path |
|-------|------|-----------|
| KDE Plasma | Tray applet | `org.masi.colorines` |
| Plasma Mobile | Quick setting (2nd tile) | `org.masi.quicksetting.colorines` |
| Decky (Steam / GameScope) | Plugin (root Decky) | `~/homebrew/plugins/colorines` |

Expected hardware (AYN Odin 2 / sm8550-class):

```
/sys/class/leds/left-joystick
/sys/class/leds/left-side
/sys/class/leds/right-joystick
/sys/class/leds/right-side
```

Each zone: `multi_intensity` = `R G B`, `brightness` = 0–255 (`pwm-leds-multicolor`).

Compatible with the Batocera Custom Qualcomm / `batoled` sysfs RGB approach.  
See [`CREDITS.md`](../../../CREDITS.md) at the repository root.

## Install

```bash
cd led-colors
cd decky-plugin && npm install && npm run build && cd ..   # if dist/ missing
sudo ./install.sh
```

## CLI

```bash
colorines on | off | cycle
colorines preset red
colorines get
```

## Persistence

- `/var/lib/colorines/state.json`
- May update `/etc/armbian-leds.conf` for Armbian LED restore on boot

## License

GPL-2.0-or-later (aligned with MaSi UI pieces) unless noted otherwise.
