import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {readdirSync, readFileSync} from "node:fs";
import test from "node:test";

import {
  additiveMerge,
  additiveMergeViolations,
  additivePublishPlan,
  killSwitchChanges,
  publishedParameterMismatches,
  templateParameters,
} from "../lib/remote-config-template.mjs";

const PUBLISHER = "publish-new-kill-switches.mjs";
const ARCHIVE_GUARD = "assert-remote-config-published.mjs";
const DRIFT_REPORT = "report-remote-config-drift.mjs";
const PULL_REQUEST_REPORT = "report-kill-switch-changes.mjs";

const PUBLISHER_PATH = new URL(`../${PUBLISHER}`, import.meta.url).pathname;
const WORKFLOWS_DIRECTORY = new URL("../../.github/workflows/", import.meta.url);

function repositoryJSON(path) {
  return JSON.parse(readFileSync(new URL(`../../${path}`, import.meta.url), "utf8"));
}

const localTemplate = repositoryJSON("remoteconfig.template.json");

function parameter(value, overrides = {}) {
  return {defaultValue: {value}, valueType: "BOOLEAN", description: "Kill switch.", ...overrides};
}

/** A live project holding every checked-in switch, each set to the given value. */
function liveTemplateWith(values) {
  return {
    parameters: Object.fromEntries(
      Object.keys(templateParameters(localTemplate))
        .filter((key) => key in values)
        .map((key) => [key, {...localTemplate.parameters[key], defaultValue: {value: values[key]}}]),
    ),
    conditions: [],
    parameterGroups: {},
    version: {versionNumber: "3"},
  };
}

const everyKey = Object.keys(templateParameters(localTemplate));
// Each parameter's own checked-in default, not a blanket "true": the template carries settings as
// well as kill switches, and a setting published as a Boolean would read as drift.
const allOn = Object.fromEntries(
  Object.entries(templateParameters(localTemplate)).map(
    ([key, parameter]) => [key, parameter?.defaultValue?.value],
  ),
);

test("a project already holding every switch is left alone", () => {
  const plan = additivePublishPlan(liveTemplateWith(allOn), localTemplate);

  assert.deepEqual(plan.missingKeys, []);
  assert.deepEqual(plan.refusals, []);
  assert.deepEqual(plan.driftReports, []);
});

test("only the switches a project has never held are added", () => {
  // #367 exactly: the template and the app carried nine, staging carried the six that predated
  // the routine backup, and nothing published the difference.
  const live = liveTemplateWith(
    Object.fromEntries(
      Object.entries(allOn).filter(([key]) => !key.startsWith("routine_")),
    ),
  );

  const plan = additivePublishPlan(live, localTemplate);

  assert.deepEqual(plan.missingKeys, [
    "routine_cloud_backup_writes_enabled",
    "routine_cloud_restore_enabled",
    "routine_remote_deletes_enabled",
  ]);
  assert.deepEqual(
    Object.keys(plan.mergedTemplate.parameters).sort(),
    [...everyKey].sort(),
  );
  assert.deepEqual(additiveMergeViolations(live, plan.mergedTemplate, plan.missingKeys), []);
});

test("an existing switch that is OFF survives the merge untouched", () => {
  // Layer one, on its own. The payload is a full replace, so the merged template necessarily
  // restates the switch - and it must restate the value the project actually holds, never the
  // `true` the checked-in template carries. That is what stops an automated publish from
  // re-enabling a kill switch in the middle of the incident it is stopping.
  const live = liveTemplateWith({
    ...Object.fromEntries(Object.entries(allOn).filter(([key]) => !key.startsWith("routine_"))),
    workout_cloud_backup_writes_enabled: "false",
  });

  const {missingKeys, mergedTemplate} = additiveMerge(live, localTemplate);

  assert.equal(
    mergedTemplate.parameters.workout_cloud_backup_writes_enabled.defaultValue.value,
    "false",
  );
  assert.equal(
    localTemplate.parameters.workout_cloud_backup_writes_enabled.defaultValue.value,
    "true",
  );
  assert.deepEqual(additiveMergeViolations(live, mergedTemplate, missingKeys), []);
});

