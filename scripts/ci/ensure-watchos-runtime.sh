#!/bin/bash
# Provision the watchOS simulator runtime a scheme embedding a watch app needs.
#
# This is a hard precondition, not an optimisation. Any scheme that embeds an
# Apple Watch app refuses to build at all without it, whatever the destination:
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
# The runtime is named by major.minor, and a runtime whose patch differs still
# satisfies the scheme, so compare on the major version the SDK reports.
needed_major="${needed%%.*}"

if xcrun simctl list runtimes | grep -q "watchOS ${needed_major}"; then
  echo "watchOS ${needed_major} runtime already installed for watchOS SDK ${needed}."
else
  echo "No watchOS ${needed_major} runtime for watchOS SDK ${needed}; downloading the one Xcode expects."
  xcodebuild -downloadPlatform watchOS
fi

xcrun simctl list runtimes | grep -i watch

if ! xcrun simctl list runtimes | grep -q "watchOS ${needed_major}"; then
  echo "::error::No watchOS ${needed_major} runtime is available, so any scheme embedding the watch app will refuse to build."
  exit 1
fi
