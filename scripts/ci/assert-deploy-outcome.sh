#!/usr/bin/env bash
#
# Turns a deploy run that did not deploy into a failed one.
#
# GitHub emails on `failure` and says nothing at all about `cancelled`, so a
# deploy run that stops half-way - by hand, by timeout, or by losing its
# concurrency slot after it started - is silent unless something converts it.
# A final job with `if: always()` runs this, and its exit code becomes the
# run's conclusion.
#
# It cannot save a run cancelled while still queued, because such a run never
# creates a job at all. `deploy-production-watchdog.yml` covers that from
# outside the pipeline.
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
  echo "::error::This deploy did not reach production. Failing the run so GitHub sends the notification a cancelled run never would."
  exit 1
fi

echo "Deploy completed: every stage succeeded for ${commit}."