test("an automated run refuses to write at all while a switch is OFF", () => {
  // Layer two, which is why layer one is never the only thing standing between an incident and
  // a re-enabled switch: the publish is a full replace, so a flip landing between the read and
  // the write would be undone by a payload that was correct when it was built.
  const live = liveTemplateWith({
    ...Object.fromEntries(Object.entries(allOn).filter(([key]) => !key.startsWith("routine_"))),
    workout_cloud_backup_writes_enabled: "false",
  });

  const plan = additivePublishPlan(live, localTemplate);

  assert.equal(plan.refusals.length, 1);
  assert.match(plan.refusals[0], /workout_cloud_backup_writes_enabled.*is\s+currently OFF/s);
  assert.equal(plan.mergedTemplate, null);
  assert.deepEqual(plan.activeKillSwitches, ["workout_cloud_backup_writes_enabled"]);
  assert.ok(plan.missingKeys.length > 0, "there must be something it is declining to publish");
});

test("a switch that is OFF does not block a project with nothing to add", () => {
  // Using the lever must not turn every later deploy red. With no missing switch there is
  // nothing to publish, so the automated run writes nothing and says so.
  const live = liveTemplateWith({...allOn, workout_media_uploads_enabled: "false"});

  const plan = additivePublishPlan(live, localTemplate);

  assert.deepEqual(plan.missingKeys, []);
  assert.deepEqual(plan.refusals, []);
  assert.deepEqual(plan.activeKillSwitches, ["workout_media_uploads_enabled"]);
});

test("a live value that differs from the checked-in one is reported, never reconciled", () => {
  const live = liveTemplateWith(
    Object.fromEntries(Object.entries(allOn).filter(([key]) => !key.startsWith("routine_"))),
  );
  live.parameters.public_profile_publishing_enabled.description = "Edited in the console.";
  live.parameters.local_data_migrations_enabled.valueType = "STRING";

  const plan = additivePublishPlan(live, localTemplate);

  assert.equal(plan.driftReports.length, 2);
  assert.ok(plan.driftReports.some((report) => /public_profile_publishing_enabled/.test(report)));
  assert.ok(plan.driftReports.some((report) => /local_data_migrations_enabled/.test(report)));

  // Reported and carried across exactly as found. Reconciling would be a second way to write
  // a checked-in value over a live one.
  assert.equal(
    plan.mergedTemplate.parameters.public_profile_publishing_enabled.description,
    "Edited in the console.",
  );
  assert.equal(plan.mergedTemplate.parameters.local_data_migrations_enabled.valueType, "STRING");
  assert.deepEqual(additiveMergeViolations(live, plan.mergedTemplate, plan.missingKeys), []);
});

test("a live parameter this ref does not know about is never deleted", () => {
  // `leaderboard_publishing_enabled` is exactly this: retired with #307, still live in every
  // project. A publish that dropped it would remove a lever from under any binary still
  // reading it.
  const live = liveTemplateWith(
    Object.fromEntries(Object.entries(allOn).filter(([key]) => !key.startsWith("routine_"))),
  );
  live.parameters.leaderboard_publishing_enabled = parameter("false");

  const plan = additivePublishPlan(live, localTemplate);

  assert.deepEqual(plan.refusals, []);
  assert.deepEqual(
    plan.mergedTemplate.parameters.leaderboard_publishing_enabled,
    parameter("false"),
  );
  assert.deepEqual(additiveMergeViolations(live, plan.mergedTemplate, plan.missingKeys), []);
});

test("conditions and parameter groups come from the live project, not the checked-in file", () => {
  const live = liveTemplateWith(allOn);
  live.conditions = [{name: "iOS internal", expression: "app.id == '1'"}];
  live.parameterGroups = {Experiments: {description: "Not ours", parameters: {}}};

  const plan = additivePublishPlan(live, localTemplate);

  assert.deepEqual(plan.mergedTemplate.conditions, live.conditions);
  assert.deepEqual(plan.mergedTemplate.parameterGroups, live.parameterGroups);
});

