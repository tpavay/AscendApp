#!/usr/bin/env bash
set -euo pipefail

# GitHub run IDs are repository-wide and strictly increasing, so they are the
# only counter both deploy workflows share - each workflow's github.run_number
# is its own sequence and collides across workflows. Raw run IDs are ~11 digits
# though, far past the 32-bit ceiling App Store Connect enforces on every
# CFBundleVersion component, so a fixed epoch is subtracted. Subtraction keeps
# the mapping order-preserving and collision-free; a modulo would wrap and let a
# later run emit a smaller build number than an earlier one.
RUN_ID_EPOCH=29800000000

# App Store Connect rejects any CFBundleVersion component above 2^32 - 1.
MAX_BUILD_NUMBER=4294967295

# Highest build number uploaded while the workflows still used
# github.run_number (Deploy Staging run 147, 2026-07-21). Every derived build
# number must stay strictly above it or TestFlight rejects the upload.
PREVIOUS_BUILD_NUMBER_FLOOR=147

run_id="${1:-${GITHUB_RUN_ID:-}}"

if [[ ! "${run_id}" =~ ^[0-9]+$ ]]; then
  echo "::error::GITHUB_RUN_ID must be a positive integer, got '${run_id}'." >&2
  exit 1
fi

build_number=$((run_id - RUN_ID_EPOCH))

if (( build_number <= 0 )); then
  echo "::error::Run ID ${run_id} is at or below the build-number epoch ${RUN_ID_EPOCH}." >&2
  exit 1
fi

if (( build_number <= PREVIOUS_BUILD_NUMBER_FLOOR )); then
  echo "::error::Derived build number ${build_number} is not above the last uploaded build number ${PREVIOUS_BUILD_NUMBER_FLOOR}." >&2
  exit 1
fi

if (( build_number > MAX_BUILD_NUMBER )); then
  echo "::error::Derived build number ${build_number} exceeds the App Store limit ${MAX_BUILD_NUMBER}." >&2
  echo "::error::Raising RUN_ID_EPOCH would emit build numbers below already-uploaded builds; ship a new marketing version with a reset build-number scheme instead." >&2
  exit 1
fi

printf '%s\n' "${build_number}"
