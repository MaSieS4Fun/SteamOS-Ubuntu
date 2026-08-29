#!/usr/bin/env bash
# masi-motion — Qualcomm SSC → uinput IMU for InputPlumber deck-uhid.
#
#   sudo ./install.sh                    # build + install + enable (live)
#   sudo ./install.sh --rootfs /path     # bake into image rootfs (no start)
#   sudo ./install.sh --skip-build
#   sudo ./install.sh --check
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE=0
CHECK_ONLY=0
SKIP_BUILD=0
ROOTFS="/"

usage() {
	cat <<EOF
masi-motion — SSC → uinput IMU (InputPlumber deck-uhid gyro)

  ./install.sh                 full install on live system
  ./install.sh --rootfs DIR    install into image rootfs (bake)
  ./install.sh --check         verify services + evdev node
  ./install.sh --skip-build    packaging/services only
  ./install.sh --force         allow non-AYN device tree (debug / bake host)

Odin 2 axis frame: odin2-dsu-v9  (X, -Z, -Y) — do not overwrite via sync.
Requires: aarch64, root, kernel FastRPC + firmware (vendor/kernel/docs/GYRO.md)
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--force) FORCE=1; shift ;;
		--check|--check-only) CHECK_ONLY=1; shift ;;
		--skip-build) SKIP_BUILD=1; shift ;;
		--rootfs)
			ROOTFS="${2:-}"
			[[ -n "$ROOTFS" ]] || { echo "ERROR: --rootfs needs a path" >&2; exit 2; }
			shift 2
			;;
		-h|--help) usage; exit 0 ;;
		*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
	esac
done

