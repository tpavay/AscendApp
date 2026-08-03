#!/usr/bin/env node

/**
 * Publishes kill switches a project has never seen, and nothing else.
 *
 * Three switches were added in #367, `remoteconfig.template.json` and `RemoteFeatureFlag.swift`
 * agreed, and nobody published them - so the 2026-08-03 staging archive stopped on
 * "routine_cloud_backup_writes_enabled is missing from the live template - this build's kill
 * switch is decorative". The guard did its job. What was missing is that publishing was a
 * separate manual act nobody remembers, discovered hours after the merge that needed it.
 *
 * This is the automatic half, and it is deliberately not `deploy-remote-config.mjs`. That
 * script publishes the checked-in template as a full replace, which is the right thing for a
 * human who has read the diff and the wrong thing for a machine: an operator flips a switch off
 * during an incident, any merge lands, and the automatic publish restores the file's defaults
 * and turns the switch back on mid-incident. The safety mechanism would cause the emergency.
 *
 * So this one is strictly additive, in two independent layers:
 *
 *   1. The payload is built from the LIVE template, never the checked-in one. Existing
 *      parameters, conditions and parameter groups cross verbatim; only keys the project has
 *      never held are added. There is no branch here that writes a checked-in value over a
 *      live one - see `additivePublishPlan`.
 *   2. It refuses to write at all while any managed switch is off in the target project, since
 *      Remote Config publishes are full replaces and the payload necessarily restates every
 *      live parameter. A human can still publish by hand.
 *
 * And it proves the write afterwards: the backend increments `version.versionNumber` on every
 * publish, so a post-publish version that is not exactly one past the version this run read is
 * evidence that something else published in between - reported loudly, with the intervening
 * version's contents, never reconciled.
 *
 * Usage:
 *   node scripts/publish-new-kill-switches.mjs dev
 *   node scripts/publish-new-kill-switches.mjs staging --apply
 *   node scripts/publish-new-kill-switches.mjs prod --confirm-production ascend-prod-9c8f2 --apply
 *
 * Dry run is the default. Production is never invoked by a workflow - see
 * `docs/remote-config-kill-switches.md` - and `scripts/test/remote-config-template.test.mjs`
 * fails if one ever does.
 *
 * Exit codes: 0 published or nothing to do, 1 refused or unverifiable, 2 structural error.
 */

import {execFileSync} from "node:child_process";
import {mkdtempSync, readFileSync, rmSync, writeFileSync} from "node:fs";
import {tmpdir} from "node:os";
import {dirname, join, resolve} from "node:path";
import process from "node:process";
import {fileURLToPath} from "node:url";

import {annotate, summarize} from "./lib/ci-annotations.mjs";
import {
  additiveMergeViolations,
  additivePublishPlan,
  publishedParameterMismatches,
  templateParameters,
  templateVersionNumber,
  unwrapTemplate,
} from "./lib/remote-config-template.mjs";

const FIREBASE_TOOLS = "firebase-tools@15.22.1";
const STRUCTURAL_EXIT_CODE = 2;

const PROJECTS = {
  dev: {projectId: "ascend-f2e4f", requiresConfirmation: false},
  staging: {projectId: "ascend-staging-fa7d5", requiresConfirmation: false},
  prod: {projectId: "ascend-prod-9c8f2", requiresConfirmation: true},
};

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const TEMPLATE_PATH = resolve(REPO_ROOT, "remoteconfig.template.json");

function failStructurally(message) {
  annotate("error", message);
  process.exit(STRUCTURAL_EXIT_CODE);
}

function parseArgs(argv) {
  const args = {environment: null, apply: false, confirmProduction: null};

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case "--apply":
        args.apply = true;
        break;
      case "--confirm-production":
        args.confirmProduction = argv[++index] ?? null;
        break;
      default:
        if (arg.startsWith("--") || args.environment !== null) {
          throw new Error(`Unrecognized argument: ${arg}`);
        }
        args.environment = arg;
    }
  }

  if (!args.environment || !(args.environment in PROJECTS)) {
    throw new Error(
      `Environment must be one of ${Object.keys(PROJECTS).join(", ")}, got ` +
        `"${args.environment ?? ""}".`,
    );
  }

  const {projectId, requiresConfirmation} = PROJECTS[args.environment];

  // Production publishing stays a deliberate human act. The flag is spelled out so it cannot be
  // reached by a workflow that merely passes an environment name through.
  if (requiresConfirmation && args.confirmProduction !== projectId) {
    throw new Error(`Production requires --confirm-production ${projectId}`);
  }

  return {...args, projectId};
}

