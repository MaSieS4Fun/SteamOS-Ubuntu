# Publicar SteamOS-Ubuntu en GitHub (privado)

Sin `gh` CLI: crear el repo en la web y hacer push con git.

## 1. Identidad git (solo tú — no Cursor)

```bash
git config --global user.name "Tu Nombre"
git config --global user.email "tu-email@ejemplo.com"
```

Los commits llevan **solo** este autor. Cursor no aparece en GitHub salvo que:
- invites a un bot como colaborador, o
- uses `Co-authored-by:` en mensajes de commit.

No subas `.cursor/` (ya está en `.gitignore`).

## 2. Limpiar repos anidados

Algunos `vendor/*` se clonaron con su propio `.git` y bloquean `git add`:

```bash
cd ~/Desktop/SteamOS-Ubuntu
chmod +x scripts/prepare-git-publish.sh
./scripts/prepare-git-publish.sh
```

Quita solo metadatos `.git` anidados; **los archivos del vendor se quedan**.

## 3. Crear repo privado en GitHub (web)

1. [github.com/new](https://github.com/new)
2. Name: `SteamOS-Ubuntu`
3. **Private**
4. **No** marques README, .gitignore ni license (ya los tienes localmente)
5. Create repository

Copia la URL SSH o HTTPS, por ejemplo:
`git@github.com:MaSieS4Fun/SteamOS-Ubuntu.git`

## 4. Primer commit y push

```bash
cd ~/Desktop/SteamOS-Ubuntu

# Si ya hiciste git init antes:
git status

git add -A
git status   # revisa que NO entren output/, .gnupg/, .cache/

git commit -m "SteamOS-Ubuntu: SM8550 gaming OS, apt packaging, kernel 7.2.2"

git remote add origin git@github.com:TU_USUARIO/SteamOS-Ubuntu.git
git push -u origin main
```

Autenticación HTTPS: [Personal Access Token](https://github.com/settings/tokens) como contraseña.  
SSH: `ssh-keygen` + añadir clave pública en GitHub → Settings → SSH keys.

## 5. GitHub Pages + Actions (privado)

- **Settings → Pages → Build from branch `gh-pages`**
- **Settings → Secrets → Actions → `APT_GPG_PRIVATE_KEY`**

Exportar clave privada apt (solo para el secret, nunca al repo):

```bash
export GNUPGHOME=~/Desktop/SteamOS-Ubuntu/packaging/apt/.gnupg
gpg --export-secret-keys --armor 0FB8C0FD06987E5EAAB6283F9BB08C3751373F58
```

Pega el bloque `-----BEGIN PGP PRIVATE KEY BLOCK-----` en el secret.

Probar CI:

```bash
git tag v1.0.0-rc1
git push origin v1.0.0-rc1
```

## 6. Repo privado vs apt en consolas

- Imagen con apps embebidas + `steamos-ubuntu.list` → OK en privado.
- `apt update` en usuarios → **solo cuando el repo sea público** y Pages sirva `/apt/`.

## 7. Día del vídeo

1. Settings → General → **Change visibility → Public**
2. Publicar Release (`.img` + notas)
3. Subir vídeo

## Alternativa: upload ZIP (no recomendado para updates)

GitHub permite subir un ZIP en Releases, pero **pierdes** historial, Actions y apt automático. Mejor git push aunque sea la primera vez por web + token.
