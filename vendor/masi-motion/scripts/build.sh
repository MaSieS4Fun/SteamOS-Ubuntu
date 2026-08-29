#!/usr/bin/env bash
# Build hexagonrpcd, libssc, qcom-motion on aarch64 → PREFIX.
# Motion-only (no virtual gamepads). Used by vendor/masi-motion/install.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-/tmp/masi-motion-build}"
DESTDIR="${DESTDIR:-/}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
PREFIX="${PREFIX:-/usr}"

HEXAGONRPC_VERSION=dd9ac70c026e1bad93e8cffa3801255b8ceb551e
LIBSSC_VERSION=3befde3ef215bdb78c4a48aa72c99cd458c2aed0
PATCH_VENDOR="${MASI_MOTION_VENDOR_PATCHES:-${ROOT}/vendor}"

log() { printf '==> [masi-motion] %s\n' "$*" >&2; }

multiarch() {
	dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo aarch64-linux-gnu
}

require_arch() {
	[[ "$(uname -m)" == "aarch64" ]] || {
		echo "ERROR: aarch64 required (got $(uname -m))" >&2
		exit 1
	}
}

require_sources() {
	[[ -f "${ROOT}/src/qcom-motion/src/batocera-qcom-motion.c" ]] || {
		echo "ERROR: missing ${ROOT}/src/qcom-motion/src/batocera-qcom-motion.c" >&2
		echo "       Run: ${ROOT}/scripts/sync-from-giroscopio.sh" >&2
		exit 1
	}
}

install_deps() {
	log "Installing build dependencies"
	apt-get update
	apt-get install -y --no-install-recommends \
		build-essential git meson ninja-build pkg-config \
		libjson-c-dev libglib2.0-dev libqmi-glib-dev libqrtr-glib-dev \
		protobuf-compiler protobuf-c-compiler libprotobuf-c-dev zlib1g-dev \
		qrtr-tools || apt-get install -y --no-install-recommends qrtr || true
}

fetch_git_sha() {
	local url="$1" sha="$2" dest="$3"
	rm -rf "${dest}"
	mkdir -p "${dest}"
	git -C "${dest}" init -q
	git -C "${dest}" remote add origin "${url}"
	git -C "${dest}" fetch --depth 1 origin "${sha}"
	git -C "${dest}" checkout -q FETCH_HEAD
}