function runFirebase(args, options = {}) {
  // FIREBASE_TOKEN is read straight from the inherited environment by firebase-tools, so it is
  // deliberately not passed as an argument - a CI credential does not belong in the runner's
  // process argument list.
  return execFileSync("npx", ["-y", FIREBASE_TOOLS, ...args], {
    cwd: REPO_ROOT,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"],
    ...options,
  });
}

function fetchLiveTemplate(projectId, versionNumber) {
  const versionArguments = versionNumber ? ["--version-number", String(versionNumber)] : [];
  const raw = runFirebase([
    "remoteconfig:get",
    "--project",
    projectId,
    "--json",
    ...versionArguments,
  ]);

  try {
    return JSON.parse(raw);
  } catch {
    throw new Error(`Could not parse the live template for ${projectId}. Raw output:\n${raw}`);
  }
}

/**
 * Publishes an arbitrary template body.
 *
 * The CLI has no "publish this object" command: `firebase deploy --only remoteconfig` reads
 * whatever path `firebase.json` names, relative to the working directory. So the merged
 * template and a one-line config are written to a scratch directory and the deploy runs there,
 * which leaves the repository's own `remoteconfig.template.json` untouched - it stays the
 * healthy-state file a human publishes, and is never a mutable staging buffer.
 *
 * `--force` is deliberately absent: it makes the CLI send `If-Match: *`.
 *
 * `--dry-run` runs the same command through the same scratch config and stops before the PUT,
 * so a dry run is a rehearsal of the real path rather than a claim about it.
 */
function publishTemplate(projectId, mergedTemplate, {dryRun}) {
  const workspace = mkdtempSync(join(tmpdir(), "ascend-remoteconfig-"));
  const templateFileName = "remoteconfig.merged.json";

  try {
    writeFileSync(join(workspace, templateFileName), JSON.stringify(mergedTemplate, null, 2));
    writeFileSync(
      join(workspace, "firebase.json"),
      JSON.stringify({remoteconfig: {template: templateFileName}}, null, 2),
    );

    execFileSync(
      "npx",
      [
        "-y",
        FIREBASE_TOOLS,
        "deploy",
        "--project",
        projectId,
        "--only",
        "remoteconfig",
        "--non-interactive",
        ...(dryRun ? ["--dry-run"] : []),
      ],
      {cwd: workspace, encoding: "utf8", stdio: ["ignore", "inherit", "inherit"]},
    );
  } finally {
    rmSync(workspace, {recursive: true, force: true});
  }
}

/**
 * Reports every way the project after the publish is not the project this run intended.
 *
 * The version number is the load-bearing check. Remote Config's publish is a full replace and
 * the pinned CLI re-fetches the ETag immediately before its own PUT, so `If-Match` cannot carry
 * this script's read across the gap. What it can do is prove afterwards that the gap was empty:
 * exactly one publish - this one - separates the version that was read from the version that is
 * live. Anything else means a concurrent publish was overwritten, which is the one outcome that
 * must never pass in silence.
 */
