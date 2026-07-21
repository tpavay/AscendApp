#!/usr/bin/env bash
set -euo pipefail

# Each workflow's github.run_number is its own sequence, so it is not shared
# across staging and production, and raw run IDs are ~11 digits - far past the
# 32-bit ceiling App Store Connect enforces on every CFBundleVersion component.
# Coarse UTC epoch seconds carry the ordering instead: one integer per second,
# doubled so each workflow owns a slot. Every workflow serializes its own runs
# through its concurrency group, so two staging (or two production) builds
# cannot derive in the same second, and the distinct slot keeps staging and
# production apart when they derive in the same second. Across adjacent seconds
# even the later tick's slot 0 outranks the earlier tick's slot 1.
#
# 2026-01-01 00:00:00 UTC. Two slots consume two integers per second, so
# 4294967296 / 2 = 2147483648 seconds of range, exhausting around 2094-01-19 UTC.
BUILD_NUMBER_EPOCH_SECONDS=1767225600

WORKFLOW_SLOT_COUNT=2

# App Store Connect rejects any CFBundleVersion component above 2^32 - 1.
MAX_BUILD_NUMBER=4294967295

# Highest build number uploaded while the workflows still used
# github.run_number (Deploy Staging run 147, 2026-07-21). Every derived build
# number must stay strictly above it or TestFlight rejects the upload.
PREVIOUS_BUILD_NUMBER_FLOOR=147

slot="${1:-}"
timestamp="${2:-$(date -u +%s)}"

if [[ ! "${slot}" =~ ^[0-9]+$ ]] || (( slot >= WORKFLOW_SLOT_COUNT )); then
  echo "::error::Workflow slot must be 0 (staging) or 1 (production), got '${slot}'." >&2
  exit 1
fi

if [[ ! "${timestamp}" =~ ^[0-9]+$ ]]; then
  echo "::error::UTC timestamp must be a non-negative integer, got '${timestamp}'." >&2
  exit 1
fi

if (( timestamp < BUILD_NUMBER_EPOCH_SECONDS )); then
  echo "::error::Timestamp ${timestamp} predates the build-number epoch ${BUILD_NUMBER_EPOCH_SECONDS}." >&2
  exit 1
fi

build_number=$(((timestamp - BUILD_NUMBER_EPOCH_SECONDS) * WORKFLOW_SLOT_COUNT + slot))

if (( build_number <= PREVIOUS_BUILD_NUMBER_FLOOR )); then
  echo "::error::Derived build number ${build_number} is not above the last uploaded build number ${PREVIOUS_BUILD_NUMBER_FLOOR}." >&2
  exit 1
fi

if (( build_number > MAX_BUILD_NUMBER )); then
  echo "::error::Derived build number ${build_number} exceeds the App Store limit ${MAX_BUILD_NUMBER}." >&2
  echo "::error::The 32-bit range from the epoch is exhausted; ship a new marketing version with a reset build-number scheme." >&2
  exit 1
fi

printf '%s\n' "${build_number}"
