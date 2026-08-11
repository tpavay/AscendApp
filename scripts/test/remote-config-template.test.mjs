import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import test from "node:test";

import {
  APP_PARAMETER_SOURCE_PATHS,
  SETTING_PARAMETERS,
  appFlagKeys,
  findActiveKillSwitches,
  findArmedSettings,
  flagParityProblems,
  isMonotonicSetting,
  isParameterOff,
  isSettingParameter,
  overrideRecoveryStep,
  templateParameters,
  templateShapeProblems,
  templateVersionNumber,
  unpublishedFlagProblems,
} from "../lib/remote-config-template.mjs";

function repositoryJSON(path) {
  return JSON.parse(readFileSync(new URL(`../../${path}`, import.meta.url), "utf8"));
}

function repositoryText(path) {
  return readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
}

const localTemplate = repositoryJSON("remoteconfig.template.json");

// Resolved through the shared constant rather than by repeating the paths, so a third enum added
// there flows into every parity assertion below instead of being wired into some call sites and
// missed by others - which is the drift the constant exists to prevent.
const parameterSourceByFileName = new Map(
  APP_PARAMETER_SOURCE_PATHS.map((path) => [path.split("/").pop(), repositoryText(path)]),
);
const everyParameterSource = [...parameterSourceByFileName.values()].join("\n");

function parameterSource(fileName) {
  const source = parameterSourceByFileName.get(fileName);
  assert.ok(source, `${fileName} is not listed in APP_PARAMETER_SOURCE_PATHS`);
  return source;
}

// A live project in the healthy state: exactly what publishing the checked-in template produces,
// which is the baseline `findArmedSettings` compares against.
function liveTemplateMatchingCheckedIn() {
  return structuredClone({ parameters: templateParameters(localTemplate) });
}

const flagSource = parameterSource("RemoteFeatureFlag.swift");
const settingSource = parameterSource("RemoteConfigSetting.swift");
const appVersionSource = parameterSource("RemoteAppVersionParameter.swift");

test("every checked-in parameter ships in its healthy shape", () => {
  assert.ok(Object.keys(templateParameters(localTemplate)).length > 0);
  assert.deepEqual(templateShapeProblems(localTemplate), []);
});

test("a malformed checked-in parameter is reported by shape", () => {
  const problems = templateShapeProblems({
    parameters: {
      a_flag_enabled: {valueType: "STRING", defaultValue: {value: "false"}},
    },
  });

  assert.equal(problems.length, 3);
  assert.ok(problems.some((problem) => /must be declared BOOLEAN/.test(problem)));
  assert.ok(problems.some((problem) => /must ship on/.test(problem)));
  assert.ok(problems.some((problem) => /needs a description/.test(problem)));
});

test("the template is wired into firebase.json", () => {
  const firebaseConfig = repositoryJSON("firebase.json");

  assert.equal(firebaseConfig.remoteconfig?.template, "remoteconfig.template.json");
});

