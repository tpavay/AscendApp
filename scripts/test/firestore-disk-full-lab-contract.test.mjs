/**
 * The disk-full laboratory contract.
 *
 * `FirestoreDiskFullSurvivalTests` is the regression test for the 2026-10-23
 * production crash: Firestore's `LevelDbTransaction::Commit()` aborting the
 * process on a volume with no free blocks. It needs a volume it can fill, which
 * the simulator cannot provide (it shares the Mac's), so the CI runner attaches
 * a tiny APFS image through `scripts/ci/attach-disk-full-lab.sh` and hands its
 * mount point to the test host.
 *
 * Two things are held here. The attach step, run for real, has to produce a
 * mounted, writable, 8 MB APFS volume at a fresh absolute path per run, outside
 * the `build-logs/` directory CI uploads, attached without a Finder window. And
 * the pass planner has to name the suite, so a suite that skipped itself (no
 * mount) fails its pass instead of counting as green - which is also what
 * catches the runner and the Swift lab disagreeing about the variable.
 */

import assert from "node:assert/strict";
import {execFileSync} from "node:child_process";
import {mkdtempSync, realpathSync, rmSync, statfsSync, writeFileSync} from "node:fs";
import {tmpdir} from "node:os";
import {isAbsolute, join} from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";

import {ISOLATED_PASSES} from "../ci/plan-test-passes.mjs";

const ATTACH_SCRIPT = fileURLToPath(new URL("../ci/attach-disk-full-lab.sh", import.meta.url));
const SUITE_NAME = "FirestoreDiskFullSurvivalTests";
const IMAGE_BYTES = 8 * 1024 * 1024;

function mountTableEntry(mountPoint) {
  const resolved = realpathSync(mountPoint);
  return execFileSync("mount", {encoding: "utf8"})
    .split("\n")
    .find((line) => line.includes(` on ${resolved} (`));
}

test(
  "the attach step mounts a fresh, writable 8 MB APFS volume outside the uploaded logs",
  {skip: process.platform !== "darwin" && "hdiutil is macOS-only"},
  () => {
    const runnerTemp = mkdtempSync(join(tmpdir(), "disk-full-lab-contract-"));
    const mounts = [];
    try {
      for (let run = 0; run < 2; run += 1) {
        mounts.push(
          execFileSync(ATTACH_SCRIPT, {env: {...process.env, RUNNER_TEMP: runnerTemp}, encoding: "utf8"}).trim(),
        );
      }

      assert.notEqual(mounts[0], mounts[1], "every run gets a path of its own");
      for (const mount of mounts) {
        assert.ok(isAbsolute(mount), `the test host has its own working directory, so ${mount} must be absolute`);
        assert.ok(
          realpathSync(mount).startsWith(realpathSync(runnerTemp)),
          `${mount} lives under RUNNER_TEMP, not in the uploaded build-logs/`,
        );

        const entry = mountTableEntry(mount);
        assert.ok(entry, `${mount} is mounted`);
        assert.match(entry, /\(apfs,/, "the volume is APFS");
        assert.match(entry, /nobrowse/, "attached without a Finder window");

        const stats = statfsSync(mount);
        const total = stats.blocks * stats.bsize;
        assert.ok(total > 0 && total <= IMAGE_BYTES, `the volume is the 8 MB image, not the host's (${total} bytes)`);
        assert.ok(stats.bavail > 0, "the volume starts with room for Firestore's directory");
        writeFileSync(join(mount, "probe"), "x");
      }
    } finally {
      for (const mount of mounts) {
        execFileSync("hdiutil", ["detach", "-quiet", "-force", mount]);
      }
      rmSync(runnerTemp, {recursive: true, force: true});
    }
  },
);

test("the planner names the suite in a pass of its own, so a skipped suite fails its pass", () => {
  assert.deepEqual(
    ISOLATED_PASSES.find((group) => group.includes(SUITE_NAME)),
    [SUITE_NAME],
    `${SUITE_NAME} must be a named pass that rides alone: the post-pass check fails a named suite that ` +
      "executed nothing, and a regression aborts its host, so the kill must name only this suite",
  );
});