test("a managed switch nested in a live parameter group is refused, not guessed at", () => {
  // Only the top-level `parameters` map is read anywhere in this repository, so a grouped key
  // looks absent - and "adding" it would publish a second copy of a switch that already exists.
  const live = liveTemplateWith(
    Object.fromEntries(Object.entries(allOn).filter(([key]) => !key.startsWith("routine_"))),
  );
  live.parameterGroups = {
    Routines: {parameters: {routine_cloud_backup_writes_enabled: parameter("false")}},
  };

  const plan = additivePublishPlan(live, localTemplate);

  assert.equal(plan.refusals.length, 1);
  assert.match(plan.refusals[0], /routine_cloud_backup_writes_enabled lives inside/);
  assert.equal(plan.mergedTemplate, null);
});

test("an empty project receives every switch", () => {
  // The #318 shape. Nothing is live, so everything is an addition and nothing is overwritten.
  const plan = additivePublishPlan({}, localTemplate);

  assert.deepEqual(plan.missingKeys, [...everyKey].sort());
  assert.deepEqual(additiveMergeViolations({}, plan.mergedTemplate, plan.missingKeys), []);
});

test("a merge that changes an existing switch is caught before it is published", () => {
  // The self-check the publisher runs on its own payload immediately before sending it. If the
  // merge ever regresses into reconciling, this is what stops the write.
  const live = liveTemplateWith({...allOn, workout_remote_deletes_enabled: "false"});
  const tampered = structuredClone(live);
  tampered.parameters.workout_remote_deletes_enabled = parameter("true");

  const violations = additiveMergeViolations(live, tampered, []);

  assert.equal(violations.length, 1);
  assert.match(violations[0], /workout_remote_deletes_enabled already exists/);
});

test("a merge that drops or invents a parameter is caught", () => {
  const live = liveTemplateWith(allOn);

  const dropped = structuredClone(live);
  delete dropped.parameters.workout_cloud_restore_enabled;
  assert.ok(additiveMergeViolations(live, dropped, []).length > 0);

  const invented = structuredClone(live);
  invented.parameters.unaccounted_flag_enabled = parameter("true");
  assert.ok(additiveMergeViolations(live, invented, []).length > 0);
});

test("a merge that rewrites conditions or parameter groups is caught", () => {
  const live = liveTemplateWith(allOn);
  live.conditions = [{name: "iOS internal", expression: "app.id == '1'"}];

  const flattened = structuredClone(live);
  flattened.conditions = [];

  assert.deepEqual(additiveMergeViolations(live, flattened, []), [
    "The merged template would change the project's conditions.",
  ]);
});

test("an addition that already exists is caught", () => {
  const live = liveTemplateWith(allOn);

  const violations = additiveMergeViolations(live, live, ["workout_media_uploads_enabled"]);

  assert.ok(
    violations.some((violation) => /was counted as an addition but already exists/.test(violation)),
  );
});

test("the backend's own field ordering is not mistaken for a failed publish", () => {
  // The checked-in template writes `defaultValue`, `valueType`, `description`; the REST API
  // echoes a parameter back in proto field order. A key-order-sensitive comparison would call
  // every newly added switch - the only kind this publisher ever writes - a failed publish, and
  // fail the staging deploy seconds after the write it had just completed successfully.
  const published = {
    parameters: {
      routine_cloud_backup_writes_enabled: {
        defaultValue: {value: "true"},
        valueType: "BOOLEAN",
        description: "Kill switch.",
      },
    },
  };
  const echoedBackByFirebase = {
    parameters: {
      routine_cloud_backup_writes_enabled: {
        defaultValue: {value: "true"},
        description: "Kill switch.",
        valueType: "BOOLEAN",
      },
    },
  };

  assert.deepEqual(publishedParameterMismatches(echoedBackByFirebase, published), []);
});

test("a parameter the backend did not store as published is still named", () => {
  const published = {parameters: {a_flag_enabled: parameter("true"), b_flag_enabled: parameter("true")}};
  const stored = {
    parameters: {
      a_flag_enabled: parameter("false"),
      b_flag_enabled: parameter("true"),
    },
  };

  assert.deepEqual(publishedParameterMismatches(stored, published), ["a_flag_enabled"]);
  assert.deepEqual(publishedParameterMismatches({parameters: {}}, published), [
    "a_flag_enabled",
    "b_flag_enabled",
  ]);
});

