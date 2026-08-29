# GYRO-FIX (`vendor/gyro-desktop`)

Desktop tools for AYN Odin 2 / Thor on SteamOS-Ubuntu:

1. **Plasma:** native **AYN** pad only (InputPlumber stopped — no virtual Steam Deck)
2. **Optional DSU** (`127.0.0.1:26760`) for Azahar / Cemu / Eden — off by default
3. **Settings UI:** sensitivity, invert axes, profiles (Gtk3)
4. **Gaming Mode:** single `deck-uhid` + IMU (`passthrough: false`) via `gyro-desktop-gamescope`

## Install / repair

```bash
sudo ./vendor/gyro-desktop/install.sh
# If Gaming Mode still shows 2 pads:
sudo gyro-desktop-gamescope
```

## Why two pads broke gyro

Desktop used `passthrough: true` (Deck + raw AYN). If Gaming Mode never ran
`gyro-desktop-gamescope`, Steam kept both. Fix: desktop stops IP; GM installs
IMU YAML with `passthrough: false`.
