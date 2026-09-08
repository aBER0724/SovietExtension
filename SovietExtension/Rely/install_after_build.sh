#!/bin/bash
set -euo pipefail

APP_NAME="WeChat"
FRAMEWORK_NAME="${PRODUCT_NAME}"

APP_PATH="/Applications/${APP_NAME}.app"
MACOS_PATH="${APP_PATH}/Contents/MacOS"
APP_EXECUTABLE_PATH="${MACOS_PATH}/${APP_NAME}"
APP_EXECUTABLE_BACKUP_PATH="${APP_EXECUTABLE_PATH}_backup"

SIGN_IDENTITY="${SOVIET_CODE_SIGN_IDENTITY:-B75037083ABB7A4DBEF63F3B5E142DC7DBCF61C1}"
echo "👉 Signing identity: ${SIGN_IDENTITY}"

FRAMEWORK_SRC_PATH="${BUILT_PRODUCTS_DIR}/${FRAMEWORK_NAME}.framework"
FRAMEWORK_DST_PATH="${MACOS_PATH}/${FRAMEWORK_NAME}.framework"

INSERT_DYLIB_PATH="${SRCROOT}/Rely/insert_dylib"
LOAD_DYLIB_PATH="@executable_path/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}"

echo "=============================="
echo " Install ${FRAMEWORK_NAME}"
echo "=============================="
echo "APP_PATH=${APP_PATH}"
echo "FRAMEWORK_SRC_PATH=${FRAMEWORK_SRC_PATH}"
echo "FRAMEWORK_DST_PATH=${FRAMEWORK_DST_PATH}"
echo "INSERT_DYLIB_PATH=${INSERT_DYLIB_PATH}"
echo "LOAD_DYLIB_PATH=${LOAD_DYLIB_PATH}"

if [ ! -d "${APP_PATH}" ]; then
    echo "❌ WeChat.app not found: ${APP_PATH}"
    exit 1
fi

if [ ! -f "${APP_EXECUTABLE_PATH}" ]; then
    echo "❌ WeChat executable not found: ${APP_EXECUTABLE_PATH}"
    exit 1
fi

if [ ! -d "${FRAMEWORK_SRC_PATH}" ]; then
    echo "❌ Built framework not found: ${FRAMEWORK_SRC_PATH}"
    exit 1
fi

if [ ! -f "${INSERT_DYLIB_PATH}" ]; then
    echo "❌ insert_dylib not found: ${INSERT_DYLIB_PATH}"
    exit 1
fi

chmod +x "${INSERT_DYLIB_PATH}"

echo "👉 Quit WeChat if running..."
osascript -e 'tell application "WeChat" to quit' >/dev/null 2>&1 || true
sleep 1
pkill -x WeChat >/dev/null 2>&1 || true
sleep 1

echo "👉 Backup original executable if needed..."
if [ ! -f "${APP_EXECUTABLE_BACKUP_PATH}" ]; then
    cp "${APP_EXECUTABLE_PATH}" "${APP_EXECUTABLE_BACKUP_PATH}"
    echo "✅ Backup created: ${APP_EXECUTABLE_BACKUP_PATH}"
else
    echo "✅ Backup exists: ${APP_EXECUTABLE_BACKUP_PATH}"
fi

echo "👉 Restore executable from backup before reinserting..."
cp "${APP_EXECUTABLE_BACKUP_PATH}" "${APP_EXECUTABLE_PATH}"

echo "👉 Copy framework..."
rm -rf "${FRAMEWORK_DST_PATH}"
cp -R "${FRAMEWORK_SRC_PATH}" "${FRAMEWORK_DST_PATH}"

echo "👉 Remove quarantine..."
xattr -rd com.apple.quarantine "${FRAMEWORK_DST_PATH}" >/dev/null 2>&1 || true
xattr -rd com.apple.quarantine "${APP_PATH}" >/dev/null 2>&1 || true

echo "👉 Insert dylib..."
"${INSERT_DYLIB_PATH}" --all-yes "${LOAD_DYLIB_PATH}" "${APP_EXECUTABLE_BACKUP_PATH}" "${APP_EXECUTABLE_PATH}"

echo "👉 Code sign nested framework..."
codesign --force --sign "${SIGN_IDENTITY}" --timestamp=none "${FRAMEWORK_DST_PATH}"

echo "👉 Code sign WeChatAppEx if exists..."
APP_EX_PATH="${MACOS_PATH}/WeChatAppEx.app"
if [ -d "${APP_EX_PATH}" ]; then
    xattr -rd com.apple.quarantine "${APP_EX_PATH}" >/dev/null 2>&1 || true
    codesign --force --deep --sign "${SIGN_IDENTITY}" --preserve-metadata=identifier,entitlements,flags,runtime --timestamp=none "${APP_EX_PATH}" || true

    WEAPP_PATH="${APP_EX_PATH}/Contents/Frameworks/WeChatAppEx Framework.framework/Versions/C/Helpers/WeApp.app"
    if [ -d "${WEAPP_PATH}" ]; then
        codesign --force --deep --sign "${SIGN_IDENTITY}" --preserve-metadata=identifier,entitlements,flags,runtime --timestamp=none "${WEAPP_PATH}" || true
    fi
fi

echo "👉 Code sign main WeChat app..."
codesign --force --deep --sign "${SIGN_IDENTITY}" --preserve-metadata=identifier,entitlements,flags,runtime --timestamp=none "${APP_PATH}"

echo "👉 Verify inserted dylib..."
otool -l "${APP_EXECUTABLE_PATH}" | grep -A3 "${FRAMEWORK_NAME}" || true

echo "👉 Verify code sign..."
codesign -vvv --deep --strict "${APP_PATH}" || true

echo "✅ Install finished."
echo "Now run:"
echo "  rm -f /tmp/YMWeChatAntiRevokePatch.log"
echo "  open -a WeChat"
echo "  tail -f /tmp/YMWeChatAntiRevokePatch.log"