test("a change that adds a switch names it, and one that removes a switch names that", () => {
  const base = {parameters: {a_flag_enabled: {}, retired_flag_enabled: {}}};
  const current = {parameters: {a_flag_enabled: {}, brand_new_flag_enabled: {}}};

  assert.deepEqual(killSwitchChanges(base, current), {
    added: ["brand_new_flag_enabled"],
    removed: ["retired_flag_enabled"],
  });
});

test("a change that touches no switch reports nothing to a reviewer", () => {
  assert.deepEqual(killSwitchChanges(localTemplate, localTemplate), {added: [], removed: []});
});

test("the pull request report reads this ref and finds nothing wrong with it", () => {
  // A smoke test over the real files, so a broken import or a template that stopped matching
  // RemoteFeatureFlag.swift fails here rather than on a pull request.
  const result = spawnSync(
    process.execPath,
    [new URL("../ci/report-kill-switch-changes.mjs", import.meta.url).pathname],
    {encoding: "utf8", timeout: 30_000},
  );

  assert.equal(result.status, 0, result.stderr);
  assert.doesNotMatch(result.stderr, /::error::/);
});

function runPublisher(args) {
  return spawnSync(process.execPath, [PUBLISHER_PATH, ...args], {encoding: "utf8", timeout: 30_000});
}

test("the publisher rejects an unknown environment before reaching Firebase", () => {
  const result = runPublisher(["everywhere"]);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /Environment must be one of dev, staging, prod/);
  assert.doesNotMatch(result.stdout, /Additive kill-switch publish/);
});

test("the publisher refuses production without the project id spelled out", () => {
  // The same shape as the full-replace script's guard: naming the project cannot be a reflex,
  // and an environment name passed through from somewhere else cannot reach production.
  const result = runPublisher(["prod", "--apply"]);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /Production requires --confirm-production ascend-prod-9c8f2/);
  assert.doesNotMatch(result.stdout, /Additive kill-switch publish/);
});

test("the publisher rejects a run with no environment at all", () => {
  const result = runPublisher(["--apply"]);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /Environment must be one of/);
});

function workflowFiles() {
  return readdirSync(WORKFLOWS_DIRECTORY)
    .filter((name) => /\.ya?ml$/.test(name))
    .sort();
}

function workflowText(name) {
  return readFileSync(new URL(name, WORKFLOWS_DIRECTORY), "utf8");
}

/**
 * The top-level jobs of a workflow, as `{name: block}`.
 *
 * A dependency parser rather than a text search, because the property under test is an
 * ordering: "the archive waits for the publish" is false if the two merely appear in the same
 * file, which is precisely the mistake this whole change exists to correct.
 */
function workflowJobs(contents) {
  const lines = contents.split("\n");
  const start = lines.findIndex((line) => /^jobs:\s*$/.test(line));
  const jobs = new Map();
  let current = null;

  for (const line of lines.slice(start + 1)) {
    const header = line.match(/^ {2}([A-Za-z0-9_.-]+):\s*$/);
    if (header) {
      current = header[1];
      jobs.set(current, []);
      continue;
    }
    if (current) {
      jobs.get(current).push(line);
    }
  }

  return new Map([...jobs].map(([name, block]) => [name, block.join("\n")]));
}

function jobNeeds(block) {
  const lines = block.split("\n");
  const index = lines.findIndex((line) => /^ {4}needs:/.test(line));
  if (index === -1) {
    return [];
  }

  const inline = lines[index].slice(lines[index].indexOf(":") + 1).trim();
  if (inline) {
    return inline
      .replaceAll(/[[\]]/g, "")
      .split(",")
      .map((entry) => entry.trim())
      .filter(Boolean);
  }

  const needs = [];
  for (const line of lines.slice(index + 1)) {
    const item = line.match(/^ {6}-\s*(\S+)\s*$/);
    if (!item) {
      break;
    }
    needs.push(item[1]);
  }
  return needs;
}

