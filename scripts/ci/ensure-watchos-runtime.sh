#!/bin/bash
# Provision the watchOS simulator runtime the retained watch target may need.
#
# Both phone schemes keep the watch target as a build dependency for 1.1 even
# though the 1.0 app no longer embeds its product. Removing that embed phase also
# removed the refusal that made this step a proven hard precondition:
#
#   xcodebuild: error: Failed to build project AscendApp with scheme AscendApp.:
#   This scheme builds an embedded Apple Watch app. watchOS 26.2 must be
#   installed in order to run the scheme
#
# That message keys off an *embedded* watch app, so whether a scheme that only
# builds the watch target as a dependency still demands an installed simulator
# runtime is now unverified - issue #496 records that verification. Until it
# lands this step is best effort: it provisions what it can and warns rather than
# failing, so a runtime that genuinely is required surfaces as Xcode's own
# accurate error instead of a guess made minutes earlier - and a runtime that is
# not required never fails four jobs for a condition the build would tolerate.
#
# When Xcode does want a runtime it wants the one matching the **SDK**, not the
# deployment target, so
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
#
# Every inability here - an uninstalled watchOS platform, a `simctl` or `jq`
# failure, a failed download, no matching runtime afterwards - warns and exits 0.
# There is exactly one authority on whether a build can proceed, and it is
# xcodebuild; a step that cannot even look must not be the thing that decides.

set -euo pipefail

# shellcheck disable=SC2317
warn_and_continue() {
  echo "::warning::$1 Continuing: whether a scheme that builds the retained watch target as a dependency requires a watchOS runtime is unverified (#496), so xcodebuild decides."
  exit 0
}

if ! needed="$(xcrun --show-sdk-version --sdk watchos)" || [ -z "$needed" ]; then
  warn_and_continue "Could not read the watchOS SDK version; the watchOS platform is probably not installed."
fi

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

if ! runtime="$(installed_watchos_runtime)"; then
  warn_and_continue "Could not list the installed simulator runtimes."
fi

if [ -n "$runtime" ]; then
  echo "watchOS ${runtime} runtime already installed for watchOS SDK ${needed}."
else
  echo "No watchOS ${needed_version} runtime for watchOS SDK ${needed}; downloading the one Xcode expects."
  # A failed download still falls through to the diagnostics and the warning below.
  xcodebuild -downloadPlatform watchOS || echo "::warning::Downloading the watchOS runtime failed."

  if ! runtime="$(installed_watchos_runtime)"; then
    warn_and_continue "Could not list the installed simulator runtimes after the download."
  fi
fi

xcrun simctl list runtimes | grep -i watch || true

if [ -z "$runtime" ]; then
  warn_and_continue "No watchOS ${needed_version} runtime is available for watchOS SDK ${needed}."
fi

echo "Resolved watchOS ${runtime} runtime for watchOS SDK ${needed}."
