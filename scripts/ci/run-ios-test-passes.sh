#!/bin/bash
#
# Builds the staging test bundle once, then runs the suite across several host
# processes instead of one.
#
# WHY, measured 2026-09-01 against `iOS Verify (Staging)`: one process could not
# hold this suite. Run whole it peaked at 4,228 MB RSS on a `macos-15` runner
# holding ~7 GB with ~2.4 GB already wired, reached the tail of the run with
# 65-83 MB free and ~2.7 GB compressed, and then stopped completing tests at
# all - three killed runs each show 12-22 minutes of total output silence with
# the host alive and still logging. Split two ways it still lost a pass to
# `EXC_BREAKPOINT` / "mach_vm_allocate_kernel failed within call to
# vm_map_enter", an allocation failure that lands on a different test each run
# and names none of them.
#
# The bulk of that demand was one benchmark, since deleted:
# `addTimeLayoutScalesLinearlyAsHeaviestClustersPileUp` ran 108 `ImageRenderer`
# passes and peaked at 2,008 MB alone against 630 MB for a sibling. Removing it
# took its suite from 2,311 MB to 1,026 MB and the whole suite from 4,228 MB to
# 3,122 MB.
#
# The remainder is kept in two hosts because 3,122 MB in one host is still most
# of what the runner has once the simulator and `xcodebuild` are resident, and
# because the split costs one extra host launch rather than a permanent
# slowdown. Do not raise the pass count as a memory fix without measuring:
# memory is concentrated in a few suites rather than spread across tests, so
# splitting four ways measured a HIGHER peak than two (2,881 MB against 2,020
# MB) by collecting the heavy suites into one pass.
#
# The concentrated ones get a host to themselves instead - see `ISOLATED_PASSES`
# in `plan-test-passes.mjs`, which is why this script runs however many pass
# files the planner wrote rather than a fixed number. Isolating one five-test
# suite costs ~90 seconds; a general three-way split costs every run ~4
# minutes. Measured again 2026-09-03 when the screen-render evidence suites
# outgrew the two-way split: each rendered screen is retained for the life of
# the host, so a balanced pass died at its tail with 13 render suites in flight
# and 67 MB free, and the fourteen suites holding 1,000-1,434 MB each moved to
# one shared isolated host. The numbers live beside that list.
#
# Minutes were never the constraint and the cap is not the lever: a killed run
# reached 1,814 completions in 6m44s where a green run took 8m30s for 1,846.
#
# What changed on 2026-09-03, once memory was contained, is how the minutes
# are spent - measured on the green job 100376172708, 37.8 minutes in this
# script: 17.7 of compile, 11.7 of launching and tearing down hosts, 8.4 of
# tests.
#
# - The test build compiles at `-Onone`, single-file, without dSYMs and for the
#   active architecture only. The Staging configuration in the project is
#   `wholemodule` at Xcode's default `-O`, which is right for the TestFlight
#   archive `deploy-staging.yml` produces through fastlane and wrong for a
#   build whose only job is to run tests: the app and test targets compiled as
#   two serial whole-module frontends of 6.4 and 5.25 minutes. Locally the
#   cold build went from 394 s to 92 s and the whole suite ran with the same
#   outcome, the same peak memory and the one wall-clock assertion
#   (`WorkoutDetailScrollHostingTests`, 1,500 ms budget) at 0.92 s. These are
#   command-line overrides, exactly like `ENABLE_TESTABILITY=YES` beside them,
#   so the project's Staging settings and every archive stay untouched.
# - There is no `-enumerate-tests` run. It executed zero tests and cost 4.5
#   minutes, 4.0 of which were the runner's first simulator boot. The passes
#   are named in `plan-test-passes.mjs` and the last one is the complement, so
#   a new suite still cannot fall out of the job; what enumeration caught - a
#   name matching nothing - is caught from each pass's `.xcresult` instead.
# - The simulator boots while the compiler is busy: `Select simulator` starts
#   the boot, and the first pass waits on `bootstatus` here. If the boot
#   failed, `bootstatus -b` boots it again, exactly as the first `xcodebuild`
#   would have.
# - A hung pass goes red instead of cancelled. The step has its own
#   `timeout-minutes` in `ci.yml` so a kill concludes `failure`; a silence
#   watchdog kills a pass in which no test starts or finishes for five
#   minutes while its host is alive - bytes are not liveness, a wedged host
#   still logs network noise - after printing `vm_stat` and the tests still
#   in flight; and
#   `-test-timeouts-enabled` fails a single hung test with its name attached.
#   The per-test allowance is 600 s, not the 120 s first proposed: on the same
#   green job 23 tests reported durations over 120 s and one 189 s, because a
#   `.hostsAWindow` test's duration is mostly queue time on the shared gate,
#   and a local run with the render suites concentrated in one pass pushed two
#   past 300 s. The allowance is XCTest's: when it fires, the host is killed
#   and restarted from the next test, the test that fired it records "Time
#   limit was exceeded", and every test in flight at the kill is recorded
#   nowhere (nine, in that local run). The pass fails on the recorded issue,
#   so it is loud, but it is a kill, which is why the allowance sits far above
#   any legitimate queue wait and the watchdog below is the first responder.
#
# The tests, the cache key and the runner are all unchanged.
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "usage: run-ios-test-passes.sh <simulator-udid>" >&2
    exit 2
