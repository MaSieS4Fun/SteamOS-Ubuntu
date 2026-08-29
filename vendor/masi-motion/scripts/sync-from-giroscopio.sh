#!/usr/bin/env bash
# Copy motion-only sources from sibling giroscopio tree (one-time / dev sync).
# Refuses to overwrite a tree that already has the locked Odin2 axis frame
# (odin2-dsu-v9) unless --force is passed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${ROOT}/../.." && pwd)"
FORCE=0

for arg; do
	case "${arg}" in
		--force) FORCE=1 ;;
		-h|--help)
			echo "Usage: $0 [--force]"
			exit 0
			;;
	esac
done

LOCAL_C="${ROOT}/src/qcom-motion/src/batocera-qcom-motion.c"
if [[ -f "${LOCAL_C}" ]] && grep -q 'odin2-dsu-v9' "${LOCAL_C}" && [[ "${FORCE}" -eq 0 ]]; then
	echo "ERROR: local tree already has odin2-dsu-v9 (working Steam gyro frame)." >&2
	echo "       Refusing sync that would overwrite it. Use --force only if intentional." >&2
	exit 1
fi

for candidate in \
	"${GIROSCOPIO_SRC:-}" \
	"${REPO_ROOT}/../giroscopio-mal-aolicado/vendor/giroscopio" \
	"/home/steam/Desktop/giroscopio-mal-aolicado/vendor/giroscopio" \
	"/home/masies/Desktop/giroscopio-mal-aolicado/vendor/giroscopio"; do
	[[ -n "${candidate}" && -f "${candidate}/src/qcom-motion/src/batocera-qcom-motion.c" ]] && {
		SRC="${candidate}"
		break
	}
done

[[ -n "${SRC:-}" ]] || {
	echo "ERROR: giroscopio source tree not found." >&2
	echo "Set GIROSCOPIO_SRC=/path/to/vendor/giroscopio" >&2
	exit 1
}

echo "==> Sync from ${SRC}"

copy_tree() {
	local rel="$1"
	mkdir -p "${ROOT}/$(dirname "${rel}")"
	rm -rf "${ROOT}/${rel}"
	cp -a "${SRC}/${rel}" "${ROOT}/${rel}"
	echo "  ${rel}"
}

copy_tree src/qcom-motion
[[ -d "${SRC}/vendor/hexagonrpc" ]] && copy_tree vendor/hexagonrpc
[[ -d "${SRC}/vendor/libssc" ]] && copy_tree vendor/libssc
copy_tree packaging/share/qcom

echo "==> Sync complete"
echo "==> NOTE: re-apply odin2-dsu-v9 (X,-Z,-Y) if the sibling tree is older"
