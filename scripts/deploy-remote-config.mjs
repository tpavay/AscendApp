#!/usr/bin/env node

/**
 * Publishes `remoteconfig.template.json` to one Firebase project.
 *
 * Deploying a template is a full replace, so a naive deploy would republish every kill
 * switch as `true` - silently undoing whatever an operator had just switched off. That is
 * the exact failure this whole mechanism exists to prevent, so this script reads the live
 * template first and refuses while any lever is in use: a managed flag currently `false`, or
 * a captain-only version threshold armed away from the inert baseline the template carries.
 *
 * The kill switches are deliberately NOT part of the CI deploy (`deploy-staging.yml` and
 * `deploy-production.yml` do not pass `remoteconfig` to `--only`). Publishing the template
 * is an explicit, human-initiated act.
 *
 * Usage:
 *   node scripts/deploy-remote-config.mjs --env dev
 *   node scripts/deploy-remote-config.mjs --env staging
 *   node scripts/deploy-remote-config.mjs --env prod --confirm-production ascend-prod-9c8f2
 *
 * Dry-run is the default; pass --apply to publish. A lever in use - a flag that is
 * intentionally off, or a version threshold armed away from its inert baseline - stays as it
 * is unless you also pass --allow-overwriting-active-kill-switch, which needs the keys
 * spelled out so it cannot be a reflex.
 */

import {execFileSync} from "node:child_process";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {dirname, resolve} from "node:path";
import {
  findActiveKillSwitches,
  findArmedVersionThresholds,
} from "./lib/remote-config-template.mjs";

const FIREBASE_TOOLS = "firebase-tools@15.22.1";

const PROJECTS = {
  dev: "ascend-f2e4f",
  staging: "ascend-staging-fa7d5",
  prod: "ascend-prod-9c8f2",
};

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const TEMPLATE_PATH = resolve(REPO_ROOT, "remoteconfig.template.json");

function parseArgs(argv) {
  const args = {
    env: null,
    apply: false,
    confirmProduction: null,
    allowedOverwrites: [],
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case "--env":
        args.env = argv[++index] ?? null;
        break;
      case "--apply":
        args.apply = true;
        break;
      case "--confirm-production":
        args.confirmProduction = argv[++index] ?? null;
        break;
      case "--allow-overwriting-active-kill-switch":
        args.allowedOverwrites.push(argv[++index] ?? "");
        break;
      default:
        throw new Error(`Unrecognized argument: ${arg}`);
    }
  }

  return args;
}

function resolveProjectId({env, confirmProduction}) {
  if (!env || !(env in PROJECTS)) {
    throw new Error(`--env must be one of: ${Object.keys(PROJECTS).join(", ")}`);
  }

  const projectId = PROJECTS[env];
  if (env === "prod" && confirmProduction !== projectId) {
    throw new Error(
      `Production requires --confirm-production ${projectId}`,
    );
  }

  return projectId;
}

function runFirebase(args) {
  return execFileSync("npx", ["-y", FIREBASE_TOOLS, ...args], {
    cwd: REPO_ROOT,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"],
  });
}

function readLocalTemplate() {
  return JSON.parse(readFileSync(TEMPLATE_PATH, "utf8"));
}

function fetchLiveTemplate(projectId) {
  const raw = runFirebase(["remoteconfig:get", "--project", projectId, "--json"]);
  try {
    return JSON.parse(raw);
  } catch {
    throw new Error(
      `Could not parse the live template for ${projectId}. Raw output:\n${raw}`,
    );
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const projectId = resolveProjectId(args);
  const localTemplate = readLocalTemplate();

  console.log(`Remote Config template -> ${args.env} (${projectId})`);

  const liveTemplate = fetchLiveTemplate(projectId);
  const activeKillSwitches = findActiveKillSwitches(liveTemplate, localTemplate);
  const armedThresholds = findArmedVersionThresholds(liveTemplate, localTemplate);
  const leversInUse = [...activeKillSwitches, ...armedThresholds];
  const unacknowledged = leversInUse.filter(
    (key) => !args.allowedOverwrites.includes(key),
  );

  if (unacknowledged.length > 0) {
    console.error(
      [
        "",
        `REFUSING: ${unacknowledged.length} lever(s) are in use in ${projectId}:`,
        ...unacknowledged.map((key) =>
          armedThresholds.includes(key)
            ? `  - ${key} is armed away from its checked-in baseline`
            : `  - ${key} is currently OFF`,
        ),
        "",
        "Publishing this template restates the checked-in value over every one of them -",
        "switching a kill switch back on, and returning an armed version threshold to 0.0.0,",
        "which ends the lockout for the whole fleet. If that is what you want, re-run naming",
        "each one:",
        ...unacknowledged.map(
          (key) => `  --allow-overwriting-active-kill-switch ${key}`,
        ),
        "",
      ].join("\n"),
    );
    process.exitCode = 1;
    return;
  }

  if (leversInUse.length > 0) {
    console.log(
      `Acknowledged overwriting: ${leversInUse.join(", ")}`,
    );
  }

  const parameterCount = Object.keys(localTemplate.parameters).length;
  if (!args.apply) {
    console.log(
      `Dry run. ${parameterCount} parameter(s) would be published. Re-run with --apply.`,
    );
    return;
  }

  runFirebase([
    "deploy",
    "--project",
    projectId,
    "--only",
    "remoteconfig",
    "--non-interactive",
    "--force",
  ]);
  console.log(`Published ${parameterCount} parameter(s) to ${projectId}.`);
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
