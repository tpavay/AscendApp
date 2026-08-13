#!/bin/bash
# Provision the watchOS simulator runtime the retained watch target needs.
#
# This is a hard precondition, not an optimization. Both phone schemes keep the
# watch target as a build dependency for 1.1 even though the 1.0 app does not
# embed its product. Xcode refuses to build the scheme without the runtime:
#
#   xcodebuild: error: Failed to build project AscendApp with scheme AscendApp.:
#   This scheme builds an embedded Apple Watch app. watchOS 26.2 must be
#   installed in order to run the scheme
#
# Xcode wants the runtime matching the **SDK**, not the deployment target, so
# lowering WATCHOS_DEPLOYMENT_TARGET does not help and neither does dropping the
# destination flag. The runner image decides which runtimes it ships and that set
# changes without notice - GitHub keeps runtimes only for the three most recently
# installed Xcodes, and the jobs pin `xcode-version: latest-stable`, so the
# required version moves whenever the runner's Xcode moves. Treating the image as
# the source of truth makes every PR fail the day it changes; provision instead.
#
# Written in the defensive style of the `Select simulator` step: check what is
# installed, download only when it is missing, and print what was resolved.
# A cold download is several minutes and about 4 GB.

set -euo pipefail

needed="$(xcrun --show-sdk-version --sdk watchos)"
# The runtime is named by major.minor. A runtime whose patch differs still
# satisfies the scheme; a runtime whose minor differs does not - a watchOS 26.0
# runtime against an SDK 26.2 scheme produces exactly the refusal above - so
# compare on the two leading components rather than the major alone.
needed_version="$(printf '%s' "$needed" | cut -d. -f1,2)"

# Matched on the parsed runtime list rather than a substring grep: the plain
# listing also carries entries suffixed `(unavailable, ...)`, which read as
# installed while offering nothing to build against.
installed_watchos_runtime() {
  xcrun simctl list runtimes -j | jq -r --arg needed "$needed_version" '
    [.runtimes[]
      | select(.isAvailable and (.identifier | startswith("com.apple.CoreSimulator.SimRuntime.watchOS-")))
      | select((.version | split(".") | .[0:2] | join(".")) == $needed)]
    | sort_by(.version | split(".") | map(tonumber))
    | last | .version // empty
  '
}

runtime="$(installed_watchos_runtime)"

if [ -n "$runtime" ]; then
  echo "watchOS ${runtime} runtime already installed for watchOS SDK ${needed}."
else
  echo "No watchOS ${needed_version} runtime for watchOS SDK ${needed}; downloading the one Xcode expects."
  # A failed download still falls through to the diagnostics and the error below.
  xcodebuild -downloadPlatform watchOS || echo "::warning::Downloading the watchOS runtime failed."
  runtime="$(installed_watchos_runtime)"
fi

xcrun simctl list runtimes | grep -i watch || true

if [ -z "$runtime" ]; then
  echo "::error::No watchOS ${needed_version} runtime is available, so any scheme building the retained watch target will refuse to build."
  exit 1
fi

echo "Resolved watchOS ${runtime} runtime for watchOS SDK ${needed}."
