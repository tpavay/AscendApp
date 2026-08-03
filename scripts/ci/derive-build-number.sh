#!/usr/bin/env bash
set -euo pipefail

# The allocator asks App Store Connect for the highest build already uploaded to
# this exact app. That remote value is the only sequence state: cancelled runs
# and reruns consume nothing, while an uploaded build always advances the next
# suffix. Fixed per-app workflow concurrency prevents two CI runs from deriving
# against the same remote state before either upload completes.
script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node "${script_directory}/derive-build-number.mjs" "$@"