function transitiveNeeds(jobs, name, seen = new Set()) {
  for (const dependency of jobNeeds(jobs.get(name) ?? "")) {
    if (seen.has(dependency)) {
      continue;
    }
    seen.add(dependency);
    transitiveNeeds(jobs, dependency, seen);
  }
  return seen;
}

/** Command lines, comments stripped, that invoke a given script. */
function invocationsOf(contents, script) {
  return contents
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => !line.startsWith("#"))
    .filter((line) => line.includes(script));
}

test("the job graph parser sees the dependencies it is used to assert", () => {
  // A parser that silently returns nothing would make every ordering assertion below pass
  // vacuously, which is the failure mode of exactly this kind of test.
  const jobs = workflowJobs(workflowText("deploy-production.yml"));

  assert.ok(jobs.has("build-ios"));
  assert.ok(jobs.has("deploy-firebase"));
  assert.deepEqual(jobNeeds(jobs.get("production-approval")), ["production-gate"]);
  assert.ok(jobNeeds(jobs.get("deploy-firebase")).includes("build-ios"));
});

test("staging publishes new kill switches on every push to develop", () => {
  const contents = workflowText("deploy-staging.yml");
  const applied = invocationsOf(contents, PUBLISHER).filter((line) => line.includes("--apply"));

  assert.ok(
    applied.some((line) => /\bstaging\b/.test(line)),
    "deploy-staging.yml must publish new kill switches to staging - a switch nobody remembers " +
      "to publish is the failure this exists to end",
  );
  assert.ok(
    applied.some((line) => /\bdev\b/.test(line)),
    "dev must receive new kill switches too; nothing else publishes to it",
  );
});

