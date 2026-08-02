import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
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

test("Remote Config is not published by any automated deploy", () => {
  // The invariant is behavioural, not syntactic: no CI workflow may publish the template by
  // *any* route, because a publish is a full replace that silently re-enables a kill switch
  // an operator had just turned off. Reading the live template is fine and is exactly what
  // the archive preflight does, so this cannot be a check on the mere appearance of the word.
  //
  // Three routes reach a publish, and all three are closed here:
  //   1. a `firebase deploy` whose --only list names remoteconfig, quoted or not;
  //   2. a `firebase deploy` with no --only at all - firebase.json wires the template in, so
  //      an unscoped deploy publishes it;
  //   3. the repository's own publish path, whether invoked through an npm alias or by
  //      running the script directly.
  //
  // Every workflow is read, not a named few: a publish added to a workflow nobody thought to
  // list is exactly as damaging as one added to a deploy, and the directory is the only
  // enumeration that cannot go stale.
  const publishScriptFile = "deploy-remote-config.mjs";
  const publishAliases = Object.entries(repositoryJSON("scripts/package.json").scripts)
    .filter(([, command]) => command.includes(publishScriptFile))
    .map(([alias]) => alias);

  assert.ok(
    publishAliases.length > 0,
    `no npm alias runs ${publishScriptFile} - if it was renamed, rename it here too rather ` +
      "than leaving this test asserting nothing",
  );

  const workflowsDirectory = new URL("../../.github/workflows/", import.meta.url);
  const workflowFiles = readdirSync(workflowsDirectory)
    .filter((name) => /\.ya?ml$/.test(name))
    .sort();

  assert.ok(workflowFiles.length > 0, "found no workflow files to check");

  for (const workflow of workflowFiles) {
    const contents = readFileSync(new URL(workflow, workflowsDirectory), "utf8");

    assert.ok(
      !contents.includes(publishScriptFile),
      `${workflow} must not run ${publishScriptFile} - publishing is a manual human act, by ` +
        "design, precisely so it cannot clobber an active kill switch on a release",
    );

    for (const alias of publishAliases) {
      assert.ok(
        !contents.includes(alias),
        `${workflow} must not run the ${alias} npm alias - it publishes the template, which is ` +
          "a full replace",
      );
    }

    const deployCommands = contents
      .split("\n")
      .filter((line) => /\bfirebase(-tools@\S+)?\s+deploy\b/.test(line));

    // Scoped to the workflows whose job *is* deploying, so the assertions above cannot pass
    // vacuously if the deploy steps are ever restructured - while a workflow that legitimately
    // deploys nothing is still checked for publishes.
    if (workflow === "deploy-staging.yml" || workflow === "deploy-production.yml") {
      assert.ok(deployCommands.length > 0, `${workflow} should still deploy something`);
    }

    for (const command of deployCommands) {
      const only = command.match(/--only\s+("[^"]*"|'[^']*'|\S+)/);

      assert.ok(
        only,
        `${workflow} runs a deploy with no --only list: ${command.trim()} - firebase.json wires ` +
          "remoteconfig in, so an unscoped deploy publishes the template",
      );

      const targets = only[1].replaceAll(/["']/g, "").split(",");

      assert.ok(
        !targets.includes("remoteconfig"),
        `${workflow} must not deploy remoteconfig - publishing is a full replace and would ` +
          "silently re-enable an active kill switch",
      );
    }
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
      public_profile_publishing_enabled: { defaultValue: { value: "true" } },
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
  const live = {
    parameters: {
      existing_flag_enabled: { valueType: "BOOLEAN", defaultValue: { value: "true" } },
    },
  };

  const problems = unpublishedFlagProblems(live, [
    "existing_flag_enabled",
    "brand_new_flag_enabled",
  ]);

  assert.equal(problems.length, 1);
  assert.match(problems[0], /brand_new_flag_enabled is missing from the live template/);
});

test("a parameter published with the wrong declared type is refused", () => {
  // Not because the client would ignore it - it reads `stringValue` and never inspects
  // `valueType`, so a STRING "false" is honoured as a live kill switch. The template
  // declares BOOLEAN, and the declaration is what keeps a value the client's strict parser
  // would drop from ever being saved here. Erring toward blocking a working config is the
  // safe direction; the opposite is what #318 was.
  const live = {
    parameters: { a_flag_enabled: { valueType: "STRING", defaultValue: { value: "true" } } },
  };

  const problems = unpublishedFlagProblems(live, ["a_flag_enabled"]);

  assert.equal(problems.length, 1);
  assert.match(problems[0], /published as STRING, not the BOOLEAN the template declares/);
});

test("a parameter set to use the in-app default is as unreachable as a missing one", () => {
  // A normal console option, and the most deceptive shape of all: the key is right there in
  // Remote Config, but the backend supplies nothing, `RemoteConfigValue.source` stays
  // `.static`, and the flag resolves from `shippedDefault`.
  const live = {
    parameters: {
      a_flag_enabled: { valueType: "BOOLEAN", defaultValue: { useInAppDefault: true } },
    },
  };

  const problems = unpublishedFlagProblems(live, ["a_flag_enabled"]);

  assert.equal(problems.length, 1);
  assert.match(problems[0], /use in-app default/);
});

test("a parameter carrying only conditional values is reported as unreachable", () => {
  // A client matching no condition receives nothing, so the switch is live for some devices
  // and decorative for the rest - which is not a lever anyone can rely on mid-incident.
  const live = {
    parameters: {
      a_flag_enabled: {
        valueType: "BOOLEAN",
        conditionalValues: { "iOS internal": { value: "false" } },
      },
    },
  };

  const problems = unpublishedFlagProblems(live, ["a_flag_enabled"]);

  assert.equal(problems.length, 1);
  assert.match(problems[0], /only conditional values and no default value/);
});

test("a parameter with no value of any kind is reported as unreachable", () => {
  const live = { parameters: { a_flag_enabled: { valueType: "BOOLEAN" } } };

  const problems = unpublishedFlagProblems(live, ["a_flag_enabled"]);

  assert.equal(problems.length, 1);
  assert.match(problems[0], /no default value/);
});

test("a result-wrapped live template is unwrapped before the published check", () => {
  const appKeys = appFlagKeys(flagSource);

  assert.deepEqual(unpublishedFlagProblems({ result: localTemplate }, appKeys), []);
});

test("parameters the app does not know about are ignored", () => {
  // The backend is allowed to carry keys for other app versions.
  const live = {
    parameters: {
      a_flag_enabled: { valueType: "BOOLEAN", defaultValue: { value: "true" } },
      some_future_flag_enabled: { valueType: "BOOLEAN", defaultValue: { useInAppDefault: true } },
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