fi

simulator_id="$1"
log_dir="build-logs"
log="$log_dir/xcodebuild-staging.log"
scripts_dir="$(cd "$(dirname "$0")" && pwd)"

# Longer than any gap a healthy pass has shown between Swift Testing events
# (42 s within a pass, 132 s from launch to the first event, both on the green
# job), shorter than any wedge (10-29 minutes), and short enough that the
# watchdog fires before the per-test allowance below does.
silence_limit_seconds="${ASCEND_TEST_PASS_SILENCE_SECONDS:-300}"

# What counts as progress: a test or suite starting or finishing. A wedged
# host keeps emitting network and WebKit noise, so bytes are not liveness.
progress_pattern='[◇✔✘⚠] (Test|Suite) '

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
    SWIFT_OPTIMIZATION_LEVEL=-Onone
    SWIFT_COMPILATION_MODE=singlefile
    DEBUG_INFORMATION_FORMAT=dwarf
    ONLY_ACTIVE_ARCH=YES
)

# `set -u` under the runner's bash 3.2 treats an empty array as unset, so an
# unguarded `"${derived_data[@]}"` aborts the script on CI - which is the only
# place the array is ever empty.
common+=(${derived_data[@]+"${derived_data[@]}"})

# A single test that hangs fails itself, by name, instead of holding the pass
# open until the step cap ends it anonymously. Ten minutes, because the
# allowance kills and restarts the host (see the header) and a hosted test's
# duration is mostly queue time; the silence watchdog names a hang sooner.
test_timeouts=(
    -test-timeouts-enabled YES
    -default-test-execution-time-allowance 600
    -maximum-test-execution-time-allowance 600
)

echo "--- Building for testing ---" | tee -a "$log"
xcodebuild "${common[@]}" build-for-testing 2>&1 | tee -a "$log"

echo "--- Planning test passes ---" | tee -a "$log"
rm -f "$log_dir"/test-pass-*.txt
node "$scripts_dir/plan-test-passes.mjs" "$log_dir/test-pass-" | tee -a "$log"

# The planner writes one file per pass; count what it produced rather than
# assuming, or an isolated pass never runs.
total_passes="$(find "$log_dir" -name 'test-pass-*.txt' | wc -l | tr -d ' ')"

# The boot was started by the `Select simulator` step while the compiler had
# the cores. This is the synchronisation point; `-b` boots it if that failed.
echo "--- Waiting for the simulator to finish booting ---" | tee -a "$log"
xcrun simctl bootstatus "$simulator_id" -b 2>&1 | tee -a "$log"

# Hand the VM system back what the previous phase is still holding, and record
# what the pass actually starts with.
#
# This is diagnostic first. It was added on the theory that the failure was
# positional - the first pass dying on a machine still carrying a 19-minute
# Swift compile - and it disproved that theory: with `purge` in front of it the
# first pass started with 4.0 GB free and 680 MB compressed, against the 65-83
# MB free the unsplit runs showed, and still failed. So the printed counts are
# the point. They are what turns "the runner ran out of memory" from an
# inference into a reading, and they are what caught the wrong theory. `purge`
# itself is advisory and costs seconds, so it stays.
reclaim_memory() {
    sudo /usr/sbin/purge 2>/dev/null || /usr/sbin/purge 2>/dev/null || true
}

