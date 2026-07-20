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

found_diagnostic=0

# Resolve a bare source file name to its repo-relative path so the annotation
# lands on the diff. Swift Testing reports only the basename.
resolve_repo_path() {
  local candidate="$1"
  case "$candidate" in
    */*)
      printf '%s' "${candidate#"${GITHUB_WORKSPACE:-/nonexistent}"/}"
      return
      ;;
  esac

  local matches
  matches="$(git ls-files -- "*/${candidate}" "${candidate}" 2>/dev/null)"
  if [ "$(printf '%s\n' "$matches" | grep -c .)" -eq 1 ]; then
    printf '%s' "$matches"
  else
    printf '%s' "$candidate"
  fi
}

# Compiler, linker, and driver diagnostics. File-anchored ones let GitHub
# annotate the diff; linker and build-input failures carry no file anchor and
# would be dropped entirely by a path-anchored pattern. Deduplicated with awk
# rather than `sort -u` so emission order survives - the first error xcodebuild
# printed is usually the root cause and the rest are cascade.
compiler_errors="$(grep -E '^/.+: (error|fatal error): |^(ld|ld64\.lld|clang\+\+|clang|swiftc|swift-frontend|xcodebuild): (error|fatal error): |^error: ' "$normalized" | awk '!seen[$0]++')"

if [ -n "$compiler_errors" ]; then
  found_diagnostic=1
  echo "Compiler diagnostics:"
  echo "$compiler_errors"
  echo

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [[ "$line" =~ ^(/.+):([0-9]+):([0-9]+):\ (error|fatal\ error):\ (.*)$ ]]; then
      file="$(resolve_repo_path "${BASH_REMATCH[1]}")"
      echo "::error file=${file},line=${BASH_REMATCH[2]},col=${BASH_REMATCH[3]}::${BASH_REMATCH[5]}"
    else
      echo "::error::${line}"
    fi
  done <<<"$compiler_errors"
fi

# Swift Testing and XCTest failures.
test_failures="$(grep -E '✘ (Test|Suite) ' "$normalized" | awk '!seen[$0]++')"

if [ -n "$test_failures" ]; then
  found_diagnostic=1
  echo "Test failures:"
  echo "$test_failures"
  echo

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [[ "$line" =~ at\ ([^[:space:]:]+):([0-9]+):([0-9]+): ]]; then
      file="$(resolve_repo_path "${BASH_REMATCH[1]}")"
      echo "::error file=${file},line=${BASH_REMATCH[2]},col=${BASH_REMATCH[3]}::${line}"
    else
      echo "::error::${line}"
    fi
  done <<<"$test_failures"
fi

# xcodebuild's own terminal verdict, which names the failed build commands. It
# deliberately does not count as a diagnostic: it states that the build failed
# without ever saying why, so on its own it must still trigger the fallback.
verdict="$(grep -E '^\*\* (TEST|BUILD) FAILED \*\*|^The following build commands failed:|^\s*Testing (failed|cancelled)' "$normalized" | awk '!seen[$0]++')"

if [ -n "$verdict" ]; then
  echo "xcodebuild verdict:"
  echo "$verdict"
  echo
fi

if [ "$found_diagnostic" -eq 0 ]; then
  # No diagnostic anywhere means the toolchain never reported a reason - a
  # killed process, an exhausted runner, or a crashed simulator. Say so, rather
  # than leaving a future reader to infer it from a log that just stops.
  if [ -n "$verdict" ]; then
    echo "::error::xcodebuild reported a failure but emitted no compiler or test diagnostic - see the last 80 lines below, the resource snapshot, and the uploaded raw log."
  else
    echo "::error::xcodebuild failed without emitting any diagnostic. That is the signature of a killed process rather than a build error - see the resource snapshot below and the uploaded raw log."
  fi
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
