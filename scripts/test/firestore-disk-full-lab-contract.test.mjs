/**
 * The disk-full laboratory contract.
 *
 * `FirestoreDiskFullSurvivalTests` is the regression test for the 2026-10-23
 * production crash: Firestore's `LevelDbTransaction::Commit()` aborting the
 * process on a volume with no free blocks. It needs a volume it can fill, which
 * the simulator cannot provide (it shares the Mac's), so the CI runner creates
 * a tiny APFS image and hands its mount point to the test host. Three things
 * have to agree for the suite to actually run on CI, and nothing in Xcode can
 * notice when they stop agreeing:
 *
 * - the runner script creates and attaches the image and exports the mount under
 *   the `TEST_RUNNER_` prefix `xcodebuild` strips,
 * - the Swift suite reads exactly the stripped key, and
 * - the pass planner names the suite, so a suite that skipped itself (no mount)
 *   fails its pass instead of counting as green.
 *
 * The image also has to be a fresh path per run, attached without a Finder
 * window, and never cleaned up by a wildcard delete: the home's rules forbid
 * `rm -rf` outright, and a `-nobrowse` attach is what keeps a window off the
 * captain's screen on a developer machine.
 */

import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {join} from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";

import {ISOLATED_PASSES} from "../ci/plan-test-passes.mjs";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));

const RUNNER_PATH = "scripts/ci/run-ios-test-passes.sh";
const LAB_PATH = "AscendAppTests/FirestoreDiskFullLab.swift";
const SUITE_PATH = "AscendAppTests/FirestoreDiskFullSurvivalTests.swift";
const SUITE_NAME = "FirestoreDiskFullSurvivalTests";

// What the test host sees. `xcodebuild` strips `TEST_RUNNER_` from the runner's
// environment, so the script exports the prefixed name and Swift reads the bare one.
const HOST_KEY = "ASCEND_DISKFULL_MOUNT";
const RUNNER_KEY = `TEST_RUNNER_${HOST_KEY}`;

async function read(relativePath) {
  return readFile(join(repositoryRoot, relativePath), "utf8");
}

test("the runner creates a fresh APFS image per run, attaches it without a window, and exports its mount", async () => {
  const runner = await read(RUNNER_PATH);

  assert.match(runner, /hdiutil create -quiet -size 8m -fs APFS[^\n]*\$disk_full_lab_image/, "an 8 MB APFS image");
  assert.match(
    runner,
    /disk_full_lab_stamp="\$\(date \+%s\)-\$\$"/,
    "the image path carries the run's time and pid, so no run ever reuses or deletes another's"
  );
  assert.match(runner, /hdiutil attach -quiet -nobrowse -mountpoint "\$disk_full_lab_mount"/, "attached with -nobrowse");
  assert.match(
    runner,
    /disk_full_lab_mount="\$PWD\/\$log_dir\//,
    "the mount is absolute: the test host has its own working directory and cannot resolve the runner's relative path"
  );
  assert.match(runner, new RegExp(`export ${RUNNER_KEY}="\\$disk_full_lab_mount"`), `exports ${RUNNER_KEY}`);
  assert.match(runner, /trap detach_disk_full_lab EXIT/, "detaches the image when the script ends, however it ends");
});

test("the image is attached before the first test pass runs", async () => {
  const runner = await read(RUNNER_PATH);
  const attachAt = runner.indexOf(`export ${RUNNER_KEY}=`);
  const firstPassAt = runner.indexOf("test-without-building");

  assert.ok(attachAt > 0, "the export exists");
  assert.ok(firstPassAt > attachAt, "the mount is exported before any pass executes");
});

test("the runner never reaches for rm -rf", async () => {
  const runner = await read(RUNNER_PATH);

  assert.doesNotMatch(runner, /rm -rf/, "a wildcard delete is forbidden in this home; fresh paths replace cleanup");
});

test("the Swift lab reads exactly the key the runner exports, minus the prefix xcodebuild strips", async () => {
  const lab = await read(LAB_PATH);

  assert.match(lab, new RegExp(`static let mountEnvironmentKey = "${HOST_KEY}"`));
  assert.doesNotMatch(lab, new RegExp(RUNNER_KEY), "the test host never sees the TEST_RUNNER_ prefix");
});

test("the suite skips itself without the mount and the planner names it, so a skipped suite fails its pass", async () => {
  const suite = await read(SUITE_PATH);

  assert.match(suite, /\.disabled\(\s*if: FirestoreDiskFullLab\.mountPoint == nil/, "the suite is disabled, not silently green, without the image");
  assert.ok(
    ISOLATED_PASSES.some((group) => group.includes(SUITE_NAME)),
    `${SUITE_NAME} must be a named pass: the post-pass check fails a named suite that executed nothing`
  );
  assert.deepEqual(
    ISOLATED_PASSES.find((group) => group.includes(SUITE_NAME)),
    [SUITE_NAME],
    "the suite rides alone: a regression aborts its host, and the kill must name only this suite"
  );
});
