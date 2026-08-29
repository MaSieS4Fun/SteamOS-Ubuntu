# SteamOS-Ubuntu — Ubuntu Resolute gaming image (ARM64)
# Pattern: Universal Blue–style layered Containerfile, Ubuntu base.
ARG BASE_IMAGE=docker.io/library/ubuntu:resolute
FROM ${BASE_IMAGE}

ARG TARGETARCH=arm64
ENV DEBIAN_FRONTEND=noninteractive \
    DEBCONF_NONINTERACTIVE_SEEN=true \
    UCF_FORCE_CONFFOLD=1 \
    STEAMOS_UBUNTU=1 \
    STEAM_USER=steam \
    STEAM_PASS=steam

COPY packages /tmp/packages
COPY build_files /tmp/build_files
COPY system_files /

# Mesa apt pin must NOT be present during package install (blocks libgbm1→xwayland).
# Stages must match bootstrap-rootfs.sh (snap off, Brave repo, desktop polish).
RUN rm -f /etc/apt/preferences.d/99-block-ubuntu-mesa \
 && chmod +x /tmp/build_files/*.sh \
 && /tmp/build_files/00-install-packages.sh \
 && /tmp/build_files/05-purge-distro-firmware.sh \
 && /tmp/build_files/10-create-steam-user.sh \
 && /tmp/build_files/20-enable-services.sh \
 && /tmp/build_files/25-disable-snap.sh \
 && /tmp/build_files/30-brave-and-mozilla-repos.sh \
 && /tmp/build_files/40-desktop-polish.sh \
 && /tmp/build_files/99-cleanup.sh \
 && rm -rf /tmp/packages /tmp/build_files

LABEL org.opencontainers.image.title="SteamOS-Ubuntu" \
      org.opencontainers.image.description="Ubuntu Resolute gaming OS for SM8550 / Adreno 740" \
      org.opencontainers.image.source="https://github.com/local/SteamOS-Ubuntu" \
      steamos.ubuntu.base="resolute" \
      steamos.ubuntu.arch="arm64"

CMD ["/sbin/init"]