memory_counters() {
    vm_stat | awk '/Pages free|occupied by compressor/ {print "    " $0}'
}

# Every pass runs even when an earlier one fails, so one broken suite reports
# its own failure instead of hiding every later suite's result behind it.
failed_passes=()
executed_total=0

# Each pass file is that pass's `xcodebuild` argument list, one per line: the
# `-only-testing:` or `-skip-testing:` selectors, and for an isolated pass the
# `-parallel-testing-enabled NO` that keeps its render peaks from stacking.
for pass in $(seq 1 "$total_passes"); do
    args=()
    expected_suites=()
    while IFS= read -r line; do
        [ -n "$line" ] && args+=("$line")
        case "$line" in
            -only-testing:*) expected_suites+=("${line#-only-testing:}") ;;
        esac
    done < "$log_dir/test-pass-$pass.txt"

    echo "--- Test pass $pass of $total_passes ---" | tee -a "$log"
    reclaim_memory
    memory_counters | tee -a "$log"

    # Where this pass's slice of the shared log begins, for the in-flight list.
    pass_first_line=$(( $(wc -l < "$log" | tr -d ' ') + 1 ))
    result_bundle="$log_dir/AscendApp-Staging-pass$pass.xcresult"

    # Printed while the host is still alive, which is the only time the memory
    # counters mean anything.
    on_stall="echo '--- Memory at the stall ---'; vm_stat; \
node '$scripts_dir/unfinished-tests.mjs' '$log' '$pass_first_line'"

    # A separate result bundle per pass: `xcodebuild` refuses to write over an
    # existing one, and the upload step takes the whole directory anyway.
    if "$scripts_dir/run-with-silence-watchdog.sh" \
        --silence "$silence_limit_seconds" \
        --log "$log" \
        --on-stall "$on_stall" \
        --progress-pattern "$progress_pattern" \
        -- xcodebuild "${common[@]}" "${test_timeouts[@]}" \
        -resultBundlePath "$result_bundle" \
        "${args[@]}" \
        test-without-building; then
        echo "--- Test pass $pass passed ---" | tee -a "$log"
    else
        echo "--- Test pass $pass FAILED ---" | tee -a "$log"
        failed_passes+=("$pass")
    fi

    # A pass that ran nothing is not a pass, whatever `xcodebuild` exited with.
    # The bundle may be missing after a watchdog kill, which is already a
    # failure above and needs no second one.
    if [ -d "$result_bundle" ]; then
        verdict="$log_dir/test-pass-$pass.verdict.txt"
        verdict_status=0
        node "$scripts_dir/verify-test-pass-result.mjs" \
            "$result_bundle" ${expected_suites[@]+"${expected_suites[@]}"} \
            > "$verdict" 2>&1 || verdict_status=$?
        cat "$verdict" | tee -a "$log"
        case "$verdict_status" in
            0) ;;
            1) echo "--- Test pass $pass ran nothing it was told to run ---" | tee -a "$log" ;;
            # A bundle `xcodebuild` never finalised - a killed pass leaves one
            # with no Info.plist - proves nothing either way; the kill is
            # already the failure.
            *) echo "--- Test pass $pass left no readable result bundle ---" | tee -a "$log" ;;
        esac
        if [ "$verdict_status" != "0" ]; then
            case " ${failed_passes[*]-} " in
                *" $pass "*) ;;
                *) failed_passes+=("$pass") ;;
            esac
        fi
        executed="$(sed -n 's/^executed-tests=//p' "$verdict" | tail -1)"
        executed_total=$((executed_total + ${executed:-0}))
        echo "    executed so far: $executed_total" | tee -a "$log"
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

# The floor is the last guard between a pass plan that quietly shrank and a
# green check. It lives beside the plan; move it there, deliberately.
floor="$(node -e "import('$scripts_dir/plan-test-passes.mjs').then((m) => console.log(m.EXECUTED_TEST_FLOOR))")"
echo "--- Executed $executed_total tests across $total_passes passes (floor $floor) ---" | tee -a "$log"

if [ "$executed_total" -lt "$floor" ]; then
    echo "::error::Only $executed_total tests executed across every pass, under the floor of $floor. A suite has fallen out of the plan; see plan-test-passes.mjs."
    exit 1
fi
