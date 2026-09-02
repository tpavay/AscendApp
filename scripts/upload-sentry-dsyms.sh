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
# failure, and zero would make the comparison always true and report an instant
# rejection as a queue delay. Reject both here rather than let sentry-cli reject
# them later.
wait_timeout_is_valid=false
case "${SENTRY_WAIT_TIMEOUT}" in
    ''|*[!0-9]*)
        ;;
    *)
        if [ "${SENTRY_WAIT_TIMEOUT}" -gt 0 ]; then
            wait_timeout_is_valid=true
        fi
        ;;
esac

if [ "${wait_timeout_is_valid}" != "true" ]; then
    echo "error: Sentry dSYM upload failed: SENTRY_WAIT_TIMEOUT must be a whole number of seconds greater than zero, got '${SENTRY_WAIT_TIMEOUT}'." >&2
    exit 1
fi

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
# the whole wait. Elapsed time is the best available signal separating the two -
# it covers the whole process, so it supports a likelihood rather than a verdict
# and both branches below say so - and unlike parsing the CLI's output it does
# not move when the pinned CLI moves.
#
# The raw state is only obtainable from sentry-cli with --log-level=debug, which
# logs response bodies AND request headers - and its Authorization redaction
# keeps the token's first 8 characters. This repository is public, so that flag
# must stay off by default and out of CI logs; run it locally when a real
# rejection needs the server's own words.
echo "error: Sentry dSYM upload failed after ${elapsed}s (exit ${status})." >&2

if [ "${elapsed}" -ge "${SENTRY_WAIT_TIMEOUT}" ]; then
    cat >&2 <<EOF
error: The whole SENTRY_WAIT_TIMEOUT=${SENTRY_WAIT_TIMEOUT}s budget elapsed, so the symbol files
error: were most likely uploaded and left queued rather than rejected, and any
error: "An unknown error occurred" above most likely reads as "still queued".
error: Check https://status.sentry.io for a Sentry-side ingestion backlog.
EOF
else
    cat >&2 <<EOF
error: No SENTRY_WAIT_TIMEOUT=${SENTRY_WAIT_TIMEOUT}s wait-budget expiry was reached, so this is
error: most likely a real upload or processing rejection rather than a queue
error: delay. Re-run the command locally with --log-level=debug to get the
error: server's own reason.
EOF
fi

cat >&2 <<EOF
error: The dSYMs can be uploaded later from any copy of the archive with:
error:   sentry-cli debug-files upload --org ${SENTRY_ORG} --project ${SENTRY_PROJECT} <archive>/dSYMs
EOF

exit "${status}"
