# Plugins Decky incluidos en SteamOS-Ubuntu

## Empaquetado en imagen

| Plugin | Upstream basis | In image |
|--------|----------------|----------|
| `power-managment/` | [Hooandee/panel-de-control](https://github.com/Hooandee/panel-de-control) → SM8550 Power | `/usr/share/steamos-ubuntu/decky-plugins/` → `~/homebrew/plugins/` after Decky install |
| `color-leds/` | [Hooandee/decky-colores](https://github.com/Hooandee/decky-colores) → SM8550 LED | same |
| `decky-lsfg-vk/` | LSFG framegen (PancakeTAS / xXJSONDeruloXx) | Full snapshot under `/home/steam/` + plugin bundle |

After Decky install, `sync-decky-bundled-plugins.sh` installs all three plugins into `~/homebrew/plugins/`.

Full upstream credits: [`CREDITS.md`](../../CREDITS.md) at the repository root.

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