apply_patches() {
	local src_dir="$1" patch_dir="$2"
	[[ -d "${patch_dir}" ]] || return 0
	local patch
	shopt -s nullglob
	for patch in "${patch_dir}"/*.patch; do
		log "Applying $(basename "${patch}")"
		patch -p1 -d "${src_dir}" < "${patch}"
	done
	shopt -u nullglob
}

build_hexagonrpc() {
	local src="${BUILD_ROOT}/hexagonrpc"
	fetch_git_sha "https://github.com/linux-msm/hexagonrpc.git" \
		"${HEXAGONRPC_VERSION}" "${src}"
	apply_patches "${src}" "${PATCH_VENDOR}/hexagonrpc"

	rm -rf "${src}/build"
	meson setup "${src}/build" "${src}" --prefix="${PREFIX}" \
		-Dhexagonrpcd_verbose=false
	ninja -C "${src}/build" -j"${JOBS}"
	DESTDIR="${DESTDIR}" ninja -C "${src}/build" install

	if [[ -x "${src}/build/tools/sscregistrygen" ]]; then
		install -D -m 0755 "${src}/build/tools/sscregistrygen" \
			"${DESTDIR}${PREFIX}/bin/sscregistrygen"
	elif [[ ! -x "${DESTDIR}${PREFIX}/bin/sscregistrygen" ]]; then
		find "${src}/build" -name sscregistrygen -type f -executable -print -quit \
			| while read -r bin; do
				install -D -m 0755 "${bin}" "${DESTDIR}${PREFIX}/bin/sscregistrygen"
			done
	fi
}

build_libssc() {
	local src="${BUILD_ROOT}/libssc"
	fetch_git_sha "https://codeberg.org/DylanVanAssche/libssc.git" \
		"${LIBSSC_VERSION}" "${src}"
	apply_patches "${src}" "${PATCH_VENDOR}/libssc"

	rm -rf "${src}/build"
	meson setup "${src}/build" "${src}" --prefix="${PREFIX}" \
		-Dtests=false -Dintrospection=false -Dauto_features=disabled
	ninja -C "${src}/build" -j"${JOBS}"
	DESTDIR="${DESTDIR}" ninja -C "${src}/build" install
	if [[ "${DESTDIR}" == "/" ]] && command -v ldconfig >/dev/null; then
		ldconfig
	fi
}

build_motion() {
	local src_c="${ROOT}/src/qcom-motion/src/batocera-qcom-motion.c"
	local build_c="${BUILD_ROOT}/qcom-motion.c"
	local out="${BUILD_ROOT}/qcom-motion"
	local ma ssc_inc ssc_so

	mkdir -p "${BUILD_ROOT}"
	sed \
		-e 's|/userdata/system/qcom-sensors|/var/lib/masi/qcom-sensors|g' \
		-e 's|/var/run/batocera-qcom-motion.ready|/run/masi/qcom-motion.ready|g' \
		-e 's|"AYN Odin2 Motion"|"Sunshine gamepad (virtual) motion sensors"|g' \
		"${src_c}" > "${build_c}"

	unset PKG_CONFIG_SYSROOT_DIR || true
	ma="$(multiarch)"
	ssc_inc=""
	ssc_so=""
	if [[ -f "${DESTDIR}${PREFIX}/include/libssc/libssc.h" && -e "${DESTDIR}${PREFIX}/lib/${ma}/libssc.so" ]]; then
		ssc_inc="${DESTDIR}${PREFIX}/include/libssc"
		ssc_so="${DESTDIR}${PREFIX}/lib/${ma}/libssc.so"
	elif [[ -f "${BUILD_ROOT}/libssc/src/libssc.h" && -e "${BUILD_ROOT}/libssc/build/src/libssc.so" ]]; then
		ssc_inc="${BUILD_ROOT}/libssc/src"
		ssc_so="${BUILD_ROOT}/libssc/build/src/libssc.so"
	fi

	if [[ -n "$ssc_inc" ]]; then
		# shellcheck disable=SC2046
		"${CC:-cc}" -std=c11 -Wall -Wextra -O2 \
			"${build_c}" -o "${out}" \
			$(pkg-config --cflags --libs glib-2.0 gobject-2.0) \
			-I"${ssc_inc}" "${ssc_so}" -lz -lm
	else
		# shellcheck disable=SC2046
		"${CC:-cc}" -std=c11 -Wall -Wextra -O2 \
			"${build_c}" -o "${out}" \
			$(pkg-config --cflags glib-2.0 libssc) \
			$(pkg-config --libs glib-2.0 libssc) -lz -lm
	fi

	install -D -m 0755 "${out}" "${DESTDIR}${PREFIX}/bin/qcom-motion"
	ln -sfn qcom-motion "${DESTDIR}${PREFIX}/bin/batocera-qcom-motion"
}

main() {
	require_arch
	require_sources
	[[ "${EUID:-$(id -u)}" -eq 0 ]] || exec sudo -- "$0" "$@"

	local skip_stack=0
	for arg; do
		case "${arg}" in
			--motion-only) skip_stack=1 ;;
		esac
	done

	mkdir -p "${BUILD_ROOT}"
	if [[ "${skip_stack}" -eq 0 ]]; then
		install_deps
		build_hexagonrpc
		build_libssc
	fi
	build_motion
	log "Done: ${DESTDIR}${PREFIX}/bin/qcom-motion"
}

main "$@"