function verifyPublish(projectId, {versionBefore, mergedTemplate}) {
  const after = fetchLiveTemplate(projectId);
  const versionAfter = templateVersionNumber(after);
  const expectedVersion = (versionBefore ?? 0) + 1;
  const problems = [];

  if (versionAfter !== expectedVersion) {
    problems.push(
      `Expected ${projectId} to reach template version ${expectedVersion}, found ` +
        `${versionAfter ?? "no version at all"}. Something else published between this run's ` +
        "read and its write, and this publish restated the values that were live before it.",
    );

    for (let version = expectedVersion; version < (versionAfter ?? 0); version += 1) {
      try {
        const overwritten = fetchLiveTemplate(projectId, version);
        const offSwitches = Object.entries(templateParameters(overwritten))
          .filter(([, parameter]) => parameter?.defaultValue?.value === "false")
          .map(([key]) => key);
        const author = unwrapTemplate(overwritten)?.version?.updateUser?.email ?? "an unknown user";
        problems.push(
          `Version ${version} was published by ${author} and had ` +
            `${offSwitches.length > 0 ? `these switches OFF: ${offSwitches.join(", ")}` : "no switch off"}.`,
        );
      } catch (error) {
        problems.push(`Could not read the overwritten version ${version}: ${error.message}`);
      }
    }
  }

  for (const key of publishedParameterMismatches(after, mergedTemplate)) {
    problems.push(`${key} does not match what this run published.`);
  }

  return problems;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const {projectId, environment} = args;
  const localTemplate = JSON.parse(readFileSync(TEMPLATE_PATH, "utf8"));

  console.log(`Additive kill-switch publish -> ${environment} (${projectId})`);

  const liveTemplate = fetchLiveTemplate(projectId);
  const versionBefore = templateVersionNumber(liveTemplate);
  const plan = additivePublishPlan(liveTemplate, localTemplate);

  for (const drift of plan.driftReports) {
    // Reported, never reconciled. The merged payload carries the live value forward untouched;
    // deciding that a live value is wrong is a human's call, not an automated publish's.
    annotate("warning", `Live drift in ${projectId}, left exactly as it is - ${drift}`);
  }

  if (plan.refusals.length > 0) {
    for (const refusal of plan.refusals) {
      annotate("error", refusal);
    }
    console.error(
      `\nREFUSING to publish to ${projectId}. ` +
        (plan.missingKeys.length > 0
          ? `${plan.missingKeys.length} switch(es) stay unpublished: ${plan.missingKeys.join(", ")}.`
          : "Nothing was pending, and nothing was written."),
    );
    console.error("Resolve the condition above, then publish by hand:");
    console.error(
      `  node scripts/publish-new-kill-switches.mjs ${environment}` +
        `${PROJECTS[environment].requiresConfirmation ? ` --confirm-production ${projectId}` : ""}` +
        " --apply",
    );
    console.error("  See docs/remote-config-kill-switches.md.");
    process.exit(1);
  }

  if (plan.missingKeys.length === 0) {
    console.log(
      `All ${plan.managedKeys.length} kill switch(es) already exist in ${projectId}. ` +
        "Nothing to publish, and nothing written.",
    );
    // Rehearsed anyway when nobody asked for a write, so a dry run answers "would this work"
    // about the real command rather than about this script's opinion of it.
    if (!args.apply) {
      publishTemplate(projectId, plan.mergedTemplate, {dryRun: true});
    }
    return;
  }

  const violations = additiveMergeViolations(liveTemplate, plan.mergedTemplate, plan.missingKeys);
  if (violations.length > 0) {
    // Unreachable unless the merge itself regressed, which is exactly when it must not publish.
    for (const violation of violations) {
      annotate("error", violation);
    }
    failStructurally(
      `The merged template for ${projectId} is not strictly additive. Refusing to publish.`,
    );
  }

  console.log(`Missing from ${projectId}: ${plan.missingKeys.join(", ")}`);
  console.log(
    `${Object.keys(templateParameters(liveTemplate)).length} existing parameter(s) carried ` +
      "across from the live project unchanged.",
  );

  publishTemplate(projectId, plan.mergedTemplate, {dryRun: !args.apply});

  if (!args.apply) {
    console.log("Dry run. Nothing was published. Re-run with --apply.");
    return;
  }

  const problems = verifyPublish(projectId, {versionBefore, mergedTemplate: plan.mergedTemplate});
  if (problems.length > 0) {
    for (const problem of problems) {
      annotate("error", problem);
    }
    console.error(
      "Read the Remote Config version history for this project and decide what to restore. " +
        "Nothing here will restore it for you.",
    );
    process.exit(1);
  }

  annotate(
    "notice",
    `Published ${plan.missingKeys.length} new kill switch(es) to ${projectId}: ` +
      `${plan.missingKeys.join(", ")}.`,
  );
  summarize([
    `### Remote Config: ${plan.missingKeys.length} new kill switch(es) published to \`${projectId}\``,
    "",
    ...plan.missingKeys.map((key) => `- \`${key}\``),
    "",
    `Existing parameters were carried across from the live project untouched (template version ` +
      `${versionBefore ?? 0} -> ${(versionBefore ?? 0) + 1}).`,
  ]);
}

try {
  main();
} catch (error) {
  failStructurally(error.message);
}
