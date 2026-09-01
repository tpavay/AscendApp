#!/bin/bash
#
# Builds the staging test bundle once, then runs the suite across several host
# processes instead of one.
#
# WHY, measured 2026-09-01 against `iOS Verify (Staging)`: the test host's
# memory grows with the number of tests it has already executed and is never
# reclaimed - 850 tests peak at 2,020 MB RSS, the full 1,927 peak at 4,228 MB.
# A `macos-15` runner holds ~7 GB with ~2.4 GB already wired, so one process
# running the whole suite arrives at the tail of the run on a machine with
# 65-83 MB free, ~2.7 GB in the compressor and ~50,000 swapouts. Past that the
# job stops completing tests altogether: three killed runs each show 12-22
# minutes of total output silence with the host still alive and still logging,
# after reaching 1,700-1,814 completions of ~1,900. The cap then fires and
# reports `cancelled`.
#
# This is a repo-level trend, not a property of any one branch: skipping the
# three suites of the branch that first hit it moved peak RSS from 4,228 MB to
# 4,343 MB, i.e. nowhere. Nor is it a shortage of minutes - the killed run
# reached 1,814 completions in 6m44s against a green run's 1,846 in 8m30s. It
# is faster, then it hits a wall. Raising `timeout-minutes` buys a longer crawl
# on a thrashing machine, which is why the cap stays where it is.
#
# The tests, the build, the cache key and the runner are all unchanged. Only the
# number of processes the suite is spread over changes, and each pass starts
# from a fresh host.
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "usage: run-ios-test-passes.sh <simulator-udid> [passes]" >&2
    exit 2
fi

simulator_id="$1"
pass_count="${2:-2}"
log_dir="build-logs"
log="$log_dir/xcodebuild-staging.log"

mkdir -p "$log_dir"

# A runner is discarded whole, so CI deliberately keeps Xcode's default
# DerivedData - relocating it would move `SourcePackages` out from under the
# `actions/cache` path and silently re-resolve every package on every run. A
# developer machine reuses one store across throwaway worktrees, so it does not.
derived_data=()
if [ -z "${GITHUB_ACTIONS:-}" ]; then
    derived_data=(-derivedDataPath "$PWD/.build/dd")
fi

common=(
    -project AscendApp.xcodeproj
    -scheme "AscendApp-Staging"
    -configuration Staging
    -destination "platform=iOS Simulator,id=$simulator_id"
    ENABLE_TESTABILITY=YES
)

# `set -u` under the runner's bash 3.2 treats an empty array as unset, so an
# unguarded `"${derived_data[@]}"` aborts the script on CI - which is the only
# place the array is ever empty.
common+=(${derived_data[@]+"${derived_data[@]}"})

echo "--- Building for testing ---" | tee -a "$log"
xcodebuild "${common[@]}" build-for-testing 2>&1 | tee -a "$log"

# Enumeration needs the built bundle, so it cannot run before the build above.
echo "--- Enumerating tests ---" | tee -a "$log"
xcodebuild "${common[@]}" \
    -enumerate-tests \
    -test-enumeration-style flat \
    -test-enumeration-format json \
    -test-enumeration-output-path "$log_dir/enumerated-tests.json" \
    test-without-building 2>&1 | tee -a "$log"

node scripts/ci/split-enumerated-tests.mjs \
    "$log_dir/enumerated-tests.json" \
    "$log_dir/test-pass-" \
    "$pass_count" | tee -a "$log"

# Hand the VM system back what the previous phase is still holding.
#
# The crash this exists to prevent is a system-wide allocation failure, not a
# process-local one: the report says `EXC_BREAKPOINT` with `ktriageinfo` reading
# "mach_vm_allocate_kernel failed within call to vm_map_enter". And it is
# positional rather than compositional - across three CI runs of two halves
# balanced to 964/963 tests and 23/22 hosted suites, the FIRST pass died every
# time and the second passed every time. What separates them is that pass one
# starts on a machine still carrying a 19-minute Swift compile and an
# enumeration launch, while pass two starts on one that has just had a whole
# test host exit. `purge` is the supported way to ask for those cached and
# compressed pages back; it is advisory, so a failure here is not fatal.
reclaim_memory() {
    sudo /usr/sbin/purge 2>/dev/null || /usr/sbin/purge 2>/dev/null || true
}

# Every pass runs even when an earlier one fails, so one broken suite reports
# its own failure instead of hiding every later suite's result behind it.
failed_passes=()

for pass in $(seq 1 "$pass_count"); do
    args=()
    while IFS= read -r line; do
        [ -n "$line" ] && args+=("$line")
    done < "$log_dir/test-pass-$pass.txt"

    echo "--- Test pass $pass of $pass_count (${#args[@]} suites) ---" | tee -a "$log"
    reclaim_memory
    vm_stat | awk '/Pages free|occupied by compressor/ {print "    " $0}' | tee -a "$log"

    # A separate result bundle per pass: `xcodebuild` refuses to write over an
    # existing one, and the upload step takes the whole directory anyway.
    if xcodebuild "${common[@]}" \
        -resultBundlePath "$log_dir/AscendApp-Staging-pass$pass.xcresult" \
        "${args[@]}" \
        test-without-building 2>&1 | tee -a "$log"; then
        echo "--- Test pass $pass passed ---" | tee -a "$log"
    else
        echo "--- Test pass $pass FAILED ---" | tee -a "$log"
        failed_passes+=("$pass")
    fi
done

# A host that traps takes every test queued on the hosted-window gate down with
# it, and `xcodebuild` reports all of them as "Test crashed with signal trap"
# with no file, no line and no stack - the same text for the one test that
# actually trapped and for the dozen merely waiting on it. The trap frame is in
# the simulator's crash report, which lives outside the workspace and is thrown
# away with the runner, so collect it while it still exists.
if [ "${#failed_passes[@]}" -gt 0 ]; then
    reports="$log_dir/crash-reports"
    mkdir -p "$reports"

    # Simulator processes report into the host's DiagnosticReports, and the
    # device's own CoreSimulator log carries what the host's does not.
    find "$HOME/Library/Logs/DiagnosticReports" \
        -name "AscendApp*" -newermt "-2 hours" -maxdepth 1 \
        -exec cp {} "$reports/" \; 2>/dev/null || true
    find "$HOME/Library/Logs/CoreSimulator" \
        -name "*.crash" -o -name "*.ips" -newermt "-2 hours" \
        -exec cp {} "$reports/" \; 2>/dev/null || true

    collected="$(find "$reports" -type f | wc -l | tr -d ' ')"
    echo "::group::Crash reports collected: $collected"
    for report in "$reports"/*; do
        [ -f "$report" ] || continue
        echo "----- $(basename "$report") -----"
        # The termination reason and the crashing thread's top frames are what
        # name the trap; the rest of an .ips is register state and binary images.
        head -c 4000 "$report"
        echo
    done
    echo "::endgroup::"

    if [ "$collected" = "0" ]; then
        echo "::warning::No crash report found. A pass can fail on assertions alone, in which case there is nothing to collect."
    fi

    echo "::error::Test passes failed: ${failed_passes[*]}"
    exit 1
fi
