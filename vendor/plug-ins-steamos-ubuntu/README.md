# Plugins Decky incluidos en SteamOS-Ubuntu

## Empaquetado en imagen

| Plugin | Origen | En imagen |
|--------|--------|-----------|
| `power-managment/` | Perfiles SM8550 | `/usr/share/steamos-ubuntu/decky-plugins/` → sync a `~/homebrew/plugins/` tras instalar Decky |
| `color-leds/` | RGB LED SM8550 | idem |
| `decky-lsfg-vk/` | LSFG framegen | Copia completa a `/home/steam/` (`~/lsfg`, `~/.config/lsfg-vk`, `~/.local/…`) + plugin en bundle |

Tras instalar Decky, `sync-decky-bundled-plugins.sh` instala los tres plugins en `~/homebrew/plugins/`.

## Antes de crear la imagen

Construir frontends TypeScript (requiere Node 18+ / pnpm):

```bash
cd vendor/plug-ins-steamos-ubuntu/power-managment && ./build.sh
cd vendor/plug-ins-steamos-ubuntu/color-leds && ./build.sh
```

`decky-lsfg-vk` ya incluye `dist/index.js` precompilado.

## Añadir otro plugin estándar

1. Crear `vendor/plug-ins-steamos-ubuntu/<nombre>/` con `plugin.json`, `main.py`, `dist/index.js` en la raíz
2. `./build.sh` si tiene frontend
3. Rebuild de imagen (`finalize` ejecuta `stage-decky-plugins-into-rootfs.sh`)

## LSFG-VK (layout especial)

`decky-lsfg-vk/` no es un plugin plano: es un snapshot de home de `steam`.  
`stage-decky-lsfg-vk-home-into-rootfs.sh` copia su contenido a `/home/steam/` durante `finalize`.

Flujo en dispositivo: instalar conversor (Box64/FEX) → instalar Decky → plugins bundled + LSFG listos.