test("no automated deploy full-replaces the Remote Config template", () => {
  // The invariant is behavioural, not syntactic: no CI workflow may replace the live template
  // wholesale, because that silently re-enables a kill switch an operator had just turned off.
  // Reading the live template is fine and is exactly what the archive preflight does, so this
  // cannot be a check on the mere appearance of the word.
  //
  // Three routes reach a full replace, and all three are closed here:
  //   1. a `firebase deploy` whose --only list names remoteconfig, quoted or not;
  //   2. a `firebase deploy` with no --only at all - firebase.json wires the template in, so
  //      an unscoped deploy publishes it;
  //   3. the repository's own full-replace publish path, whether invoked through an npm alias
  //      or by running the script directly.
  //
  // What IS allowed in a workflow is the additive publisher, which builds its payload from the
  // live template and can only ever add a parameter the project has never held - see
  // `remote-config-publish.test.mjs`, which pins that guarantee against the merge itself
  // rather than against a filename. Its production form stays out of every workflow: the
  // additive argument makes it safe, but widening what automation touches in production is a
  // separate decision nobody has made.
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

test("the template carries exactly the parameters the app knows about", () => {
  // A parameter the app reads but the template does not carry is a lever that cannot be
  // pulled; a parameter the app does not read is a lever that moves nothing. Settings live in
  // their own enum but are held to the same parity contract.
  const appKeys = appFlagKeys(everyParameterSource);

  assert.ok(appKeys.length > 0, "could not parse any keys out of the RemoteConfig enums");
  assert.deepEqual(Object.keys(templateParameters(localTemplate)).sort(), appKeys);
  assert.deepEqual(
    flagParityProblems(localTemplate, everyParameterSource),
    [],
  );
});

test("a setting is held to its own shape contract, not the kill-switch one", () => {
  // A kill switch ships on as a Boolean. A setting ships at its healthy baseline with its own
  // type, and calling it a switch would make the healthy state a lie.
  assert.ok(isSettingParameter("workout_sync_recovery_epoch"));
  assert.ok(!isSettingParameter("workout_cloud_backup_writes_enabled"));

  const problems = templateShapeProblems({
    parameters: {
      workout_sync_recovery_epoch: {
        defaultValue: {value: "true"},
        valueType: "BOOLEAN",
        description: "wrong shape",
      },
    },
  });

  assert.equal(problems.length, 2);
  assert.ok(problems.some((problem) => problem.includes("must be declared NUMBER")));
  assert.ok(problems.some((problem) => problem.includes("healthy baseline")));
});

test("minimum and recommended app versions ship as inert strings", () => {
  for (const key of ["minimum_supported_app_version", "recommended_app_version"]) {
    assert.ok(isSettingParameter(key));
    assert.ok(appFlagKeys(appVersionSource).includes(key));
    assert.equal(localTemplate.parameters[key].valueType, "STRING");
    assert.equal(localTemplate.parameters[key].defaultValue.value, "0.0.0");
  }
});

test("a flag the app reads with no parameter behind it is reported", () => {
  const problems = flagParityProblems({parameters: {}}, 'case newSwitch = "new_switch_enabled"');

  assert.equal(problems.length, 1);
  assert.match(problems[0], /new_switch_enabled is read by the app but carries no parameter/);
});

test("a parameter no code reads is reported", () => {
  const problems = flagParityProblems(
    {
      parameters: {
        new_switch_enabled: {},
        forgotten_switch_enabled: {},
      },
    },
    'case newSwitch = "new_switch_enabled"',
  );

  assert.equal(problems.length, 1);
  assert.match(problems[0], /forgotten_switch_enabled is in remoteconfig.template.json/);
});

test("a Swift source with no flags is a parity failure, not a pass", () => {
  // The same reason the archive preflight refuses an empty parse: asserting nothing is how
  // this class of gap opens.
  assert.equal(flagParityProblems(localTemplate, "// no cases here").length, 1);
});

test("the live template's version number is read from either envelope", () => {
  assert.equal(templateVersionNumber({version: {versionNumber: "4"}}), 4);
  assert.equal(templateVersionNumber({result: {version: {versionNumber: "1"}}}), 1);
});

test("a project that has never been published carries no version", () => {
  // Distinct from version 0, which does not exist - `{}` is the literal response every project
  // gave on 2026-08-02, and the first publish makes it version 1.
  assert.equal(templateVersionNumber({}), null);
  assert.equal(templateVersionNumber({parameters: {}}), null);
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

test("a setting an operator parked at false still refuses an automated republish", () => {
  // The client reads `stringValue` and never inspects `valueType`, so a setting holding "false"
  // is honoured exactly like a switch. Excluding settings wholesale would let the automated
  // publisher restate it as its healthy baseline mid-incident.
  const live = {
    parameters: {
      workout_sync_recovery_epoch: { defaultValue: { value: "false" } },
    },
  };

  assert.deepEqual(findActiveKillSwitches(live, localTemplate), ["workout_sync_recovery_epoch"]);
});

test("an armed minimum version stops the full replace that would return it to 0.0.0", () => {
  // The hazard the Boolean guard cannot see: a threshold has no "false" to recognise, and the
  // checked-in template is pinned to the inert baseline, so publishing it IS the disarm.
  const live = liveTemplateMatchingCheckedIn();
  live.parameters.minimum_supported_app_version.defaultValue.value = "1.4.0";

  assert.deepEqual(findArmedSettings(live, localTemplate), [
    "minimum_supported_app_version",
  ]);
});

test("a threshold armed only through a condition is caught as well", () => {
  // The shape the App Review guidance tells a captain to use: the default stays inert and the
  // lockout rides on a Firebase App version condition, which a full replace would drop.
  const live = liveTemplateMatchingCheckedIn();
  live.parameters.minimum_supported_app_version.conditionalValues = {
    "iOS build 1.3.0": { value: "1.4.0" },
  };

  assert.deepEqual(findArmedSettings(live, localTemplate), [
    "minimum_supported_app_version",
  ]);
});

test("a bumped sync recovery epoch stops the full replace the same way", () => {
  // Same shape as an armed threshold, and the reason the guard covers every setting rather than
  // the captain-only two. The client compares the recovery basis for difference rather than
  // magnitude, so restating "0" does not strand the lever - it fires it, re-opening every stopped
  // sync series fleet-wide at a moment nobody chose.
  const live = liveTemplateMatchingCheckedIn();
  live.parameters.workout_sync_recovery_epoch.defaultValue.value = "3";

  assert.deepEqual(findArmedSettings(live, localTemplate), ["workout_sync_recovery_epoch"]);
});

test("overriding the epoch's permanent refusal comes with the value to put back", () => {
  // The epoch never returns to the checked-in floor, so unlike a switch or a threshold its
  // refusal is permanent and the override is the only way past it. That makes the follow-up part
  // of the operation rather than a tidy-up, so the tool names it with the live number.
  const live = liveTemplateMatchingCheckedIn();
  live.parameters.workout_sync_recovery_epoch.defaultValue.value = "3";

  const step = overrideRecoveryStep("workout_sync_recovery_epoch", live);

  assert.match(step, /workout_sync_recovery_epoch/);
  assert.match(step, /"3"/);
  assert.match(step, /back to at least/);
});

test("a lever that returns to parity on its own needs no follow-up step", () => {
  // A threshold disarms back to the checked-in baseline, so publishing it IS the disarm. Only a
  // monotonic setting is left below where it was.
  const live = liveTemplateMatchingCheckedIn();
  live.parameters.minimum_supported_app_version.defaultValue.value = "1.4.0";

  assert.equal(overrideRecoveryStep("minimum_supported_app_version", live), null);
  assert.equal(overrideRecoveryStep("workout_cloud_backup_writes_enabled", live), null);
});

test("only settings marked monotonic carry the permanent-refusal follow-up", () => {
  assert.ok(isMonotonicSetting("workout_sync_recovery_epoch"));
  assert.equal(isMonotonicSetting("minimum_supported_app_version"), false);
  assert.equal(isMonotonicSetting("workout_cloud_backup_writes_enabled"), false);
});

test("the full replace prints the follow-up on refusal and on the way through", () => {
  // Printed on both paths on purpose: the acknowledged run is the last output before the publish
  // that makes the follow-up necessary, and is the run that will not be read twice.
  const deploy = repositoryText("scripts/deploy-remote-config.mjs");

  assert.match(deploy, /overrideRecoveryStep/);
  assert.match(deploy, /recoverySteps\(unacknowledged, liveTemplate\)/);
  assert.match(deploy, /recoverySteps\(leversInUse, liveTemplate\)/);
});

test("every setting is covered by the full replace guard, not a named subset", () => {
  // Enumerated from the catalog, so a setting added later is guarded without being wired in
  // here - the drift that left the epoch uncovered when the guard was written for thresholds.
  for (const key of Object.keys(SETTING_PARAMETERS)) {
    const live = liveTemplateMatchingCheckedIn();
    live.parameters[key].defaultValue.value = "an operator moved this";

    assert.deepEqual(findArmedSettings(live, localTemplate), [key]);
  }
});

test("settings published at their healthy baseline let the full replace proceed", () => {
  assert.deepEqual(findArmedSettings(liveTemplateMatchingCheckedIn(), localTemplate), []);
});

test("a project that has never held the settings is not reported as moved", () => {
  // The first publish, which is exactly what a captain runs this script to do.
  assert.deepEqual(findArmedSettings({ parameters: {} }, localTemplate), []);
});

test("the full replace refuses on a moved setting, not just on an off switch", () => {
  const deploy = repositoryText("scripts/deploy-remote-config.mjs");

  assert.match(deploy, /findArmedSettings/);
  assert.match(deploy, /moved away from its checked-in baseline/);
  assert.match(deploy, /--allow-overwriting-active-kill-switch/);
});

test("a captain-only parameter is never treated as an automated publish's blocker", () => {
  const live = {
    parameters: {
      minimum_supported_app_version: { defaultValue: { value: "false" } },
    },
  };

  assert.deepEqual(findActiveKillSwitches(live, localTemplate), []);
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

// The archive-blocking gate has to cover settings, not just kill switches.
//
// An operator lever that exists in the checked-in template and nowhere in the live backend is
// worse than no lever, because it is believed in: `workout_sync_recovery_epoch` is the one thing
// that can unstick a fleet after a rules fix, and it is reached for mid-incident.
test("both RemoteConfig enums declare keys the published check covers", () => {
  const appKeys = appFlagKeys(everyParameterSource);

  assert.ok(appKeys.includes("workout_sync_recovery_epoch"));
  assert.ok(!appFlagKeys(flagSource).includes("workout_sync_recovery_epoch"));
  assert.deepEqual(unpublishedFlagProblems(localTemplate, appKeys), []);
});

test("a setting missing from the live backend fails the archive like a switch does", () => {
  const live = {
    parameters: Object.fromEntries(
      [...appFlagKeys(flagSource), ...appFlagKeys(appVersionSource)].map((key) => [
        key,
        localTemplate.parameters[key],
      ]),
    ),
  };

  const problems = unpublishedFlagProblems(
    live,
    appFlagKeys(everyParameterSource),
  );

  assert.equal(problems.length, 1);
  assert.match(problems[0], /workout_sync_recovery_epoch is missing from the live template/);
});

test("captain-only version parameters remain mandatory in the live archive check", () => {
  const versionKeys = appFlagKeys(appVersionSource);
  const problems = unpublishedFlagProblems({}, versionKeys);

  assert.equal(problems.length, 2);
  for (const key of versionKeys) {
    assert.ok(problems.some((problem) => problem.includes(key)));
  }
  assert.deepEqual(unpublishedFlagProblems(localTemplate, versionKeys), []);
});

test("a setting published at its own declared type is not reported as mistyped", () => {
  // The check used to hardcode BOOLEAN, which would have reported a correctly published NUMBER
  // lever as unreachable and blocked every archive.
  const live = {
    parameters: {
      workout_sync_recovery_epoch: { valueType: "NUMBER", defaultValue: { value: "0" } },
    },
  };

  assert.deepEqual(unpublishedFlagProblems(live, ["workout_sync_recovery_epoch"]), []);

  const mistyped = unpublishedFlagProblems(
    { parameters: { workout_sync_recovery_epoch: { valueType: "STRING", defaultValue: { value: "0" } } } },
    ["workout_sync_recovery_epoch"],
  );

  assert.equal(mistyped.length, 1);
  assert.match(mistyped[0], /published as STRING, not the NUMBER the template declares/);
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
