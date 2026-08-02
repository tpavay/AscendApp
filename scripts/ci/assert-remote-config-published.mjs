#!/usr/bin/env node
// Fails a staging or production archive whose kill switches do not exist on the
// Remote Config backend it will talk to.
//
// #298 shipped seven switches and #318 found that none of them had ever been
// published, in any project. Nothing caught it, because nothing looks: the
// checked-in template was right, the app was right, and CI compared those two to
// each other. The one comparison nobody made was against the live backend, which
// was empty. A build in that state behaves perfectly normally right up to the
// moment an operator needs the lever.
//
// So this asserts the third side of the triangle - live template vs the flags this
// build reads - and refuses the archive rather than shipping a binary whose only
// undo is decorative.
//
// Usage: assert-remote-config-published.mjs <dev|staging|prod>
//
// Exit codes: 0 shippable, 1 flags unreachable on the backend, 2 structural error.
import {execFileSync} from "node:child_process";
import {readFile} from "node:fs/promises";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import process from "node:process";

import {appFlagKeys, unpublishedFlagProblems} from "../lib/remote-config-template.mjs";

const FIREBASE_TOOLS = "firebase-tools@15.22.1";
const STRUCTURAL_EXIT_CODE = 2;

// The publish script's npm alias lives beside its project id so a renamed script cannot
// leave the remediation below pointing at a command that does not exist.
const PROJECTS = {
  dev: {projectId: "ascend-f2e4f", publishScript: "remoteconfig:deploy"},
  staging: {projectId: "ascend-staging-fa7d5", publishScript: "remoteconfig:deploy:staging"},
  prod: {projectId: "ascend-prod-9c8f2", publishScript: "remoteconfig:deploy:production"},
};

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const FLAG_SOURCE_PATH = resolve(
  REPO_ROOT,
  "AscendApp/Shared/Services/RemoteConfig/RemoteFeatureFlag.swift",
);

function failStructurally(message) {
  // A workflow command terminates at its first raw newline; `%0A` is how a multi-line
  // annotation survives into the rendered error rather than only the raw log.
  console.error(`::error::${message.replaceAll("\n", "%0A")}`);
  process.exit(STRUCTURAL_EXIT_CODE);
}

const [environment] = process.argv.slice(2);

if (!environment || !(environment in PROJECTS)) {
  failStructurally(
    `Environment must be one of ${Object.keys(PROJECTS).join(", ")}, got "${environment ?? ""}".`,
  );
}

const {projectId, publishScript} = PROJECTS[environment];

let swiftSource;
try {
  swiftSource = await readFile(FLAG_SOURCE_PATH, "utf8");
} catch (error) {
  failStructurally(`Cannot read ${FLAG_SOURCE_PATH}: ${error.message}`);
}

const appKeys = appFlagKeys(swiftSource);

if (appKeys.length === 0) {
  failStructurally(
    "Parsed no flag keys out of RemoteFeatureFlag.swift. Passing here would mean asserting " +
      "nothing, which is how this class of gap opens in the first place.",
  );
}

let raw;
try {
  // FIREBASE_TOKEN is read straight from the inherited environment by firebase-tools, so it
  // is deliberately not passed as an argument - a CI credential does not belong in the
  // runner's process argument list. A developer running this locally is already logged in.
  raw = execFileSync(
    "npx",
    ["-y", FIREBASE_TOOLS, "remoteconfig:get", "--project", projectId, "--json"],
    {cwd: REPO_ROOT, encoding: "utf8", stdio: ["ignore", "pipe", "inherit"]},
  );
} catch (error) {
  // Deliberately structural rather than a pass. A check that cannot reach the
  // backend has not verified anything, and "could not look" must never read as
  // "looks fine" - that is the failure this script exists to end.
  failStructurally(
    `Could not read the live Remote Config template for ${projectId}: ${error.message}`,
  );
}

let liveTemplate;
try {
  liveTemplate = JSON.parse(raw);
} catch {
  failStructurally(`Could not parse the live template for ${projectId}. Raw output:\n${raw}`);
}

const problems = unpublishedFlagProblems(liveTemplate, appKeys);

if (problems.length > 0) {
  for (const problem of problems) {
    console.error(`::error::${problem}`);
  }
  // A workflow command ends at its first newline, so the remediation would be stranded in
  // the raw log - the least visible place at the moment someone needs it. Keep the
  // annotation to one line and print the command separately.
  console.error(
    `::error::${problems.length} of ${appKeys.length} kill switch(es) are unreachable in ` +
      `${projectId}. Publish the template before archiving: ` +
      `cd scripts && npm run ${publishScript} -- --apply (see docs/remote-config-kill-switches.md).`,
  );
  console.error(`  cd scripts && npm run ${publishScript} -- --apply`);
  console.error("  See docs/remote-config-kill-switches.md.");
  process.exit(1);
}

console.log(
  `Verified all ${appKeys.length} kill switch(es) are published in ${projectId} as BOOLEAN ` +
    "parameters carrying a backend default the client can resolve.",
);
