#!/bin/sh
set -eu

if [ -z "${SENTRY_AUTH_TOKEN:-}" ]; then
    if [ "${CI:-false}" = "true" ]; then
        echo "error: Sentry dSYM upload failed: SENTRY_AUTH_TOKEN is not set." >&2
        exit 1
    fi

    echo "Sentry dSYM upload skipped: SENTRY_AUTH_TOKEN is not set."
    exit 0
fi

DSYM_FOLDER_PATH="${1:-${DWARF_DSYM_FOLDER_PATH:-}}"

if [ -z "${DSYM_FOLDER_PATH}" ] || [ ! -d "${DSYM_FOLDER_PATH}" ]; then
    echo "error: Sentry dSYM upload failed: dSYM folder not found at '${DSYM_FOLDER_PATH}'." >&2
    exit 1
fi

if ! find "${DSYM_FOLDER_PATH}" -type d -name '*.dSYM' -print -quit | grep -q .; then
    echo "error: Sentry dSYM upload failed: no dSYM bundles found in '${DSYM_FOLDER_PATH}'." >&2
    exit 1
fi

SENTRY_ORG="${SENTRY_ORG:-ascend-uk}"
SENTRY_PROJECT="${SENTRY_PROJECT:-ascend-ios}"

if [ -n "${SENTRY_CLI_PATH:-}" ]; then
    if [ ! -x "${SENTRY_CLI_PATH}" ]; then
        echo "error: Sentry dSYM upload failed: SENTRY_CLI_PATH is not executable at '${SENTRY_CLI_PATH}'." >&2
        exit 1
    fi

    SENTRY_CLI="${SENTRY_CLI_PATH}"
elif command -v sentry-cli >/dev/null 2>&1; then
    SENTRY_CLI="$(command -v sentry-cli)"
else
    echo "error: Sentry dSYM upload failed: sentry-cli was not found. Install sentry-cli or set SENTRY_CLI_PATH." >&2
    exit 1
fi

echo "Uploading dSYMs to Sentry project ${SENTRY_ORG}/${SENTRY_PROJECT}."
"${SENTRY_CLI}" debug-files upload \
    --org "${SENTRY_ORG}" \
    --project "${SENTRY_PROJECT}" \
    --wait \
    "${DSYM_FOLDER_PATH}"
