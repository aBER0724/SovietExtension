#!/bin/bash
set -euo pipefail

CONFIG_PATH="${1:-${HOME}/Library/Application Support/SovietExtension/theme.json}"
SUPPORT_DIR="${HOME}/Library/Application Support/SovietExtension"
PATCHER="${SUPPORT_DIR}/apply_theme.py"
APP_PATH="/Applications/WeChat.app"
DYLIB="${APP_PATH}/Contents/Resources/wechat.dylib"
BACKUP="${APP_PATH}/Contents/Resources/wechat.dylib.soviet-original"
LOG="/tmp/SovietExtension-theme-apply.log"


resolve_signing_identity() {
    if [ -n "${SOVIET_CODE_SIGN_IDENTITY:-}" ]; then
        printf '%s' "${SOVIET_CODE_SIGN_IDENTITY}"
        return
    fi
    local identity
    identity=$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | /usr/bin/head -1)
    if [ -n "${identity}" ]; then
        printf '%s' "${identity}"
    else
        printf '%s' '-'
    fi
}

SIGN_IDENTITY="$(resolve_signing_identity)"
exec >>"${LOG}" 2>&1
printf '\n[%s] Applying global theme\n' "$(date '+%F %T')"

[ -f "${PATCHER}" ] || { echo "missing patcher: ${PATCHER}"; exit 1; }
[ -f "${CONFIG_PATH}" ] || { echo "missing config: ${CONFIG_PATH}"; exit 1; }
[ -f "${DYLIB}" ] || { echo "missing WeChat theme image: ${DYLIB}"; exit 1; }
[ -f "${BACKUP}" ] || { echo "missing pristine backup: ${BACKUP}"; exit 1; }

# This must remain before every quit/kill operation. It loads the pristine
# backup, validates exact advanced keys and generates/counts the full patch in
# memory without changing the config, backup, live dylib, or app.
/usr/bin/python3 "${PATCHER}" "${DYLIB}" --backup "${BACKUP}" --config "${CONFIG_PATH}" --preflight

/usr/bin/osascript -e 'tell application "WeChat" to quit' >/dev/null 2>&1 || true
for _ in {1..30}; do
    /usr/bin/pgrep -x WeChat >/dev/null 2>&1 || break
    /bin/sleep 0.2
done
/usr/bin/pkill -x WeChat >/dev/null 2>&1 || true
/bin/sleep 0.5

/usr/bin/python3 "${PATCHER}" "${DYLIB}" --backup "${BACKUP}" --config "${CONFIG_PATH}"
/usr/bin/xattr -d com.apple.quarantine "${DYLIB}" >/dev/null 2>&1 || true
if [ "${SIGN_IDENTITY}" = "-" ]; then
    echo "warning: no persistent signing identity found; Full Disk Access may need to be granted again"
else
    echo "using persistent signing identity: ${SIGN_IDENTITY}"
fi
/usr/bin/codesign --force --sign "${SIGN_IDENTITY}" --identifier com.tencent.xinWeChat.theme-resource --timestamp=none "${DYLIB}"
/usr/bin/codesign --verify --strict "${DYLIB}"
/usr/bin/codesign --force --deep --sign "${SIGN_IDENTITY}" --preserve-metadata=identifier,entitlements,flags,runtime --timestamp=none "${APP_PATH}"
/usr/bin/codesign --verify --deep --strict "${APP_PATH}"
/usr/bin/open "${APP_PATH}"
echo "theme applied successfully"
