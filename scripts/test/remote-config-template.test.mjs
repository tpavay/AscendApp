import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  appFlagKeys,
  findActiveKillSwitches,
  isParameterOff,
  templateParameters,
  unpublishedFlagProblems,
} from "../lib/remote-config-template.mjs";

function repositoryJSON(path) {
  return JSON.parse(readFileSync(new URL(`../../${path}`, import.meta.url), "utf8"));
}

function repositoryText(path) {
  return readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
}

const localTemplate = repositoryJSON("remoteconfig.template.json");
const flagSource = repositoryText(
  "AscendApp/Shared/Services/RemoteConfig/RemoteFeatureFlag.swift",
);

test("every checked-in parameter is a boolean that ships on", () => {
  const parameters = templateParameters(localTemplate);
  assert.ok(Object.keys(parameters).length > 0);

  for (const [key, parameter] of Object.entries(parameters)) {
    assert.equal(parameter.valueType, "BOOLEAN", `${key} must be a BOOLEAN parameter`);
    assert.equal(
      parameter.defaultValue?.value,
      "true",
      `${key} must ship on - the checked-in template is the healthy state`,
    );
    assert.ok(parameter.description?.length > 0, `${key} needs a description`);
  }
});

test("the template is wired into firebase.json", () => {
  const firebaseConfig = repositoryJSON("firebase.json");

  assert.equal(firebaseConfig.remoteconfig?.template, "remoteconfig.template.json");
});

test("Remote Config is not part of any automated deploy", () => {
  // Publishing the template is a full replace, so a CI deploy would silently re-enable a
  // kill switch an operator had just turned off.
  //
  // This asserts on the deploy `--only` lists rather than on the mere appearance of the
  // word: the workflows legitimately *read* the live template as an archive preflight
  // (`assert-remote-config-published.mjs`), and a substring check would either forbid that
  // or, worse, pass on the spelling and be believed to mean more than it does.
  for (const workflow of ["deploy-staging.yml", "deploy-production.yml"]) {
    const contents = readFileSync(
      new URL(`../../.github/workflows/${workflow}`, import.meta.url),
      "utf8",
    );

    const deployTargets = [...contents.matchAll(/--only\s+(\S+)/g)].flatMap((match) =>
      match[1].split(","),
    );

    assert.ok(deployTargets.length > 0, `${workflow} should still deploy something`);
    assert.ok(
      !deployTargets.includes("remoteconfig"),
      `${workflow} must not deploy remoteconfig - publishing is a full replace and would ` +
        "silently re-enable an active kill switch",
    );
  }
});

test("the template carries exactly the flags the app knows about", () => {
  // A flag the app reads but the template does not carry is a switch that cannot be
  // flipped; a parameter the app does not read is a switch that does nothing.
  const appKeys = appFlagKeys(flagSource);

  assert.ok(appKeys.length > 0, "could not parse any flag keys out of RemoteFeatureFlag.swift");
  assert.deepEqual(Object.keys(templateParameters(localTemplate)).sort(), appKeys);
});

test("a value of false is recognised as a live kill switch", () => {
  assert.equal(isParameterOff({ defaultValue: { value: "false" } }), true);
  assert.equal(isParameterOff({ defaultValue: { value: "FALSE" } }), true);
  assert.equal(isParameterOff({ defaultValue: { value: " false " } }), true);
});

test("anything not recognisably false is treated as not off", () => {
  assert.equal(isParameterOff({ defaultValue: { value: "true" } }), false);
  assert.equal(isParameterOff({ defaultValue: { value: "" } }), false);
  assert.equal(isParameterOff({}), false);
  assert.equal(isParameterOff(undefined), false);
});

test("a live switch that is off is reported so the deploy can refuse", () => {
  const live = {
    parameters: {
      workout_cloud_backup_writes_enabled: { defaultValue: { value: "false" } },
      leaderboard_publishing_enabled: { defaultValue: { value: "true" } },
    },
  };

  assert.deepEqual(findActiveKillSwitches(live, localTemplate), [
    "workout_cloud_backup_writes_enabled",
  ]);
});

