# fixpad-sm8550

Correcciones del mando integrado AYN en handhelds **Qualcomm SM8550** (Odin 2, Thor, Portal, Retroid Pocket 6 con rsinput).

## Problemas que soluciona

| Problema | Modo | Solución |
|----------|------|----------|
| Cámara / personaje se mueve lento (sticks no usan todo el radio) | Gaming + Desktop | ABS sticks **±1407/1408 → ±740** en el nodo rsinput |
| La pantalla se atenúa por inactividad aunque muevas el mando | Solo Desktop (Plasma) | Daemon resetea idle de PowerDevil vía D-Bus |

## Imagen nueva (bake)

**Sí — queda aplicado de fábrica.** `scripts/finalize-handheld-rootfs.sh` ejecuta `vendor/fixpad-sm8550/install.sh`:

- **Gaming Mode:** `gamescope-session` y `gyro-desktop-gamescope` llaman `fixpad-sm8550 apply` al arrancar.
- **Desktop:** servicio de usuario `fixpad-sm8550.service` + autostart Plasma + `gyro-desktop-plasma`.
- Dependencias: `python3-evdev`, `python3-dbus` (en `packages/steam`).

No hace falta instalar nada manualmente en una imagen recién creada.

## Probar en sistema actual (sin rebake)

```bash
sudo apt install python3-evdev python3-dbus
cd ~/Desktop/SteamOS-Ubuntu/vendor/fixpad-sm8550
chmod +x fixpad-sm8550 fixpad-sm8550-daemon.py install.sh
sudo ./install.sh
```

## Comandos

```bash
fixpad-sm8550 status      # rango actual de sticks
fixpad-sm8550 apply       # aplicar ±740 una vez
fixpad-sm8550 restore     # volver a stock ±1408
fixpad-sm8550 install      # manual: daemon de usuario (solo si no viene de imagen)
fixpad-sm8550 uninstall
```

## Paquete apt (futuro)

Cuando se publique el canal apt:

```bash
sudo apt install fixpad-sm8550
```

## Archivos en imagen

| Ruta | Rol |
|------|-----|
| `/usr/bin/fixpad-sm8550` | CLI |
| `/usr/libexec/steamos-ubuntu/fixpad-sm8550-daemon.py` | Daemon desktop |
| `/usr/lib/systemd/user/fixpad-sm8550.service` | Unidad systemd usuario |
| `/etc/xdg/autostart/fixpad-sm8550-plasma.desktop` | Apply al entrar en Plasma |

Basado en `vendor/system-fixes/fixpad/`, integrado en el bake del OS.
