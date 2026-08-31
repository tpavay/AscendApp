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
SENTRY_WAIT_TIMEOUT="${SENTRY_WAIT_TIMEOUT:-300}"

# The failure diagnosis below compares elapsed seconds against this budget, so a
# non-numeric value would silently turn a queue delay back into an unexplained
# failure. Reject it here rather than let sentry-cli reject it later.
case "${SENTRY_WAIT_TIMEOUT}" in
    ''|*[!0-9]*)
        echo "error: Sentry dSYM upload failed: SENTRY_WAIT_TIMEOUT must be a whole number of seconds, got '${SENTRY_WAIT_TIMEOUT}'." >&2
        exit 1
        ;;
esac

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

started_at="$(date +%s)"
status=0
"${SENTRY_CLI}" debug-files upload \
    --org "${SENTRY_ORG}" \
    --project "${SENTRY_PROJECT}" \
    --wait-for "${SENTRY_WAIT_TIMEOUT}" \
    "${DSYM_FOLDER_PATH}" || status=$?
elapsed=$(( $(date +%s) - started_at ))

if [ "${status}" -eq 0 ]; then
    exit 0
fi

# sentry-cli prints "ERROR <file>" with the fallback text "An unknown error
# occurred" for any file that is merely still queued when --wait-for expires,
# which reads as a rejected symbol file and is why run 33434685667 could not be
# told apart from a real upload failure. The upload itself had succeeded; Sentry
# had a US ingestion backlog and left the assemble task in state "created" for
# the whole wait. Elapsed time is the one signal that separates the two, and
# unlike parsing the CLI's output it does not move when the pinned CLI moves.
#
# The raw state is only obtainable from sentry-cli with --log-level=debug, which
# logs response bodies AND request headers - and its Authorization redaction
# keeps the token's first 8 characters. This repository is public, so that flag
# must stay off by default and out of CI logs; run it locally when a real
# rejection needs the server's own words.
echo "error: Sentry dSYM upload failed after ${elapsed}s (exit ${status})." >&2

if [ "${elapsed}" -ge "${SENTRY_WAIT_TIMEOUT}" ]; then
    cat >&2 <<EOF
error: The symbol files were uploaded; Sentry had not finished processing them
error: within SENTRY_WAIT_TIMEOUT=${SENTRY_WAIT_TIMEOUT}s, so sentry-cli gave up waiting. Any
error: "An unknown error occurred" above means "still queued", not "rejected".
error: Check https://status.sentry.io for a Sentry-side ingestion backlog.
error: The dSYMs can be uploaded later from any copy of the archive with:
error:   sentry-cli debug-files upload --org ${SENTRY_ORG} --project ${SENTRY_PROJECT} <archive>/dSYMs
EOF
else
    cat >&2 <<EOF
error: Sentry finished before the ${SENTRY_WAIT_TIMEOUT}s wait budget, so this is a real
error: upload or processing rejection rather than a queue delay. Re-run the
error: command locally with --log-level=debug to get the server's own reason.
EOF
fi

exit "${status}"