test("a parameter missing from the live project is not mistaken for a kill switch", () => {
  assert.deepEqual(findActiveKillSwitches({ parameters: {} }, localTemplate), []);
});

test("an empty live template is reported as every switch being unreachable", () => {
  // This is #318 exactly, and the reason the gap survived: the checked-in template was
  // right, RemoteFeatureFlag.swift was right, and CI compared those two to each other
  // while all three backends were empty. `{}` is the literal response every project gave
  // on 2026-08-02.
  const appKeys = appFlagKeys(flagSource);
  const problems = unpublishedFlagProblems({}, appKeys);

  assert.equal(problems.length, appKeys.length);
  for (const key of appKeys) {
    assert.ok(
      problems.some((problem) => problem.includes(key)),
      `${key} must be reported as unreachable against an empty backend`,
    );
  }
});

test("a fully published live template raises nothing", () => {
  const appKeys = appFlagKeys(flagSource);

  assert.deepEqual(unpublishedFlagProblems(localTemplate, appKeys), []);
});

test("a switch an operator turned off is the mechanism working, not a problem", () => {
  // The guard must never conflate "deliberately off" with "never published", or it would
  // block the archive precisely when someone is using the lever it exists to protect.
  const live = {
    parameters: Object.fromEntries(
      appFlagKeys(flagSource).map((key) => [
        key,
        { defaultValue: { value: "false" }, valueType: "BOOLEAN" },
      ]),
    ),
  };

  assert.deepEqual(unpublishedFlagProblems(live, appFlagKeys(flagSource)), []);
});

test("a single flag added to the app but never published is caught", () => {
  const live = { parameters: { existing_flag_enabled: { valueType: "BOOLEAN" } } };

  const problems = unpublishedFlagProblems(live, [
    "existing_flag_enabled",
    "brand_new_flag_enabled",
  ]);

  assert.equal(problems.length, 1);
  assert.match(problems[0], /brand_new_flag_enabled is missing from the live template/);
});

test("a published parameter of the wrong type is as unreachable as a missing one", () => {
  // The client parses strictly and treats a non-boolean as absent, so this silently falls
  // back to the shipped default in the same way.
  const live = {
    parameters: { a_flag_enabled: { valueType: "STRING", defaultValue: { value: "true" } } },
  };

  const problems = unpublishedFlagProblems(live, ["a_flag_enabled"]);

  assert.equal(problems.length, 1);
  assert.match(problems[0], /published as STRING, not BOOLEAN/);
});

test("a result-wrapped live template is unwrapped before the published check", () => {
  const appKeys = appFlagKeys(flagSource);

  assert.deepEqual(unpublishedFlagProblems({ result: localTemplate }, appKeys), []);
});

test("parameters the app does not know about are ignored", () => {
  // The backend is allowed to carry keys for other app versions.
  const live = {
    parameters: {
      a_flag_enabled: { valueType: "BOOLEAN" },
      some_future_flag_enabled: { valueType: "BOOLEAN" },
    },
  };

  assert.deepEqual(unpublishedFlagProblems(live, ["a_flag_enabled"]), []);
});

test("flag keys are parsed out of the Swift enum's raw values", () => {
  const keys = appFlagKeys(flagSource);

  assert.ok(keys.includes("workout_cloud_backup_writes_enabled"));
  assert.ok(keys.includes("public_profile_publishing_enabled"));
  assert.deepEqual(keys, [...keys].sort());
});

test("a result-wrapped CLI response is unwrapped", () => {
  const live = {
    result: {
      parameters: {
        public_profile_publishing_enabled: { defaultValue: { value: "false" } },
      },
    },
  };

  assert.deepEqual(findActiveKillSwitches(live, localTemplate), [
    "public_profile_publishing_enabled",
  ]);
});
