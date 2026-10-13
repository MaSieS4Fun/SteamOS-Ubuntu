# Plugins Decky incluidos en SteamOS-Ubuntu

## Empaquetado en imagen

| Plugin | Upstream | In image |
|--------|----------|----------|
| Panel de Control | [Hooandee/panel-de-control](https://github.com/Hooandee/panel-de-control) v0.67.1 (`upstream/Panel.de.Control.zip`) | `/usr/share/steamos-ubuntu/decky-plugins/Panel de Control/` → `~/homebrew/plugins/` after Decky install |
| Colores | [Hooandee/decky-colores](https://github.com/Hooandee/decky-colores) v0.31.0 (`upstream/Colores.zip`) | same |
| `decky-lsfg-vk/` | LSFG framegen (PancakeTAS / xXJSONDeruloXx) | Full snapshot under `/home/steam/` + plugin bundle |

The in-tree `power-managment/` (SM8550-Power) and `color-leds/` (SM8550-LED) trees are not installed.

After Decky install, `sync-decky-bundled-plugins.sh` installs Panel de Control, Colores, and LSFG into `~/homebrew/plugins/`, and removes SM8550-Power / SM8550-LED if they are already there.

Full upstream credits: [`CREDITS.md`](../../CREDITS.md) at the repository root.

## Antes de crear la imagen

Panel de Control y Colores van en `upstream/` como zip de la release de Hooandee. No hace falta compilarlos.

`decky-lsfg-vk` ya incluye `dist/index.js` precompilado.

## Añadir otro plugin estándar

1. Crear `vendor/plug-ins-steamos-ubuntu/<nombre>/` con `plugin.json`, `main.py`, `dist/index.js` en la raíz
2. `./build.sh` si tiene frontend
3. Rebuild de imagen (`finalize` ejecuta `stage-decky-plugins-into-rootfs.sh`)

## LSFG-VK (layout especial)

`decky-lsfg-vk/` no es un plugin plano: es un snapshot de home de `steam`.  
`stage-decky-lsfg-vk-home-into-rootfs.sh` copia su contenido a `/home/steam/` durante `finalize`.

Flujo en dispositivo: instalar conversor (Box64/FEX) → instalar Decky → plugins bundled + LSFG listos.