log() { printf '==> [masi-motion] %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [[ "$ROOTFS" != "/" ]]; then
	ROOTFS="${ROOTFS%/}"
	[[ -d "${ROOTFS}/usr" ]] || die "Not a rootfs: ${ROOTFS}"
fi

path() {
	local p="$1"
	if [[ "$ROOTFS" == "/" ]]; then
		printf '%s\n' "$p"
	else
		printf '%s%s\n' "$ROOTFS" "$p"
	fi
}

_ayn_device() {
	[[ -f /proc/device-tree/compatible ]] || return 1
	tr -d '\0' < /proc/device-tree/compatible | grep -qE 'ayn,(thor|odin2)'
}

require_root() {
	[[ "${EUID:-$(id -u)}" -ne 0 ]] || return 0
	exec sudo -- "$0" "$@"
}

ensure_sources() {
	if [[ -f "${ROOT}/src/qcom-motion/src/batocera-qcom-motion.c" ]]; then
		return 0
	fi
	log "Sources missing — syncing from giroscopio sibling"
	"${ROOT}/scripts/sync-from-giroscopio.sh"
}

wait_for_motion_ready() {
	local ready="/run/masi/qcom-motion.ready"
	local timeout="${1:-90}"
	local i=0
	while [[ ! -f "${ready}" && "${i}" -lt "${timeout}" ]]; do
		sleep 1
		i=$((i + 1))
	done
	[[ -f "${ready}" ]]
}

check_smoke() {
	log "Smoke check"
	local ok=0 fail=0
	_pass() { echo "PASS  $*"; ok=$((ok + 1)); }
	_fail() { echo "FAIL  $*"; fail=$((fail + 1)); }

	_ayn_device && _pass "device ayn,odin2|thor" || _fail "not an AYN Odin2/Thor DT"
	[[ -x /usr/bin/qcom-motion ]] && _pass "qcom-motion" || _fail "qcom-motion missing"
	[[ -x /usr/bin/hexagonrpcd ]] && _pass "hexagonrpcd" || _fail "hexagonrpcd missing"
	[[ -x /usr/bin/masi-qcom-sensors ]] && _pass "masi-qcom-sensors" || _fail "masi-qcom-sensors missing"
	systemctl is-active --quiet masi-qcom-sensors.service && _pass "sensors service" || _fail "sensors service"
	systemctl is-active --quiet qcom-motion.service && _pass "qcom-motion service" || _fail "qcom-motion service"
	if wait_for_motion_ready 30; then
		_pass "qcom-motion ready marker"
	else
		_fail "qcom-motion ready marker"
	fi
	if grep -ql 'Sunshine gamepad (virtual) motion sensors\|qcom-motion/input0' /sys/class/input/event*/device/name /sys/class/input/event*/device/phys 2>/dev/null; then
		_pass "uinput IMU node (InputPlumber-whitelisted name)"
	else
		_fail "uinput IMU node missing"
	fi
	if grep -q 'odin2-dsu-v9' "${ROOT}/src/qcom-motion/src/batocera-qcom-motion.c" 2>/dev/null; then
		_pass "Odin2 axis frame odin2-dsu-v9 in sources"
	else
		_fail "Odin2 axis frame odin2-dsu-v9 missing from sources"
	fi
	echo ""
	echo "Result: ${ok} passed, ${fail} failed"
	[[ "${fail}" -eq 0 ]]
}

install_packaging() {
	log "Installing scripts, systemd, sensor profiles → ${ROOTFS}"
	install -d "$(path /usr/bin)" "$(path /usr/lib/systemd/system)" \
		"$(path /etc/tmpfiles.d)" "$(path /usr/share/qcom)" \
		"$(path /usr/share/doc/masi-motion)"

	install -m 0755 "${ROOT}/packaging/bin/"* "$(path /usr/bin)/"
	install -m 0644 "${ROOT}/systemd/"*.service "$(path /usr/lib/systemd/system)/"
	install -m 0644 "${ROOT}/packaging/etc/tmpfiles.d/masi-qcom.conf" \
		"$(path /etc/tmpfiles.d)/masi-qcom.conf"
	cp -a "${ROOT}/packaging/share/qcom/." "$(path /usr/share/qcom)/"
	install -D -m 0644 "${ROOT}/README.md" "$(path /usr/share/doc/masi-motion)/README.txt"

	if [[ "$ROOTFS" == "/" ]]; then
		systemd-tmpfiles --create /etc/tmpfiles.d/masi-qcom.conf
		systemctl daemon-reload
	fi
}

enable_services() {
	log "Enabling motion stack (sensors + qcom-motion)"
	local units=(
		masi-qcom-qrtr.service
		masi-qcom-sensors.service
		qcom-motion.service
		masi-inputplumber-refresh.service
	)
	if [[ "$ROOTFS" == "/" ]]; then
		systemctl enable "${units[@]}"
		systemctl restart masi-qcom-qrtr.service 2>/dev/null || systemctl start masi-qcom-qrtr.service || true
		systemctl restart masi-qcom-sensors.service || systemctl start masi-qcom-sensors.service || true
		systemctl restart qcom-motion.service || systemctl start qcom-motion.service || true
	else
		mkdir -p "$(path /etc/systemd/system/multi-user.target.wants)"
		local u
		for u in "${units[@]}"; do
			ln -sfn "/usr/lib/systemd/system/${u}" \
				"$(path /etc/systemd/system/multi-user.target.wants)/${u}"
		done
		if command -v systemctl >/dev/null 2>&1; then
			systemctl --root="$ROOTFS" enable "${units[@]}" 2>/dev/null || true
		fi
	fi
}

main() {
	if [[ "${CHECK_ONLY}" -eq 1 ]]; then
		check_smoke
		exit $?
	fi

	require_root "$@"

	if [[ "${FORCE}" -eq 0 ]] && [[ "$ROOTFS" == "/" ]] && ! _ayn_device; then
		die "AYN Thor/Odin 2 only (compatible=ayn,thor|ayn,odin2). Use --force to override."
	fi
	[[ "$(uname -m)" == "aarch64" ]] || die "Must run on aarch64"

	ensure_sources

	if ! grep -q 'odin2-dsu-v9' "${ROOT}/src/qcom-motion/src/batocera-qcom-motion.c"; then
		die "Expected odin2-dsu-v9 axis frame in batocera-qcom-motion.c (do not sync older giroscopio)"
	fi

	if [[ "${SKIP_BUILD}" -eq 0 ]]; then
		log "Building hexagonrpcd, libssc, qcom-motion (DESTDIR=${ROOTFS})"
		DESTDIR="${ROOTFS}" "${ROOT}/scripts/build.sh"
	else
		[[ -x "$(path /usr/bin/qcom-motion)" ]] || die "--skip-build but qcom-motion missing in ${ROOTFS}"
	fi

	install_packaging
	enable_services

	if [[ "$ROOTFS" == "/" ]]; then
		log "Waiting for motion bridge (up to 90s)…"
		wait_for_motion_ready 90 || log "WARN: not ready yet — journalctl -u qcom-motion -n 40"
		check_smoke || true
		echo ""
		log "Done. InputPlumber default YAML already includes IMU (odin2-dsu-v9)."
	else
		echo ""
		log "Done (rootfs). qcom-motion + services enabled for first boot."
		log "Axis frame: odin2-dsu-v9 (X, -Z, -Y)"
	fi
}

main "$@"
