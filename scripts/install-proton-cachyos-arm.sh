#!/usr/bin/env bash
# Install latest Proton-CachyOS ARM64 into Steam compatibilitytools.d
# and set it as the default Steam Play tool.
#
# Usage:
#   sudo ./scripts/install-proton-cachyos-arm.sh /media/odin2/STORAGE
#   sudo ./scripts/install-proton-cachyos-arm.sh /path/to/rootfs
#   STEAM_HOME_OVERRIDE=/home/steam ./scripts/install-proton-cachyos-arm.sh /   # live system
#
# Tweaks applied (required on ARM handhelds):
#   - strip require_tool_appid from toolmanifest.vdf
#   - files/bin -> files/bin-arm64 symlink (Lutris / legacy tools)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:-}"
REPO="CachyOS/proton-cachyos"
CACHE="${ROOT_DIR}/.cache/proton-cachyos"
API="https://api.github.com/repos/${REPO}/releases/latest"

log() { printf '==> [proton-cachyos] %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "$ROOTFS" && -d "${ROOTFS}/usr" ]] || die "Usage: $0 <rootfs-or-STORAGE>"
[[ "$(id -u)" -eq 0 ]] || die "Run as root"

STEAM_HOME="${STEAM_HOME_OVERRIDE:-${ROOTFS}/home/steam}"
STEAM_DIR="${STEAM_HOME}/.local/share/Steam"
CT_DIR="${STEAM_DIR}/compatibilitytools.d"
CFG="${STEAM_DIR}/config/config.vdf"

[[ -d "$STEAM_DIR" ]] || die "Steam dir missing: $STEAM_DIR (install Steam ARM first)"

install -d "$CACHE" "$CT_DIR" "$(dirname "$CFG")"

# --- resolve latest arm64 asset (or reuse cache / Downloads) ---
resolve_asset() {
  local json name url tag
  if [[ -n "${PROTON_CACHYOS_TAR:-}" && -f "${PROTON_CACHYOS_TAR}" ]]; then
    TAR="${PROTON_CACHYOS_TAR}"
    log "Using PROTON_CACHYOS_TAR=$TAR"
    return 0
  fi
  # Prefer already-downloaded release next to common paths
  for cand in \
    "${CACHE}"/proton-cachyos-*-arm64.tar.xz \
    /home/odin2/Downloads/proton-cachyos-*-arm64.tar.xz
  do
    [[ -f "$cand" ]] || continue
    TAR="$cand"
    log "Reusing local tarball: $TAR"
    return 0
  done

  log "Querying GitHub latest release…"
  json="$(curl -fsSL "$API")" || die "GitHub API failed"
  name="$(printf '%s' "$json" | python3 -c '
import json,sys
rel=json.load(sys.stdin)
for a in rel.get("assets",[]):
    n=a.get("name","")
    if n.endswith("-arm64.tar.xz"):
        print(n); raise SystemExit
raise SystemExit("no arm64.tar.xz asset")
')" || die "No arm64 asset in latest release"
  url="$(printf '%s' "$json" | python3 -c '
import json,sys
rel=json.load(sys.stdin)
for a in rel.get("assets",[]):
    n=a.get("name","")
    if n.endswith("-arm64.tar.xz"):
        print(a["browser_download_url"]); raise SystemExit
')" 
  tag="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))')"
  TAR="${CACHE}/${name}"
  if [[ ! -f "$TAR" ]]; then
    log "Downloading ${name} (${tag})…"
    curl -fL --retry 3 -o "${TAR}.partial" "$url"
    mv "${TAR}.partial" "$TAR"
  else
    log "Cached: $TAR"
  fi
}

resolve_asset
[[ -f "$TAR" ]] || die "Tarball missing"

TOOL_NAME="$(basename "$TAR" .tar.xz)"
DEST="${CT_DIR}/${TOOL_NAME}"
PREP="${CACHE}/prepared/${TOOL_NAME}"

# --- extract + patch into cache, then sync into Steam dir ---
if [[ ! -x "${PREP}/proton" || ! -f "${PREP}/toolmanifest.vdf" ]]; then
  log "Extracting $TAR → $PREP"
  rm -rf "$PREP"
  install -d "${CACHE}/prepared"
  tar --no-same-owner -xJf "$TAR" -C "${CACHE}/prepared"
  [[ -d "$PREP" ]] || die "Expected extract dir missing: $PREP"
fi

log "Patching toolmanifest + bin symlink in prepared tree"
# Strip require_tool_appid (Steam ARM errors if present)
if [[ -f "${PREP}/toolmanifest.vdf" ]]; then
  grep -v 'require_tool_appid' "${PREP}/toolmanifest.vdf" > "${PREP}/toolmanifest.vdf.tmp"
  mv "${PREP}/toolmanifest.vdf.tmp" "${PREP}/toolmanifest.vdf"
fi
# Lutris / legacy expect files/bin
if [[ -d "${PREP}/files/bin-arm64" ]]; then
  rm -rf "${PREP}/files/bin"
  ln -sfn bin-arm64 "${PREP}/files/bin"
fi
[[ -x "${PREP}/proton" ]] || die "proton launcher missing after extract"
[[ -L "${PREP}/files/bin" || -d "${PREP}/files/bin" ]] || die "files/bin symlink missing"
if grep -q 'require_tool_appid' "${PREP}/toolmanifest.vdf"; then
  die "require_tool_appid still present in toolmanifest.vdf"
fi

log "Installing → $DEST"
rm -rf "$DEST"
# Prefer hardlink/copy; fall back to cp -a
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "${PREP}/" "${DEST}/"
else
  cp -a "$PREP" "$DEST"
fi

# Drop stale template that pointed at missing Proton11ARM
rm -f "${CT_DIR}/compatibilitytool.vdf"

# --- set as default Steam Play tool (CompatToolMapping "0") ---
set_default_tool() {
  local tool="$1" cfg="$2"
  python3 - "$tool" "$cfg" <<'PY'
import pathlib, re, sys
tool, cfg_path = sys.argv[1], pathlib.Path(sys.argv[2])
mapping = (
    '\t\t\t\t"CompatToolMapping"\n'
    '\t\t\t\t{\n'
    '\t\t\t\t\t"0"\n'
    '\t\t\t\t\t{\n'
    f'\t\t\t\t\t\t"name"\t\t"{tool}"\n'
    '\t\t\t\t\t\t"config"\t\t""\n'
    '\t\t\t\t\t\t"priority"\t\t"75"\n'
    '\t\t\t\t\t}\n'
    '\t\t\t\t}'
)
if cfg_path.exists():
    text = cfg_path.read_text(encoding="utf-8", errors="ignore")
else:
    text = (
        '"InstallConfigStore"\n{\n\t"Software"\n\t{\n\t\t"Valve"\n\t\t{\n'
        '\t\t\t"Steam"\n\t\t\t{\n\t\t\t}\n\t\t}\n\t}\n}\n'
    )

# Drop any existing CompatToolMapping block (brace-balanced under Steam)
def drop_mapping(s: str) -> str:
    key = '"CompatToolMapping"'
    i = s.find(key)
    if i < 0:
        return s
    j = s.find("{", i)
    if j < 0:
        return s
    depth = 0
    k = j
    while k < len(s):
        if s[k] == "{":
            depth += 1
        elif s[k] == "}":
            depth -= 1
            if depth == 0:
                # include trailing newline after closing brace
                end = k + 1
                if end < len(s) and s[end] == "\n":
                    end += 1
                return s[:i] + s[end:]
        k += 1
    return s

text = drop_mapping(text)

m = re.search(r'("Steam"\s*\{)', text)
if not m:
    raise SystemExit(f"no Steam section in {cfg_path}")
insert = "\n\t\t\t\t\"SteamPlayEnabled\"\t\t\"1\"\n" + mapping + "\n"
# Avoid duplicating SteamPlayEnabled
text2 = re.sub(r'\n\t\t\t\t"SteamPlayEnabled"\s*"[^"]*"\n?', "\n", text)
m = re.search(r'("Steam"\s*\{)', text2)
text = text2[: m.end()] + insert + text2[m.end() :]

cfg_path.parent.mkdir(parents=True, exist_ok=True)
cfg_path.write_text(text, encoding="utf-8")
print(f"default CompatToolMapping[0] → {tool}")
PY
}

set_default_tool "$TOOL_NAME" "$CFG"

# Ownership
STEAM_UID="$(awk -F: '$1=="steam"{print $3; exit}' "${ROOTFS}/etc/passwd" 2>/dev/null || true)"
STEAM_GID="$(awk -F: '$1=="steam"{print $4; exit}' "${ROOTFS}/etc/passwd" 2>/dev/null || true)"
g="$(awk -F: '$1=="steam"{print $3; exit}' "${ROOTFS}/etc/group" 2>/dev/null || true)"
[[ -n "$g" ]] && STEAM_GID="$g"
if [[ -n "${STEAM_UID:-}" && -n "${STEAM_GID:-}" ]]; then
  chown -R "${STEAM_UID}:${STEAM_GID}" "$CT_DIR" "$(dirname "$CFG")"
else
  chown -R steam:steam "$CT_DIR" "$(dirname "$CFG")" 2>/dev/null || true
fi

log "OK: ${TOOL_NAME}"
log "  path : $DEST"
log "  bin  : $(readlink -f "${DEST}/files/bin" 2>/dev/null || ls -la "${DEST}/files/bin")"
log "  manifest:"
grep -E 'commandline|require_tool|compatmanager' "${DEST}/toolmanifest.vdf" || true
log "Default Steam Play tool set to ${TOOL_NAME}"
