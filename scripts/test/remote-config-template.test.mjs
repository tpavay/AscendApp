import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  findActiveKillSwitches,
  isParameterOff,
  templateParameters,
} from "../lib/remote-config-template.mjs";

function repositoryJSON(path) {
  return JSON.parse(readFileSync(new URL(`../../${path}`, import.meta.url), "utf8"));
}

const localTemplate = repositoryJSON("remoteconfig.template.json");

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
  for (const workflow of ["deploy-staging.yml", "deploy-production.yml"]) {
    const contents = readFileSync(
      new URL(`../../.github/workflows/${workflow}`, import.meta.url),
      "utf8",
    );
    assert.ok(
      !contents.includes("remoteconfig"),
      `${workflow} must not deploy remoteconfig`,
    );
  }
});

test("the template carries exactly the flags the app knows about", () => {
  // A flag the app reads but the template does not carry is a switch that cannot be
  // flipped; a parameter the app does not read is a switch that does nothing.
  const source = readFileSync(
    new URL(
      "../../AscendApp/Shared/Services/RemoteConfig/RemoteFeatureFlag.swift",
      import.meta.url,
    ),
    "utf8",
  );
  const appKeys = [...source.matchAll(/^\s*case\s+\w+\s*=\s*"([a-z0-9_]+)"/gm)]
    .map((match) => match[1])
    .sort();

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
