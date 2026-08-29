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
# 1) Clave de firma (una vez)
./scripts/apt-generate-signing-key.sh

# 2) Construir .deb
./scripts/build-debs.sh
BUILD_KERNEL_DEB=1 ./scripts/build-debs.sh   # incluir kernel kbase en el .deb

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

`finalize-handheld-rootfs.sh` llama a `install-steamos-ubuntu-apt-source.sh`.

Override del repo GitHub:

```bash
STEAMOS_UBUNTU_GITHUB_REPO=TuOrg/SteamOS-Ubuntu sudo ./create-image.sh
```

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
sudo masi-kernel-update
sudo reboot
```
