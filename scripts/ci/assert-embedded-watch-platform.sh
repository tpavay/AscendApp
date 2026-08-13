#!/bin/bash
# Assert that the watch app embedded in a built iOS app bundle is a watchOS
# binary.
#
# PARKED, NOT DEAD. Ascend 1.0 embeds no watch app in any IPA - staging archives
# included - so this guard has no caller and asserts nothing today. It is
# retained for reactivation when 1.1 restores embedding, at which point wire it
# back into `ios-verify-release` and both deploy pipelines. The release split is
# owned by `docs/heart-rate-zones-plan.md`; `ascend-deploy` owns the CI side, and
# `scripts/test/watch-target-configuration.test.mjs` holds the source-side
# platform contract in the meantime.
#
# This failure is invisible without a check. `-sdk <platform>` on an xcodebuild
# command line overrides SDKROOT for *every* target in the build, the watch app
# is embedded regardless of what it was built for, and the build still reports
# `** BUILD SUCCEEDED **`. The first sign of trouble is an App Store Connect
# upload rejection, or a watch app that installs and never launches.
#
# Measured in this repository, Xcode 26.3 / watchOS SDK 26.2, Release,
# `-sdk iphoneos -destination "generic/platform=iOS"`:
#
#   AscendWatch has SUPPORTED_PLATFORMS = "watchos watchsimulator"
#     -> embedded binary is `platform WATCHOS`. The explicit supported-platform
#        list is what refuses the override.
#   the same build with SUPPORTED_PLATFORMS removed from the watch target
#     -> BUILD SUCCEEDED, embedded binary is `platform IOS`.
#
# So two separate things have to hold, and neither is self-announcing: the
# Release job passes no `-sdk` flag, and the watch target keeps its
# SUPPORTED_PLATFORMS. This asserts the outcome rather than either input, so it
# still fires if some future route to a wrong-platform embed is found.
#
# Usage: assert-embedded-watch-platform.sh <path/to/Built.app> [WatchAppName]

set -euo pipefail

app_bundle="${1:-}"
watch_app_name="${2:-AscendWatch}"

if [ -z "$app_bundle" ]; then
  echo "::error::Usage: $0 <path/to/Built.app> [WatchAppName]"
  exit 2
fi

watch_binary="${app_bundle}/Watch/${watch_app_name}.app/${watch_app_name}"

if [ ! -f "$watch_binary" ]; then
  echo "::error::No embedded watch binary at ${watch_binary}. The app bundle must embed ${watch_app_name}.app under Watch/."
  ls -la "${app_bundle}/Watch" 2>&1 || true
  exit 1
fi

build_info="$(vtool -show-build "$watch_binary" 2>&1)"

# Compare the platform token exactly rather than substring-matching the line.
# The platform names nest - IOSSIMULATOR contains IOS, WATCHOSSIMULATOR contains
# WATCHOS - so `grep "platform IOS"` would misread a simulator build either way.
platforms="$(printf '%s\n' "$build_info" | awk '$1 == "platform" {print $2}' | sort -u)"

if [ -z "$platforms" ]; then
  echo "::error::vtool reported no build platform for ${watch_binary}."
  printf '%s\n' "$build_info"
  exit 1
fi

# Every slice has to be watchOS, not just the first one vtool prints. The
# simulator variant is accepted so the same check can guard a simulator build.
while IFS= read -r platform; do
  case "$platform" in
    WATCHOS | WATCHOSSIMULATOR) ;;
    *)
      echo "::error::Embedded watch binary at ${watch_binary} has a slice built for ${platform}. It must be a watchOS binary; check for an -sdk flag on the xcodebuild command and for SUPPORTED_PLATFORMS on the AscendWatch target."
      printf '%s\n' "$build_info"
      exit 1
      ;;
  esac
done <<< "$platforms"

echo "Verified ${watch_binary} is a watchOS binary (${platforms//$'\n'/, })."
printf '%s\n' "$build_info" | grep -E "platform|minos"
