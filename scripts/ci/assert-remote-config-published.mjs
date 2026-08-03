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

import {annotate} from "../lib/ci-annotations.mjs";
import {appFlagKeys, unpublishedFlagProblems} from "../lib/remote-config-template.mjs";

const FIREBASE_TOOLS = "firebase-tools@15.22.1";
const STRUCTURAL_EXIT_CODE = 2;

// Both npm aliases live beside the project id so a renamed script cannot leave the remediation
// below pointing at a command that does not exist. The additive publisher comes first because
// it is the one that cannot re-enable a switch an operator has turned off: it only ever adds a
// parameter the project has never held, and refuses to write at all while any switch is off.
// The full replace is the second option, for a project that has genuinely diverged, and it is
// the one a human must read the diff before running.
const PROJECTS = {
  dev: {
    projectId: "ascend-f2e4f",
    additivePublishScript: "remoteconfig:publish-new",
    fullReplaceScript: "remoteconfig:deploy",
  },
  staging: {
    projectId: "ascend-staging-fa7d5",
    additivePublishScript: "remoteconfig:publish-new:staging",
    fullReplaceScript: "remoteconfig:deploy:staging",
  },
  prod: {
    projectId: "ascend-prod-9c8f2",
    additivePublishScript: "remoteconfig:publish-new:production",
    fullReplaceScript: "remoteconfig:deploy:production",
  },
};

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const FLAG_SOURCE_PATH = resolve(
  REPO_ROOT,
  "AscendApp/Shared/Services/RemoteConfig/RemoteFeatureFlag.swift",
);

function failStructurally(message) {
  annotate("error", message);
  process.exit(STRUCTURAL_EXIT_CODE);
}

const [environment] = process.argv.slice(2);

if (!environment || !(environment in PROJECTS)) {
  failStructurally(
    `Environment must be one of ${Object.keys(PROJECTS).join(", ")}, got "${environment ?? ""}".`,
  );
}

const {projectId, additivePublishScript, fullReplaceScript} = PROJECTS[environment];

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
    annotate("error", problem);
  }
  // A workflow command ends at its first newline, so the annotation carries the diagnosis
  // alone and the remediation follows as plain lines rather than being truncated into the
  // raw log - the least visible place at the moment someone needs it.
  annotate(
    "error",
    `${problems.length} of ${appKeys.length} kill switch(es) are unreachable in ${projectId}. ` +
      "Publish the template before archiving.",
  );
  console.error(`  cd scripts && npm run ${additivePublishScript} -- --apply`);
  console.error(
    "  That adds only the switches this project has never held, and refuses to write at all " +
      "while any switch is off - so it cannot re-enable one mid-incident.",
  );
  console.error(
    `  If ${projectId} has genuinely diverged and needs the whole template rewritten, that is ` +
      "the full replace, and it is a human's call after reading the diff:",
  );
  console.error(`  cd scripts && npm run ${fullReplaceScript} -- --apply`);
  console.error("  See docs/remote-config-kill-switches.md.");
  process.exit(1);
}

console.log(
  `Verified all ${appKeys.length} kill switch(es) are published in ${projectId} as BOOLEAN ` +
    "parameters carrying a backend default the client can resolve.",
);
