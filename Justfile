# SteamOS-Ubuntu build recipes
set dotenv-load := false
export IMAGE := env("IMAGE", "localhost/steamos-ubuntu")
export TAG := env("TAG", "resolute")
export CONTAINER_RUNTIME := env("CONTAINER_RUNTIME", "podman")

default:
    @just --list

# Build OCI image (Ubuntu Resolute + packages + overlays)
build:
    {{CONTAINER_RUNTIME}} build --network=host -t {{IMAGE}}:{{TAG}} -f Containerfile .

# Rebuild without cache
rebuild:
    {{CONTAINER_RUNTIME}} build --network=host --no-cache -t {{IMAGE}}:{{TAG}} -f Containerfile .

# Build SM8550 gaming kernel (vendor/kernel)
kernel:
    ./vendor/kernel/make.sh

# Build vendor userspace (mesa/gamescope/mangohud) — long
vendor-stack ROOTFS="output/rootfs":
    sudo ./scripts/build-vendor-stack.sh {{ROOTFS}}

mesa ROOTFS="output/rootfs":
    sudo ./scripts/build-vendor-mesa.sh {{ROOTFS}}

# Build Adreno gamescope from vendor/ into rootfs
gamescope ROOTFS="output/rootfs":
    sudo ./scripts/build-vendor-gamescope.sh {{ROOTFS}}

mangohud ROOTFS="output/rootfs":
    sudo ./scripts/build-vendor-mangohud.sh {{ROOTFS}}

# Export container rootfs tarball to output/
export-rootfs: build
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p output
    cid=$({{CONTAINER_RUNTIME}} create {{IMAGE}}:{{TAG}})
    {{CONTAINER_RUNTIME}} export "$cid" | gzip -1 > output/steamos-ubuntu-rootfs.tar.gz
    {{CONTAINER_RUNTIME}} rm "$cid"
    ls -lh output/steamos-ubuntu-rootfs.tar.gz

# Full device image (needs sudo)
image:
    sudo ./scripts/build-image.sh

# Install audio drop-in into live system or rootfs
audio ROOT="/":
    sudo ./vendor/audio/scripts/install-into-rootfs.sh {{ROOT}}

# Create / refresh local steam user (live host helper)
steam-user:
    sudo ./scripts/create-steam-user.sh
