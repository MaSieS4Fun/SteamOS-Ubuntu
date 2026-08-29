# SteamOS-Ubuntu apt repository

Monorepo apt channel for ARM Manager apps, gaming tools, and the MaSi kernel updater.

## Private repo vs public apt

| Component | Repo privado | Repo público |
|-----------|--------------|--------------|
| `steamos-ubuntu.list` en la imagen | ✅ Se puede instalar | ✅ |
| `steamos-ubuntu.gpg` (clave pública) | ✅ Se puede instalar | ✅ |
| `apt update` en consolas de usuarios | ❌ Falla (GitHub Pages no accesible) | ✅ |
| GitHub Actions (build .deb) | ✅ | ✅ |

**Respuesta corta:** el `.list` y el `.gpg` **no requieren** repo público para *instalarlos* en la imagen.  
**Sí requieren** repo público (y GitHub Pages activo) para que `apt update` **descargue** paquetes en dispositivos de usuarios.

Hasta el día del vídeo:

1. Repo **privado** en GitHub.
2. Imagen con apps **embebidas** (scripts actuales) + source list preparado.
3. `apt update` puede mostrar error de red — **normal** hasta el launch.
4. Día del launch: repo → **público**, publicar Release + Pages → `apt upgrade` funciona.

## Paquetes

| Paquete | Contenido |
|---------|-----------|
| `mesa-easy-manager` | MESA Easy Manager |
| `easy-ufs-install` | Easy UFS Installer |
| `proton-arm-easy-manager` | Proton ARM Easy Manager |
| `no-steam-games` | ARM Non-Steam Games |
| `gyro-desktop` | GYRO-FIX |
| `masi-kernel-edge-sm8550` | `masi-kernel-update` + bundle opcional |
| `steamos-ubuntu-apps` | Metapaquete (todos los anteriores) |

Versiones en `packaging/apt/channel.conf`.

## Build local

```bash
# 0) Kernel kbase must exist (embedded in the .deb — apt upgrade flashes it)
cd vendor/kernel && KERNEL_VER=7.2.2 ./make.sh
cd ../..

# 1) Clave de firma (una vez)
./scripts/apt-generate-signing-key.sh

# 2) Construir .deb (BUILD_KERNEL_DEB=1 by default)
./scripts/build-debs.sh

# 3) Índice apt
APT_SIGN=1 ./scripts/generate-apt-repo.sh

# 4) Probar en el dispositivo (repo local)
sudo cp packaging/apt/steamos-ubuntu.gpg /usr/share/keyrings/
echo "deb [signed-by=/usr/share/keyrings/steamos-ubuntu.gpg arch=arm64] file:$(pwd)/output/apt-repo ./" | \
  sudo tee /etc/apt/sources.list.d/steamos-ubuntu-local.list
sudo apt update
sudo apt install steamos-ubuntu-apps
```

## Imagen (bake)

`finalize-handheld-rootfs.sh` llama a:

1. `install-steamos-ubuntu-apt-source.sh` — `steamos-ubuntu.list` + GPG
2. `install-steamos-ubuntu-apt-packages.sh` — instala `.deb` con **`apt-get install /path/*.deb`** (no `dpkg -i` suelto)

Usar **apt** en el bake registra el origen de cada paquete; en el dispositivo basta:

```bash
sudo apt update && sudo apt upgrade
```

`system_files/etc/apt/apt.conf.d/90steamos-flat-repo` optimiza el repo plano en GitHub Pages.

Durante el bake, `STEAMOS_APT_BAKE=1` hace que el postinst del kernel **no reflashee** (el kernel ya está en la imagen); solo registra dpkg.

## CI / GitHub Pages

Workflow `.github/workflows/release-apt.yml`:

- Tag `v*` o manual → build debs → apt repo → deploy a `gh-pages` en `/apt/`
- Secret requerido para firmar: `APT_GPG_PRIVATE_KEY` (export de `packaging/apt/.gnupg`)

URL en dispositivos:

```text
https://<owner>.github.io/SteamOS-Ubuntu/apt
```

## Usuario final (tras launch público)

```bash
sudo apt update
sudo apt upgrade
# o solo apps MaSi:
sudo apt install steamos-ubuntu-apps
```

Kernel tras upgrade del paquete `masi-kernel-edge-sm8550`:

```bash
sudo apt update && sudo apt upgrade   # postinst flashea el kernel embebido
sudo reboot
uname -r   # p. ej. 7.2.2-edge-sm8550
```
