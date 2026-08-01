import assert from "node:assert/strict";
import test from "node:test";

import {
  compareVersionStrings,
  selectVersion,
} from "../lib/phased-release-selection.mjs";

function candidate(versionString, {appStoreState = "READY_FOR_DISTRIBUTION", phasedReleaseState} = {}) {
  return {
    version: {
      id: `version-${versionString}`,
      attributes: {versionString, appStoreState},
    },
    phasedRelease: phasedReleaseState
      ? {id: `phased-${versionString}`, attributes: {phasedReleaseState}}
      : null,
  };
}

test("newest-first ordering is numeric, so 1.10.0 beats 1.9.0", () => {
  const ordered = ["1.9.0", "1.10.0", "1.2.3", "2.0.0"].sort(compareVersionStrings);

  assert.deepEqual(ordered, ["2.0.0", "1.10.0", "1.9.0", "1.2.3"]);
});

test("status picks the newest version regardless of the order the API returned", () => {
  const candidates = [candidate("1.0.0"), candidate("1.10.0"), candidate("1.9.0")];

  const selected = selectVersion(candidates, {command: "status"});

  assert.equal(selected.version.attributes.versionString, "1.10.0");
});

test("pause targets the version whose rollout is actually in flight, not the newest record", () => {
  const candidates = [
    candidate("1.1.0", {appStoreState: "PREPARE_FOR_SUBMISSION"}),
    candidate("1.0.1", {phasedReleaseState: "ACTIVE"}),
    candidate("1.0.0", {phasedReleaseState: "COMPLETE"}),
  ];

  const selected = selectVersion(candidates, {command: "pause"});

  assert.equal(selected.version.attributes.versionString, "1.0.1");
});

test("resume finds a paused rollout", () => {
  const candidates = [candidate("1.0.1", {phasedReleaseState: "PAUSED"}), candidate("1.0.0")];

  const selected = selectVersion(candidates, {command: "resume"});

  assert.equal(selected.version.attributes.versionString, "1.0.1");
});

test("pause refuses rather than reporting success when nothing is rolling out", () => {
  const candidates = [candidate("1.0.0", {phasedReleaseState: "COMPLETE"})];

  assert.throws(
    () => selectVersion(candidates, {command: "pause"}),
    /nothing to `pause`/,
  );
});

test("pause refuses rather than guessing when two rollouts are in flight", () => {
  const candidates = [
    candidate("1.0.1", {phasedReleaseState: "ACTIVE"}),
    candidate("1.0.2", {phasedReleaseState: "PAUSED"}),
  ];

  assert.throws(() => selectVersion(candidates, {command: "pause"}), /--version/);
});

test("an explicit --version wins over every inference", () => {
  const candidates = [
    candidate("1.0.1", {phasedReleaseState: "ACTIVE"}),
    candidate("1.0.2", {phasedReleaseState: "PAUSED"}),
  ];

  const selected = selectVersion(candidates, {
    command: "pause",
    requestedVersionString: "1.0.2",
  });

  assert.equal(selected.version.attributes.versionString, "1.0.2");
});

test("an unknown --version is an error, not a silent fallback to the newest", () => {
  const candidates = [candidate("1.0.1", {phasedReleaseState: "ACTIVE"})];

  assert.throws(
    () => selectVersion(candidates, {command: "pause", requestedVersionString: "9.9.9"}),
    /No iOS App Store version 9\.9\.9/,
  );
});

test("an empty version list is an error", () => {
  assert.throws(() => selectVersion([], {command: "status"}), /No iOS App Store version/);
});

test("duplicate newest records refuse rather than picking one", () => {
  const candidates = [candidate("1.0.1"), candidate("1.0.1")];

  assert.throws(() => selectVersion(candidates, {command: "enable"}), /--version/);
});
