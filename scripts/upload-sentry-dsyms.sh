#!/bin/sh
set -eu

if [ "${ASCEND_SENTRY_ENABLED:-NO}" != "YES" ]; then
    echo "Sentry dSYM upload skipped: ASCEND_SENTRY_ENABLED is not YES."
    exit 0
fi

if [ -z "${SENTRY_AUTH_TOKEN:-}" ]; then
    echo "Sentry dSYM upload skipped: SENTRY_AUTH_TOKEN is not set."
    exit 0
fi

if [ -z "${DWARF_DSYM_FOLDER_PATH:-}" ] || [ ! -d "${DWARF_DSYM_FOLDER_PATH}" ]; then
    echo "Sentry dSYM upload skipped: dSYM folder not found."
    exit 0
fi

SENTRY_ORG="${SENTRY_ORG:-ascend-uk}"
SENTRY_PROJECT="${SENTRY_PROJECT:-ascend-ios}"

if [ -n "${SENTRY_CLI_PATH:-}" ] && [ -x "${SENTRY_CLI_PATH}" ]; then
    SENTRY_CLI="${SENTRY_CLI_PATH}"
elif command -v sentry-cli >/dev/null 2>&1; then
    SENTRY_CLI="$(command -v sentry-cli)"
else
    echo "warning: Sentry dSYM upload skipped: sentry-cli was not found. Install sentry-cli or set SENTRY_CLI_PATH."
    exit 0
fi

echo "Uploading dSYMs to Sentry project ${SENTRY_ORG}/${SENTRY_PROJECT}."
"${SENTRY_CLI}" debug-files upload \
    --org "${SENTRY_ORG}" \
    --project "${SENTRY_PROJECT}" \
    "${DWARF_DSYM_FOLDER_PATH}"
