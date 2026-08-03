#!/usr/bin/env node

/**
 * Compares every Firebase project's live Remote Config against this ref, and reports.
 *
 * The archive preflight only ever looks at the one project the build in front of it will talk
 * to, and only at the moment someone is shipping. That leaves a project nobody is building for
 * - production, most of the time - free to diverge silently until an incident is the thing that
 * discovers it. This looks at all three on a schedule, so divergence is something you can see
 * rather than something you find out.
 *
 * It is strictly read-only. It reports drift; it never reconciles it. A live value that differs
 * from the checked-in template is either an operator using the lever, which is the mechanism
 * working, or a mistake that needs a human - and an automated repair would be indistinguishable
 * from the incident-time clobber this whole area exists to prevent.
 *
 * Usage: report-remote-config-drift.mjs <dev|staging|prod>...
 *
 * Exit codes: 0 every switch reachable, 1 a switch is unreachable somewhere, 2 could not look.
 */

import {execFileSync} from "node:child_process";
import {appendFileSync, readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import process from "node:process";
import {fileURLToPath} from "node:url";

import {
  appFlagKeys,
  findActiveKillSwitches,
  templateParameters,
  templateVersionNumber,
  unpublishedFlagProblems,
} from "../lib/remote-config-template.mjs";

const FIREBASE_TOOLS = "firebase-tools@15.22.1";
const STRUCTURAL_EXIT_CODE = 2;

const PROJECTS = {
  dev: "ascend-f2e4f",
  staging: "ascend-staging-fa7d5",
  prod: "ascend-prod-9c8f2",
};

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const TEMPLATE_PATH = resolve(REPO_ROOT, "remoteconfig.template.json");
const FLAG_SOURCE_PATH = resolve(
  REPO_ROOT,
  "AscendApp/Shared/Services/RemoteConfig/RemoteFeatureFlag.swift",
);

function annotate(level, message) {
  const stream = level === "error" ? console.error : console.log;
  stream(`::${level}::${message.replaceAll("\n", "%0A")}`);
}

function summarize(lines) {
  const path = process.env.GITHUB_STEP_SUMMARY;
  if (!path) {
    return;
  }
  appendFileSync(path, `${lines.join("\n")}\n`);
}

function failStructurally(message) {
  annotate("error", message);
  process.exit(STRUCTURAL_EXIT_CODE);
}

function fetchLiveTemplate(projectId) {
  // FIREBASE_TOKEN is read from the inherited environment by firebase-tools rather than passed
  // as an argument, so a CI credential never reaches the runner's process argument list.
  const raw = execFileSync(
    "npx",
    ["-y", FIREBASE_TOOLS, "remoteconfig:get", "--project", projectId, "--json"],
    {cwd: REPO_ROOT, encoding: "utf8", stdio: ["ignore", "pipe", "inherit"]},
  );

  return JSON.parse(raw);
}

function inspectProject(environment, localParameters, appKeys) {
  const projectId = PROJECTS[environment];
  let liveTemplate;

  try {
    liveTemplate = fetchLiveTemplate(projectId);
  } catch (error) {
    // Deliberately structural rather than a pass: "could not look" must never read as
    // "looks fine", which is the exact shape of the gap this whole area exists to end.
    failStructurally(`Could not read the live Remote Config template for ${projectId}: ${error.message}`);
  }

  const liveParameters = templateParameters(liveTemplate);

  return {
    environment,
    projectId,
    version: templateVersionNumber(liveTemplate),
    unreachable: unpublishedFlagProblems(liveTemplate, appKeys),
    switchedOff: findActiveKillSwitches(liveTemplate, {parameters: localParameters}),
    valueDrift: Object.keys(localParameters)
      .filter((key) => liveParameters[key] !== undefined)
      .filter(
        (key) =>
          liveParameters[key]?.defaultValue?.value !== localParameters[key]?.defaultValue?.value,
      ),
    unmanaged: Object.keys(liveParameters)
      .filter((key) => !appKeys.includes(key))
      .sort(),
  };
}

const environments = process.argv.slice(2);

if (
  environments.length === 0 ||
  environments.some((environment) => !(environment in PROJECTS))
) {
  failStructurally(
    `Every argument must be one of ${Object.keys(PROJECTS).join(", ")}, got ` +
      `"${environments.join(" ")}".`,
  );
}

let localParameters;
let appKeys;
try {
  localParameters = templateParameters(JSON.parse(readFileSync(TEMPLATE_PATH, "utf8")));
  appKeys = appFlagKeys(readFileSync(FLAG_SOURCE_PATH, "utf8"));
} catch (error) {
  failStructurally(`Cannot read this ref's kill-switch declarations: ${error.message}`);
}

if (appKeys.length === 0) {
  failStructurally(
    "Parsed no flag keys out of RemoteFeatureFlag.swift. Passing here would mean asserting " +
      "nothing, which is how this class of gap opens in the first place.",
  );
}

const reports = environments.map((environment) =>
  inspectProject(environment, localParameters, appKeys),
);

const summaryLines = [`### Remote Config drift, ${appKeys.length} kill switch(es) in this ref`, ""];

for (const report of reports) {
  const {projectId, version, unreachable, switchedOff, valueDrift, unmanaged} = report;

  summaryLines.push(
    `**\`${projectId}\`** - template version ${version ?? "never published"}, ` +
      `${unreachable.length} unreachable, ${switchedOff.length} switched off, ` +
      `${unmanaged.length} parameter(s) this ref does not read.`,
  );

  for (const problem of unreachable) {
    annotate("error", `${projectId}: ${problem}`);
    summaryLines.push(`- 🔴 ${problem}`);
  }

  for (const key of switchedOff) {
    // Not a defect. Reported because a switch left off long after its incident is exactly the
    // kind of divergence nobody notices until the path it disabled is missed.
    annotate("warning", `${projectId}: ${key} is currently OFF - a kill switch is in use.`);
    summaryLines.push(`- 🟡 \`${key}\` is OFF`);
  }

  for (const key of valueDrift.filter((key) => !switchedOff.includes(key))) {
    annotate(
      "warning",
      `${projectId}: ${key} holds a live value that is neither the checked-in default nor a ` +
        "recognisable off. Decide what it should be; nothing here will change it.",
    );
    summaryLines.push(`- 🟡 \`${key}\` holds an unexpected value`);
  }

  if (unmanaged.length > 0) {
    annotate(
      "notice",
      `${projectId} carries ${unmanaged.length} parameter(s) no current flag reads: ` +
        `${unmanaged.join(", ")}. Retired switches are left in place on purpose - deleting one ` +
        "is a human's call.",
    );
    summaryLines.push(`- ⚪️ Unread by this ref: ${unmanaged.map((key) => `\`${key}\``).join(", ")}`);
  }

  summaryLines.push("");
}

summarize(summaryLines);

const unreachableCount = reports.reduce((total, report) => total + report.unreachable.length, 0);

if (unreachableCount > 0) {
  annotate(
    "error",
    `${unreachableCount} kill switch(es) are unreachable across ` +
      `${reports.filter((report) => report.unreachable.length > 0).map((report) => report.projectId).join(", ")}. ` +
      "Publish before the next release, or that build's only undo is decorative.",
  );
  process.exit(1);
}

console.log(
  `Every one of the ${appKeys.length} kill switch(es) is reachable in ` +
    `${reports.map((report) => report.projectId).join(", ")}.`,
);
