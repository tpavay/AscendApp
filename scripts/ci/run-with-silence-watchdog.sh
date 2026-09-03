#!/bin/bash
#
# Runs a command, appending its output to a log, and kills it when the log has
# not grown for a given number of seconds while the command is still alive.
#
# WHY: a test host that has exhausted the runner's memory does not crash, it
# stops. Job 100425139180 (2026-09-02) wrote its last test result at 21:44:10
# and was killed by the job cap at 21:53:57; job 100448384458 went quiet at
# 23:01:08 and was killed at 23:30:18. Both concluded `cancelled`, which is
# what GitHub reports for a job-level `timeout-minutes`, and neither named a
# test. Total output silence with the process alive is the signature, so
# silence is what this watches for - a healthy pass on the same job never went
# more than 96 seconds without a line (the launch phase of pass 3 on job
# 100376172708), and the wedged ones went 10 to 29 minutes.
#
# The kill lands on the command's whole process group: `xcodebuild` runs the
# host and the simulator bridge as children, and terminating the parent alone
# leaves them holding the log open. `set -m` is what gives the background job a
# group of its own under the runner's bash 3.2. SIGTERM first, so `xcodebuild`
# can finalise its result bundle, SIGKILL after a grace period so a bridge that
# ignores it cannot keep the step alive.
#
# Silence is measured on progress, not on bytes. With `--progress-pattern`,
# a line is progress only if it matches; anything else is noise. A wedged test
# host keeps logging - Firestore watch streams reconnecting, `nw_connection`
# timeouts, WebKit process bookkeeping - every minute or two, and a watchdog
# that counted those lines slept through a 448 s stall in which no test
# started or finished (local run, 2026-09-03). Until the first matching line
# any output counts, because the launch phase before the first test event is
# legitimately silent on progress for up to 132 s on the runner and longer
# when the simulator still has to boot.
#
# `--on-stall <command>` runs BEFORE the kill, while the process is still
# there to be inspected: memory counters and an in-flight test list mean
# nothing once the host is gone.
#
# Usage:
#   run-with-silence-watchdog.sh --silence <seconds> --log <path> \
#       [--progress-pattern <grep -E regex>] [--on-stall <command>] \
#       [--poll <seconds>] [--grace <seconds>] -- <command> [args...]
#
# Exit status: the command's own when it finishes on its own, 124 when the
# watchdog killed it.
#
# Note on `first_line`: the log is shared across passes and appended to, so
# progress is counted only from the line where this invocation began.
set -uo pipefail

silence=""
log=""
on_stall=""
progress_pattern=""
poll=10
grace=30

while [ "$#" -gt 0 ]; do
    case "$1" in
        --silence) silence="$2"; shift 2 ;;
        --log) log="$2"; shift 2 ;;
        --on-stall) on_stall="$2"; shift 2 ;;
        --progress-pattern) progress_pattern="$2"; shift 2 ;;
        --poll) poll="$2"; shift 2 ;;
        --grace) grace="$2"; shift 2 ;;
        --) shift; break ;;
        *)
            echo "run-with-silence-watchdog.sh: unknown option $1" >&2
            exit 2
            ;;
    esac
done

if [ -z "$silence" ] || [ -z "$log" ] || [ "$#" -eq 0 ]; then
    echo "usage: run-with-silence-watchdog.sh --silence <seconds> --log <path> [--on-stall <command>] -- <command> [args...]" >&2
    exit 2
fi

mkdir -p "$(dirname "$log")"
touch "$log"

log_size() {
    stat -f %z "$log" 2>/dev/null || echo 0
}

# Progress lines written since this watchdog started; the log may already
# hold earlier passes' output above `first_line`.
progress_count() {
    if [ -z "$progress_pattern" ]; then
        echo 0
        return
    fi
    tail -n "+$first_line" "$log" | grep -cE "$progress_pattern" || true
}

# Recorded before the command starts, or a progress line written in the first
# instant would be counted as an earlier pass's.
first_line=$(( $(wc -l < "$log" | tr -d ' ') + 1 ))
last_size="$(log_size)"

# Monitor mode puts the background pipeline in its own process group, which is
# the only handle that reaches every process the command spawned.
set -m
( "$@" 2>&1 | tee -a "$log" ) &
job=$!
set +m

group="$(ps -o pgid= -p "$job" | tr -d ' ')"
last_progress=0
quiet=0

while kill -0 "$job" 2>/dev/null; do
    sleep "$poll"

    if ! kill -0 "$job" 2>/dev/null; then
        break
    fi

    size="$(log_size)"
    progress="$(progress_count)"

    if [ "$progress" -gt "$last_progress" ]; then
        last_progress="$progress"
        last_size="$size"
        quiet=0
        continue
    fi

    # Before the first progress line, any output at all is taken as liveness.
    if [ "$last_progress" -eq 0 ] && [ "$size" != "$last_size" ]; then
        last_size="$size"
        quiet=0
        continue
    fi

    quiet=$((quiet + poll))

    if [ "$quiet" -lt "$silence" ]; then
        continue
    fi

    if [ "$last_progress" -gt 0 ]; then
        echo "::error::No test progress for ${quiet}s while the command is still running (${last_progress} progress lines so far); treating it as wedged and killing it."
    else
        echo "::error::No output for ${quiet}s while the command is still running; treating it as wedged and killing it."
    fi

    if [ -n "$on_stall" ]; then
        # The stall hook is diagnostics; its failure must not mask the stall.
        bash -c "$on_stall" || true
    fi

    kill -TERM -- "-$group" 2>/dev/null || kill -TERM "$job" 2>/dev/null || true

    waited=0
    while kill -0 "$job" 2>/dev/null && [ "$waited" -lt "$grace" ]; do
        sleep 1
        waited=$((waited + 1))
    done

    if kill -0 "$job" 2>/dev/null; then
        kill -KILL -- "-$group" 2>/dev/null || kill -KILL "$job" 2>/dev/null || true
    fi

    wait "$job" 2>/dev/null
    exit 124
done

wait "$job"
