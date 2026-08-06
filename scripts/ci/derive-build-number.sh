#!/usr/bin/env bash
set -euo pipefail

# The allocator asks App Store Connect for the highest processed build or active
# build-upload reservation on this exact app. Failed uploads are reusable;
# processing and completed uploads advance the next suffix. Fixed per-app
# workflow concurrency prevents two CI runs from deriving against the same
# remote state before either upload is recorded.
script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node "${script_directory}/derive-build-number.mjs" "$@"
