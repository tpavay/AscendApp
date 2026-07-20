#!/usr/bin/env bash
#
# Turn a raw xcodebuild log into a readable failure summary.
#
# xcodebuild interleaves its diagnostics with the build commands of every other
# target still in flight, so a single compiler error routinely lands a thousand
# lines before the end of a 16,000-line log. Read from the tail - which is what
# `gh run view --log-failed` and the web log viewer show first - the job looks
# like it died mid-copy of some unrelated SPM dependency with no diagnostic at
# all. That misread cost a full debugging cycle on 2026-07-20, so the summary is
# written to the step log, re-emitted as GitHub annotations, and the raw log is
# uploaded as an artifact.
#
# Usage: summarize-xcodebuild-failure.sh <path-to-xcodebuild-log>
#
# Runs against a log downloaded from the Actions API too, which carries a
# per-line ISO-8601 timestamp prefix the live `tee`d log does not.

set -uo pipefail

log_path="${1:-}"

if [ -z "$log_path" ] || [ ! -f "$log_path" ]; then
  echo "::error::summarize-xcodebuild-failure.sh: no xcodebuild log at '${log_path}'."
  exit 0
fi

normalized="$(mktemp)"
trap 'rm -f "$normalized"' EXIT
sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+Z //' "$log_path" >"$normalized"

echo "::group::Failure summary"

found_any=0

# Compiler and linker diagnostics, anchored to the file so GitHub can annotate
# the diff. Deduplicated because a single error is echoed by every batch-compile
# invocation that saw it.
compiler_errors="$(grep -E '^/.+: error: ' "$normalized" | sort -u)"

if [ -n "$compiler_errors" ]; then
  found_any=1
  echo "Compiler diagnostics:"
  echo "$compiler_errors"
  echo

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    location="${line%%: error: *}"
    message="${line#*: error: }"
    file="$(printf '%s' "$location" | cut -d: -f1)"
    line_number="$(printf '%s' "$location" | cut -d: -f2)"
    column="$(printf '%s' "$location" | cut -d: -f3)"
    # Annotations anchor to repo-relative paths.
    file="${file#"${GITHUB_WORKSPACE:-/nonexistent}"/}"
    echo "::error file=${file},line=${line_number:-1},col=${column:-1}::${message}"
  done <<<"$compiler_errors"
fi

# Swift Testing and XCTest failures.
test_failures="$(grep -E '✘ (Test|Suite) ' "$normalized" | sort -u)"

if [ -n "$test_failures" ]; then
  found_any=1
  echo "Test failures:"
  echo "$test_failures"
  echo

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    echo "::error::${line}"
  done <<<"$test_failures"
fi

# xcodebuild's own terminal verdict, which names the failed build commands.
verdict="$(grep -E '^\*\* (TEST|BUILD) FAILED \*\*|^The following build commands failed:|^\s*Testing (failed|cancelled)' "$normalized" | sort -u)"

if [ -n "$verdict" ]; then
  found_any=1
  echo "xcodebuild verdict:"
  echo "$verdict"
  echo
fi

if [ "$found_any" -eq 0 ]; then
  # No diagnostic anywhere means the toolchain never reported the failure - a
  # killed process, an exhausted runner, or a crashed simulator. Say so, rather
  # than leaving a future reader to infer it from a log that just stops.
  echo "::error::xcodebuild failed without emitting any diagnostic. That is the signature of a killed process rather than a build error - see the resource snapshot below and the uploaded raw log."
  echo "Last 80 lines of ${log_path}:"
  tail -80 "$normalized"
  echo
fi

echo "::endgroup::"

# Always captured: cheap, and the only way to tell an out-of-disk or
# out-of-memory runner from a compile error after the fact.
echo "::group::Runner resource snapshot"
echo "--- disk ---"
df -h || true
echo "--- memory ---"
vm_stat || true
echo "--- load ---"
uptime || true
echo "--- log size ---"
wc -l "$log_path" || true
echo "::endgroup::"
