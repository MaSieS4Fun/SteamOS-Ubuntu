#!/usr/bin/env bash
# Strip cont-splash / simple-framebuffer from AYN and Retroid DTBs (fixes
# SM8550 dispcc blue screen on those panels).
# AYANEO keeps splash_region. ROCKNIX and ARMADA boot the EVO with that
# reservation; deleting it drops the ABL logo and the panel stays black.
# Do NOT strip mdss_mdp* — that left apps-SMMU translation faults on display SID
# and is absent from the known-good Armbian 6.18.8 Odin 2 DTB path.
set -euo pipefail

_sanitize_dtb_with_dtc() {
    local dtb="$1" dts="${dtb}.dts" out="${dtb}.new"

    dtc -I dtb -O dts -o "${dts}" "${dtb}" 2>/dev/null || return 1

    python3 - "${dts}" <<'PY'
import re, sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(errors="replace")
# ROCKNIX AYANEO reference DTBs ask for split adsp.mdt. This tree ships
# ayaneo/adsp.mbn (odin2 alias). The name is inside KERNEL, so a kernel-only
# drop has to match the rootfs the tester already has.
text = text.replace("qcom/sm8550/ayaneo/adsp.mdt", "qcom/sm8550/ayaneo/adsp.mbn")
text = text.replace("qcom/sm8550/ayaneo/adsp_dtb.mdt", "qcom/sm8550/ayaneo/adsp_dtb.mbn")
model = ""
mm = re.search(r'\bmodel = "([^"]+)"', text)
if mm:
    model = mm.group(1)
keep_splash = model.startswith("AYANEO")
lines = text.splitlines(True)
out = []
skip = 0
depth = 0

drop_names = (
    "cont-splash", "splash_region", "simple-framebuffer",
    "framebuffer@",
)

for line in lines:
    stripped = line.strip()
    if skip:
        if "{" in line:
            depth += line.count("{")
        if "}" in line:
            depth -= line.count("}")
            if depth <= 0:
                skip = 0
                depth = 0
        continue

    if not keep_splash:
        if re.match(r"^\s*/?[\w@.-]+:\s", line) or re.match(r"^\s*/?[\w@.-]+\s*\{", line):
            name = stripped.split(":")[0].split("{")[0].strip().lstrip("/")
            if any(d in name for d in drop_names):
                skip = 1
                depth = line.count("{") - line.count("}")
                continue

        if "cont-splash" in stripped or "simple-framebuffer" in stripped:
            continue

    out.append(line)

path.write_text("".join(out))
PY

    dtc -I dts -O dtb -o "${out}" "${dts}" 2>/dev/null || return 1
    mv -f "${out}" "${dtb}"
    rm -f "${dts}"
}

sanitize_dtb_file() {
    local dtb="$1"
    command -v dtc >/dev/null 2>&1 || return 0
    _sanitize_dtb_with_dtc "${dtb}" || true
}

sanitize_dtb_dir() {
    local dir="$1" f n=0
    [[ -d "${dir}" ]] || return 0
    command -v dtc >/dev/null 2>&1 || {
        echo "  DTB sanitize: install device-tree-compiler (dtc) to strip cont-splash" >&2
        return 0
    }

    for f in "${dir}"/slot-*.dtb "${dir}"/*.dtb; do
        [[ -f "${f}" ]] || continue
        sanitize_dtb_file "${f}" && n=$((n + 1))
    done
    [[ "${n}" -gt 0 ]] && echo "  DTB sanitize: ${n} file(s) — AYN/RP6 splash removed, AYANEO splash kept" >&2
}
