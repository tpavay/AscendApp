/**
 * The relocated-DerivedData contract.
 *
 * Local builds pass `-derivedDataPath "$PWD/.build/dd"` so Xcode's output dies
 * with the throwaway worktree that produced it instead of orphaning ~9 GiB
 * under `~/Library/Developer/Xcode/DerivedData` forever. That relocation puts
 * the Firebase Crashlytics `run` binary inside `SRCROOT`, where
 * `ENABLE_USER_SCRIPT_SANDBOXING` denies an undeclared read, so the Crashlytics
 * phase declares the path in `inputPaths`.
 *
 * Those two facts are coupled by a hardcoded directory name. Rename `.build/dd`
 * in the documented commands alone and the declaration stops covering the file
 * Xcode actually reads; every local build then fails with
 * `Sandbox: bash deny(1) file-read-data`, which names a path rather than the
 * rename that caused it. Nothing in the build system can notice, because the
 * project file's literal and the documented flag never meet. This test is where
 * they meet.
 *
 * The sandboxing assertion is part of the coupling, not decoration: the
 * `inputPaths` entry exists only because user script sandboxing is on. If it is
 * ever turned off, the declaration's whole reason goes away and the trade should
 * be revisited deliberately rather than discovered later.
 */

import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {join} from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";

import {buildConfigurations, settingValue} from "../lib/monetization-build-settings.mjs";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
const projectPath = join(repositoryRoot, "AscendApp.xcodeproj/project.pbxproj");
const mixpanelScriptPath = join(repositoryRoot, "scripts/ci/assert-mixpanel-build-settings.mjs");

// The Crashlytics `run` binary, relative to whichever DerivedData directory
// resolved the Swift packages. Everything before this suffix is the part that
// has to agree with the documented flag.
const CRASHLYTICS_RUN_SUFFIX = "/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run";

// The one anchor that is correct for `build`, `test` AND `archive`. `$(BUILD_DIR)`
// is not: under `archive` it points into ArchiveIntermediates and stripping
// components off it lands on a directory holding no SourcePackages at all.
const CRASHLYTICS_INPUT_ANCHOR = "$(SRCROOT)/";

// Every file carrying a local `xcodebuild` command a human or an agent is meant
// to copy. Docs that merely describe what CI runs are deliberately absent: CI
// keeps the default DerivedData so its `actions/cache` on
// `~/Library/Developer/Xcode/DerivedData/**/SourcePackages` keeps hitting.
const DOCUMENTED_COMMAND_FILES = [
  "CLAUDE.md",
  ".claude/skills/live-climb-content/SKILL.md"
];

const FENCED_BLOCK_PATTERN = /^```[^\n]*\n([\s\S]*?)^```/gm;
const DERIVED_DATA_FLAG_PATTERN = /-derivedDataPath\s+"\$PWD\/([^"]+)"/g;

/** The `inputPaths` entries of the shell script phase that runs Crashlytics. */
async function crashlyticsInputPaths() {
  const project = await readFile(projectPath, "utf8");
  const phases = [
    ...project.matchAll(
      /isa = PBXShellScriptBuildPhase;([\s\S]*?)\n\t\t\};/g
    )
  ].map(([, body]) => body);

  const crashlyticsPhases = phases.filter((body) =>
    body.includes("Crashlytics/run")
  );

  assert.equal(
    crashlyticsPhases.length,
    1,
    "exactly one shell script phase may run the Crashlytics upload"
  );

  const inputPaths = crashlyticsPhases[0].match(
    /inputPaths = \(\n([\s\S]*?)\n\t\t\t\);/
  );

  assert.ok(inputPaths, "the Crashlytics phase must declare inputPaths");

  return inputPaths[1]
    .split("\n")
    .map((line) => line.trim().replace(/,$/, "").replace(/^"(.*)"$/, "$1"))
    .filter((entry) => entry.length > 0);
}

/** Every `xcodebuild` invocation inside a fenced block, continuations joined. */
function xcodebuildCommands(markdown) {
  const commands = [];

  for (const [, block] of markdown.matchAll(FENCED_BLOCK_PATTERN)) {
    const lines = block.split("\n");

    for (let index = 0; index < lines.length; index += 1) {
      if (!/(?:^|\s)xcodebuild(?:\s|$)/.test(lines[index])) {
        continue;
      }

      let command = lines[index];
      while (command.trimEnd().endsWith("\\") && index + 1 < lines.length) {
        index += 1;
        command = `${command.trimEnd().slice(0, -1)} ${lines[index].trim()}`;
      }

      commands.push(command.trim());
    }
  }

  return commands;
}

