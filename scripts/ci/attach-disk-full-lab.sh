#!/bin/bash
#
# Creates and attaches the volume `FirestoreDiskFullSurvivalTests` fills, and
# prints its mount point.
#
# The simulator shares the Mac's volume and cannot fill it, so the suite points
# a dedicated Firestore instance's LevelDB directory into a tiny APFS image and
# fills that instead (`docs/firestore-disk-full-guard.md`). The image lives in a
# fresh `mktemp -d` directory under `$RUNNER_TEMP` (else `$TMPDIR`), so no run
# reuses or deletes another's, nothing is ever cleaned up by a wildcard, and the
# image stays out of `build-logs/`, which CI uploads as an artifact. It is
# attached without a Finder window. The printed path is absolute because the
# test host runs in the simulator with its own working directory.
#
# Usage: mount="$(scripts/ci/attach-disk-full-lab.sh)"; detach with
# `hdiutil detach -force "$mount"`.
set -euo pipefail

lab_root="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ascend-disk-full-lab.XXXXXX")"
image="$lab_root/disk-full-lab.dmg"
mount_point="$lab_root/mount"

hdiutil create -quiet -size 8m -fs APFS -volname AscendDiskFullLab "$image"
mkdir "$mount_point"
hdiutil attach -quiet -nobrowse -mountpoint "$mount_point" "$image"
echo "$mount_point"
