#!/bin/bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "usage: $0 INSTALL_COMMAND [ARG ...]" >&2
    exit 64
fi

if [ "${SOVIET_INSTALL_AFTER_BUILD:-0}" != "1" ]; then
    echo "ℹ️ SovietExtension built; live WeChat install skipped (set SOVIET_INSTALL_AFTER_BUILD=1 to opt in)."
    exit 0
fi

exec "$@"
