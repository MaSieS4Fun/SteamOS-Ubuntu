# masi-motion — Qualcomm Sensor Core → uinput IMU for Steam Gaming Mode

Minimal userspace for **InputPlumber `deck-uhid`**: one virtual Steam Deck controller with AYN button layout **and** gyro from the built-in IMU.

## Odin 2 axis frame (locked)

`odin2-dsu-v9` in `qcom-motion`: Steam look frame **`(X, -Z, -Y)`** for accel and gyro (right-handed; do not flip yaw alone). Bake and live install use this automatically. `sync-from-giroscopio.sh` refuses to overwrite it without `--force`.

## Architecture

```
rsinput gamepad ──┐
                  ├── InputPlumber (composite) ──► deck-uhid ──► Steam
qcom-motion IMU ──┘     imu_generic + ayn_mcu
```

- **No** second virtual gamepad (`qcom-deck-pad`, `qcom-sdl-pad` removed from this path).
- **No** InputPlumber mask in Gaming Mode — `gamescope-session` stays clean.
- DSU server on `:26760` still runs (emulators); Steam uses evdev IMU via InputPlumber.

## Install

On the Odin 2 / Thor (after kernel + firmware from `vendor/kernel`):

```bash
cd /path/to/SteamOS-Ubuntu
sudo ./scripts/install-masi-motion.sh
```

Or motion only:

```bash
sudo ./vendor/masi-motion/install.sh
sudo ./scripts/install-inputplumber.sh
```

**Image bake:** `finalize-handheld-rootfs.sh` runs `install.sh --rootfs` and installs the gamepad+IMU composite by default.

First install needs network (builds hexagonrpcd + libssc from git). Sources sync automatically from `../giroscopio-mal-aolicado/vendor/giroscopio` if missing (blocked when v9 is already present).

## Verify

```bash
grep -l 'Sunshine gamepad (virtual) motion sensors' /sys/class/input/event*/device/name
journalctl -u qcom-motion -n 20
inputplumber devices list   # IMU source + deck-uhid target
```

In Steam → Settings → Controller → test gyro (Portal).

## Plan B

If `deck-uhid` does not expose IMU in Steam, switch target to `ds5` in `02-ayn-controller.yaml` (DualSense emulation with gyro). Try deck first.

## InputPlumber virtual IMU name

InputPlumber ignores virtual uinput devices unless they are on an internal whitelist. `qcom-motion` exports the IMU as `Sunshine gamepad (virtual) motion sensors` (already whitelisted upstream) and matches it via `phys_path: qcom-motion/input0`.

## Files

| Path | Role |
|------|------|
| `src/qcom-motion/` | SSC bridge + uinput (Sunshine whitelist name) |
| `packaging/bin/masi-qcom-sensors` | FastRPC SensorsPD/RootPD |
| `systemd/*.service` | Boot order: qrtr → sensors → motion |
| `../system_files/etc/inputplumber/` | Composite device + maps (IMU default) |

See also: `vendor/kernel/docs/GYRO.md`
