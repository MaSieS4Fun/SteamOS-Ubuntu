#!/usr/bin/env bash
# Build one .deb from a prepared staging tree (must contain DEBIAN/control).
set -euo pipefail

mkdeb() {
    local staging="$1" out_dir="$2" name="$3" version="$4" arch="${5:-arm64}"
    local deb="${out_dir}/${name}_${version}_${arch}.deb"

    [[ -f "${staging}/DEBIAN/control" ]] || {
        echo "ERROR: missing DEBIAN/control in ${staging}" >&2
        return 1
    }

    mkdir -p "${out_dir}"
    rm -f "${deb}"
    # -z9 keeps the kernel bundle under GitHub's 100MB git blob limit.
    dpkg-deb -Zxz -z9 --root-owner-group --build "${staging}" "${deb}"
    echo "${deb}"
}
