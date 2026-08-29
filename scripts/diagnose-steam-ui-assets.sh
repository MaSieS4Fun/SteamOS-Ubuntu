#!/usr/bin/env bash
# Diagnose Steam Deck UI bake completeness on a mounted STORAGE rootfs.
set -euo pipefail
ROOT="${1:-/media/odin2/STORAGE}"
S="$ROOT/home/steam/.local/share/Steam"
echo "ROOT=$ROOT"
echo "== steamui =="
ls -la "$S/steamui" 2>&1 | head -30
echo "== clientui =="
ls -la "$S/clientui" 2>&1 | head -20
echo "== package =="
ls -la "$S/package" 2>&1 | head -25
echo "== sizes =="
du -sh "$S/steamui" "$S/clientui" "$S/steamrtarm64" "$S" 2>&1 || true
echo "== index.html =="
find "$S/steamui" "$S/clientui" -name 'index.html' 2>/dev/null | head || true
echo "== .installed =="
ls -la "$S/package/"*.installed 2>/dev/null | head || true
echo "== NM =="
chroot "$ROOT" systemctl is-enabled NetworkManager 2>&1 || true
ls "$ROOT/usr/sbin/NetworkManager" 2>&1 || true
echo "== recent steam logs =="
ls -lt "$S/logs" 2>&1 | head -20
