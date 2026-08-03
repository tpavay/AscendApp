#!/usr/bin/env node

/**
 * Says what a pull request does to the kill switches, while it is still being reviewed.
 *
 * The archive preflight (`assert-remote-config-published.mjs`) compares the flags a build reads
 * against the live backend, which is the only check that can catch an unpublished switch - and
 * by construction it cannot run on a pull request, because a flag added in that pull request is
 * not published anywhere yet and never should be. So the useful assertion here is the offline
 * one: the app and the checked-in template agree, and the parameter is shaped like a switch.
 *
 * The rest is reporting. A reviewer should learn "this adds a kill switch, here is where it
 * lands automatically and where it does not" at review time, rather than from a staging archive
 * failing hours after the merge - which is exactly how #367's three switches were discovered.
 *
 * Usage: report-kill-switch-changes.mjs [--base-ref <ref>]
 *
 * Exit codes: 0 fine, 1 the app and template disagree or a parameter is malformed.
 */

import {execFileSync} from "node:child_process";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import process from "node:process";
import {fileURLToPath} from "node:url";

import {annotate, summarize} from "../lib/ci-annotations.mjs";
import {
  flagParityProblems,
  killSwitchChanges,
  templateParameters,
  templateShapeProblems,
} from "../lib/remote-config-template.mjs";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const TEMPLATE_PATH = "remoteconfig.template.json";
const FLAG_SOURCE_PATH = "AscendApp/Shared/Services/RemoteConfig/RemoteFeatureFlag.swift";

function parseArgs(argv) {
  const args = {baseRef: null};

  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === "--base-ref") {
      args.baseRef = argv[++index] ?? null;
      continue;
    }
    throw new Error(`Unrecognized argument: ${argv[index]}`);
  }

  return args;
}

/**
 * The template as of the base ref, or `null` when it cannot be read there.
 *
 * A missing base is not a failure: the pull request may be adding the file, the base ref may
 * not be fetched in a shallow checkout, or this may be a local run with no base at all. The
 * comparison is a courtesy to the reviewer; the assertions above it are what block.
 */
function templateAtBase(baseRef) {
  if (!baseRef) {
    return null;
  }

  try {
    return JSON.parse(
      execFileSync("git", ["show", `${baseRef}:${TEMPLATE_PATH}`], {
        cwd: REPO_ROOT,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
      }),
    );
  } catch {
    return null;
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const localTemplate = JSON.parse(readFileSync(resolve(REPO_ROOT, TEMPLATE_PATH), "utf8"));
  const swiftSource = readFileSync(resolve(REPO_ROOT, FLAG_SOURCE_PATH), "utf8");

  const problems = [
    ...flagParityProblems(localTemplate, swiftSource),
    ...templateShapeProblems(localTemplate),
  ];

  if (problems.length > 0) {
    for (const problem of problems) {
      annotate("error", problem);
    }
    console.error(
      `${problems.length} problem(s) between ${FLAG_SOURCE_PATH} and ${TEMPLATE_PATH}. ` +
        "See docs/remote-config-kill-switches.md.",
    );
    process.exit(1);
  }

  const currentKeys = Object.keys(templateParameters(localTemplate)).sort();
  const baseTemplate = templateAtBase(args.baseRef);

  if (baseTemplate === null) {
    console.log(
      `All ${currentKeys.length} kill switch(es) are declared in both the app and the template. ` +
        "No base ref to compare against, so nothing to report about this change.",
    );
    return;
  }

  const {added, removed} = killSwitchChanges(baseTemplate, localTemplate);

  if (added.length === 0 && removed.length === 0) {
    console.log(
      `All ${currentKeys.length} kill switch(es) are declared in both the app and the template, ` +
        "and this change adds or removes none.",
    );
    return;
  }

  if (added.length > 0) {
    annotate(
      "notice",
      `This pull request adds ${added.length} kill switch(es): ${added.join(", ")}. Merging to ` +
        "develop publishes them to dev and staging automatically; production does not, and its " +
        "archive will refuse until a human publishes them.",
    );
  }

  if (removed.length > 0) {
    annotate(
      "warning",
      `This pull request removes ${removed.length} kill switch(es) from the template: ` +
        `${removed.join(", ")}. Nothing deletes them from a live project - the automated ` +
        "publisher only ever adds - so they stay in each console until removed by hand.",
    );
  }

  // Falls back to the console on purpose: this one is run by hand as often as by CI, and a
  // local run that printed nothing would read as "this change touches no switch".
  summarize(
    [
      "### Remote Config kill switches",
      "",
      ...added.map((key) => `- **Added** \`${key}\``),
      ...removed.map((key) => `- **Removed** \`${key}\``),
      "",
      ...(added.length > 0
        ? [
            "| Project | How it gets published |",
            "|---|---|",
            "| `ascend-f2e4f` (dev) | Automatically, on merge to `develop` |",
            "| `ascend-staging-fa7d5` (staging) | Automatically, on merge to `develop`, before the staging archive checks the backend |",
            "| `ascend-prod-9c8f2` (production) | **By hand.** `cd scripts && npm run remoteconfig:publish-new:production -- --apply` |",
            "",
            "The automated publish only ever adds a parameter the project has never held, and refuses to write at all while any switch is off.",
            "See `docs/remote-config-kill-switches.md`.",
          ]
        : []),
    ],
    {fallbackToConsole: true},
  );
}

try {
  main();
} catch (error) {
  annotate("error", error.message);
  process.exit(1);
}
