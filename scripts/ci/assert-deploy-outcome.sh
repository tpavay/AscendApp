#!/usr/bin/env bash
#
# Turns a deploy run that did not deploy into a failed one.
#
# GitHub emails on `failure` and says nothing at all about `cancelled`. A run
# where a stage was skipped - because an upstream job was skipped, or never
# reached - would otherwise roll up to `success` having deployed nothing. A
# final job with `if: always()` runs this, and a non-zero exit here makes the
# run conclude `failure`, which does send the email.
#
# It cannot rescue a CANCELLED run. Measured on throwaway run 30676439255: the
# run was cancelled mid-flight, the `always()` status job ran and concluded
# `failure`, and the run still concluded `cancelled` - GitHub ranks
# cancellation above a failed job. Cancellation, whether the run was cancelled
# while queued or mid-flight, is carried by `deploy-production-watchdog.yml`
# from outside the pipeline.
#
# Usage:
#   assert-deploy-outcome.sh <gate-result> <ready> <stage>=<result> ...
#
#   gate-result  The gate job's `result`. Anything but `success` fails.
#   ready        The gate's readiness output. When not `true`, every stage must
#                have been `skipped` - a run that claims a clean no-op has to
#                have actually performed one.
#   stage=result A deploy job's name and its `needs.<job>.result`.
#
# Optional env: DEPLOY_COMMIT, named in the failure annotation.

set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "::error::assert-deploy-outcome.sh needs a gate result, a readiness flag, and at least one stage." >&2
  exit 2
fi

gate_result="$1"
ready="$2"
shift 2

commit="${DEPLOY_COMMIT:-this commit}"
failed=0

echo "gate=${gate_result} ready=${ready}"
for pair in "$@"; do
  echo "${pair%%=*}=${pair#*=}"
done

if [ "$gate_result" != "success" ]; then
  echo "::error::The deploy gate concluded '${gate_result}'."
  failed=1
# Currently unreachable: production-gate exits 1 whenever PRODUCTION_READY is
# not "true", so gate_result cannot be "success" while ready is anything else.
# Kept as the correct behaviour if that exit is ever relaxed - but its tests
# are not live coverage of gate-off behaviour.
elif [ "$ready" != "true" ]; then
  for pair in "$@"; do
    stage="${pair%%=*}"
    result="${pair#*=}"
    if [ "$result" != "skipped" ]; then
      echo "::error::The gate is off but ${stage} concluded '${result}' rather than being skipped."
      failed=1
    fi
  done
  if [ "$failed" -eq 0 ]; then
    echo "::notice::The deploy gate is off; nothing was deployed, by design."
  fi
else
  for pair in "$@"; do
    stage="${pair%%=*}"
    result="${pair#*=}"
    if [ "$result" != "success" ]; then
      echo "::error::${stage} concluded '${result}'. Production did not receive ${commit}."
      failed=1
    fi
  done
fi

if [ "$failed" -eq 1 ]; then
  echo "::error::This deploy did not reach production. Failing the run so GitHub sends a notification instead of rolling an empty deploy up into a green run."
  exit 1
fi

echo "Deploy completed: every stage succeeded for ${commit}."