/** The `on: push: paths:` filter of a workflow, as a list. */
function pushPaths(contents) {
  const lines = contents.split("\n");
  const start = lines.findIndex((line) => /^ {4}paths:\s*$/.test(line));
  if (start === -1) {
    return [];
  }

  const paths = [];
  for (const line of lines.slice(start + 1)) {
    const item = line.match(/^ {6}-\s*"?([^"#]+?)"?\s*$/);
    if (!item) {
      if (/^\s*(#.*)?$/.test(line)) {
        continue;
      }
      break;
    }
    paths.push(item[1]);
  }
  return paths;
}

test("the file that declares the kill switches triggers the job that publishes them", () => {
  // Without this the staging deploy fires on a template-only change solely by way of the
  // AscendApp/** match, which holds because the parity check forces RemoteFeatureFlag.swift to
  // move with it. That is another check's guarantee, not this workflow's.
  const paths = pushPaths(workflowText("deploy-staging.yml"));

  assert.ok(paths.length > 0, "parsed no push paths - the assertion below would be vacuous");
  assert.ok(
    paths.includes("remoteconfig.template.json"),
    "deploy-staging.yml must fire on remoteconfig.template.json - the file that defines what " +
      "publish-kill-switches publishes must be the file that triggers it",
  );
});

test("the archive guard's remediation names the additive publisher before the full replace", () => {
  // Mid-release, the operator reads this failure and runs the first command in it. The full
  // replace is the one command that can re-enable a switch someone deliberately turned off, so
  // it cannot be the one named first.
  const guard = readFileSync(
    new URL(`../ci/${ARCHIVE_GUARD}`, import.meta.url),
    "utf8",
  );
  const aliases = repositoryJSON("scripts/package.json").scripts;

  for (const suffix of ["", ":staging", ":production"]) {
    const additive = `remoteconfig:publish-new${suffix}`;
    const fullReplace = `remoteconfig:deploy${suffix}`;

    assert.ok(additive in aliases, `${additive} must exist as an npm alias`);
    assert.ok(fullReplace in aliases, `${fullReplace} must exist as an npm alias`);
    assert.ok(guard.includes(additive), `${ARCHIVE_GUARD} must offer ${additive}`);
    assert.ok(
      guard.indexOf(additive) < guard.indexOf(fullReplace),
      `${ARCHIVE_GUARD} must name ${additive} before ${fullReplace}`,
    );
  }
});

test("the archive preflight cannot run before the publish it depends on", () => {
  // The ordering finding this change is built around. Putting the publish in the Firebase
  // deploy job would NOT work: in deploy-staging.yml that job runs in parallel with the
  // archive, and in deploy-production.yml it runs after it.
  for (const workflow of workflowFiles()) {
    const contents = workflowText(workflow);
    const jobs = workflowJobs(contents);

    const publishingJobs = [...jobs]
      .filter(([, block]) => invocationsOf(block, PUBLISHER).length > 0)
      .map(([name]) => name);
    const archivingJobs = [...jobs]
      .filter(([, block]) => invocationsOf(block, ARCHIVE_GUARD).length > 0)
      .map(([name]) => name);

    for (const archiving of archivingJobs) {
      const upstream = transitiveNeeds(jobs, archiving);

      for (const publishing of publishingJobs) {
        assert.ok(
          upstream.has(publishing),
          `${workflow}: "${archiving}" reads the live template but does not need ` +
            `"${publishing}", which publishes to it. They would race, and the archive would ` +
            "fail on a switch that was about to be published seconds later",
        );
      }
    }
  }
});

test("no workflow publishes Remote Config to production", () => {
  // Additive publishing is safe by construction, and that is still not a reason to widen what
  // automation touches in production without a decision. Production stays a captain-only
  // publish - docs/production-backend-rollout-runbook.md - and the archive preflight is what
  // makes a missed one stop the release.
  const productionAlias = "remoteconfig:publish-new:production";

  for (const workflow of workflowFiles()) {
    const contents = workflowText(workflow);

    assert.ok(
      !contents.includes(productionAlias),
      `${workflow} must not run ${productionAlias}`,
    );

    for (const invocation of invocationsOf(contents, PUBLISHER)) {
      const args = invocation.slice(invocation.indexOf(PUBLISHER) + PUBLISHER.length);

      assert.ok(
        !/(^|\s)prod(\s|$)/.test(args),
        `${workflow} invokes the publisher against production: ${invocation}`,
      );
      assert.ok(
        !args.includes("--confirm-production"),
        `${workflow} carries the production confirmation flag: ${invocation}`,
      );
    }
  }
});

test("drift is checked against all three projects on a schedule", () => {
  const contents = workflowText("remote-config-drift.yml");
  const invocations = invocationsOf(contents, DRIFT_REPORT);

  assert.equal(invocations.length, 1);
  for (const environment of ["dev", "staging", "prod"]) {
    assert.match(invocations[0], new RegExp(`(^|\\s)${environment}(\\s|$)`));
  }

  assert.match(contents, /^on:\n(.*\n)*?\s+schedule:\n\s+- cron:/m);
  assert.match(contents, /^\s+workflow_dispatch:\s*$/m);

  // Read-only, production included. The drift report never writes anywhere.
  assert.equal(invocationsOf(contents, PUBLISHER).length, 0);
  assert.equal(invocationsOf(contents, "deploy-remote-config.mjs").length, 0);
});

test("a pull request that adds a flag is told so while it is being reviewed", () => {
  const contents = workflowText("ci.yml");

  assert.ok(
    invocationsOf(contents, PULL_REQUEST_REPORT).length > 0,
    "ci.yml must report kill-switch changes on a pull request - learning about a new switch " +
      "from a staging archive hours after the merge is the delay this removes",
  );
  assert.match(contents, /remoteconfig\.template\.json/);
  assert.match(contents, /AscendApp\/Shared\/Services\/RemoteConfig\/\*\*/);
});

test("both deploy workflows still refuse to archive against an unpublished switch", () => {
  // Automation now removes the usual reason a switch is missing. It does not remove the guard:
  // the publisher deliberately declines in cases the archive must still catch.
  for (const workflow of ["deploy-staging.yml", "deploy-production.yml"]) {
    assert.ok(
      invocationsOf(workflowText(workflow), ARCHIVE_GUARD).length > 0,
      `${workflow} must still run ${ARCHIVE_GUARD}`,
    );
  }
});
