#!/bin/bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "usage: $0 SUPPORT_DIR PATCHER_SOURCE RUNNER_SOURCE" >&2
    exit 64
fi

support_dir="$1"
patcher_source="$2"
runner_source="$3"
themes_dir="${support_dir}/themes"

[ -f "${patcher_source}" ] || { echo "theme patcher missing: ${patcher_source}" >&2; exit 1; }
[ -f "${runner_source}" ] || { echo "theme runner missing: ${runner_source}" >&2; exit 1; }

# Only assign permissions while creating absent directories. Existing support
# directories and every user-owned themes/*.json file are left untouched.
if [ ! -d "${support_dir}" ]; then
    mkdir -m 700 -p "${support_dir}"
fi
if [ ! -d "${themes_dir}" ]; then
    mkdir -m 700 "${themes_dir}"
fi

cp "${patcher_source}" "${support_dir}/apply_theme.py"
cp "${runner_source}" "${support_dir}/apply_theme.sh"
chmod 755 "${support_dir}/apply_theme.py" "${support_dir}/apply_theme.sh"