/** The directory the project file expects DerivedData to have been relocated to. */
async function declaredDerivedDataDirectory() {
  const entries = await crashlyticsInputPaths();
  const declared = entries.filter((entry) => entry.endsWith(CRASHLYTICS_RUN_SUFFIX));

  assert.equal(
    declared.length,
    1,
    "the Crashlytics phase must declare exactly one path to the `run` binary"
  );

  const entry = declared[0];
  assert.ok(
    entry.startsWith(CRASHLYTICS_INPUT_ANCHOR),
    `the Crashlytics input must anchor on ${CRASHLYTICS_INPUT_ANCHOR}, got "${entry}"`
  );

  return entry.slice(CRASHLYTICS_INPUT_ANCHOR.length, -CRASHLYTICS_RUN_SUFFIX.length);
}

test("the Crashlytics phase declares the relocated `run` binary as a script input", async () => {
  const entries = await crashlyticsInputPaths();

  assert.ok(
    entries.includes(
      "$(SRCROOT)/.build/dd/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
    ),
    "without this declaration every local build fails with `Sandbox: bash deny(1) file-read-data`"
  );
});

test("user script sandboxing stays on, which is why the declaration exists", async () => {
  const project = await readFile(projectPath, "utf8");
  const sandboxed = new Map();

  for (const {name, buildSettings} of buildConfigurations(project)) {
    const value = settingValue(buildSettings, "ENABLE_USER_SCRIPT_SANDBOXING");
    if (value !== null) {
      sandboxed.set(name, value);
    }
  }

  assert.deepEqual(
    [...sandboxed.keys()].sort(),
    ["Debug", "Release", "Staging"],
    "every configuration must state ENABLE_USER_SCRIPT_SANDBOXING explicitly"
  );

  for (const [name, value] of sandboxed) {
    assert.equal(
      value,
      "YES",
      `${name} turned user script sandboxing off, so the Crashlytics inputPaths ` +
        "declaration no longer has a reason to exist and the trade needs revisiting"
    );
  }
});

test("every documented xcodebuild command relocates DerivedData into the worktree", async () => {
  let commandCount = 0;

  for (const file of DOCUMENTED_COMMAND_FILES) {
    const markdown = await readFile(join(repositoryRoot, file), "utf8");
    const commands = xcodebuildCommands(markdown);

    assert.ok(
      commands.length > 0,
      `${file} must still document at least one xcodebuild command`
    );

    for (const command of commands) {
      assert.match(
        command,
        /-derivedDataPath "\$PWD\/[^"]+"/,
        `${file} documents an xcodebuild command with no -derivedDataPath, which ` +
          "orphans ~9 GiB of DerivedData for every throwaway worktree it runs in: " +
          command
      );
      commandCount += 1;
    }
  }

  assert.ok(commandCount >= 3, "the documented build, test and content commands must all be covered");
});

test("the project file and the documented flag name the same directory", async () => {
  const declaredDirectory = await declaredDerivedDataDirectory();

  assert.equal(
    declaredDirectory,
    ".build/dd",
    "renaming this directory means changing the project file and every documented command together"
  );

  for (const file of DOCUMENTED_COMMAND_FILES) {
    const markdown = await readFile(join(repositoryRoot, file), "utf8");
    const documented = [...markdown.matchAll(DERIVED_DATA_FLAG_PATTERN)].map(([, value]) => value);

    assert.ok(documented.length > 0, `${file} must document a -derivedDataPath value`);

    for (const value of documented) {
      assert.equal(
        value,
        declaredDirectory,
        `${file} documents -derivedDataPath "$PWD/${value}" while the Crashlytics ` +
          `inputPaths entry allows "$(SRCROOT)/${declaredDirectory}"; the sandbox ` +
          "denies the read the moment these two disagree"
      );
    }
  }
});

test("the build-settings script relocates DerivedData locally and leaves CI alone", async () => {
  const declaredDirectory = await declaredDerivedDataDirectory();
  const script = await readFile(mixpanelScriptPath, "utf8");

  assert.match(
    script,
    /GITHUB_ACTIONS/,
    "the flag must be gated on CI, whose actions/cache is keyed on the default DerivedData"
  );
  assert.match(
    script,
    /-derivedDataPath/,
    "resolving build settings locally without the flag populates the default DerivedData"
  );
  assert.ok(
    script.includes(declaredDirectory),
    `the script must resolve packages into ${declaredDirectory}, the same directory ` +
      "the project file's sandbox allowance names"
  );
});
