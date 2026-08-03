import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  CI_RELEVANT_PATHS,
  VERIFICATION_IRRELEVANT_PATHS,
  assertSupportedPattern,
  changedPathsFromApiEntries,
  classifyChangedPaths,
  matchesPattern,
} from "../lib/required-check-routing.mjs";

function repositoryFile(path) {
  return readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
}

const ciWorkflow = repositoryFile(".github/workflows/ci.yml");
const fallbackWorkflow = repositoryFile(
  ".github/workflows/ci-required-check-fallback.yml",
);
const classifierScript = repositoryFile(
  "scripts/ci/classify-required-check-route.mjs",
);

function ciTriggerPaths() {
  const block = ciWorkflow.match(
    /# required-check-paths:start\n(?<paths>[\s\S]*?)# required-check-paths:end/,
  )?.groups?.paths;

  assert.ok(block, "ci.yml must contain the required-check path contract");

  const paths = [...block.matchAll(/^\s*-\s+"(?<path>[^"]+)"\s*$/gm)].map(
    (match) => match.groups.path,
  );

  assert.ok(paths.length > 0, "ci.yml path contract must not be empty");
  assert.equal(
    new Set(paths).size,
    paths.length,
    "ci.yml path contract must not contain duplicates",
  );

  return paths;
}

// The workflow-level trigger is only one of ci.yml's path sources. Every
// job-level dorny filter also declares paths ci.yml treats as CI-relevant, and
// a path that reaches a verify job without reaching the trigger never runs.
function ciFilterPatterns() {
  const filters = new Map();
  let blockIndent = null;
  let currentFilter = null;

  for (const line of ciWorkflow.split("\n")) {
    const blockStart = line.match(/^(?<indent>\s*)filters:\s*\|\s*$/);

    if (blockStart) {
      blockIndent = blockStart.groups.indent.length;
      currentFilter = null;
      continue;
    }

    if (blockIndent === null || line.trim() === "") {
      continue;
    }

    const indent = line.length - line.trimStart().length;

    if (indent <= blockIndent) {
      blockIndent = null;
      currentFilter = null;
      continue;
    }

    const filterName = line.match(/^\s*(?<name>[A-Za-z0-9_-]+):\s*$/)?.groups
      ?.name;

    if (filterName) {
      currentFilter = filterName;
      filters.set(currentFilter, filters.get(currentFilter) ?? []);
      continue;
    }

    const entry = line.match(/^\s*-\s+"(?<path>[^"]+)"\s*$/)?.groups?.path;

    if (entry) {
      assert.ok(
        currentFilter,
        `ci.yml declares the filter path "${entry}" outside any named filter`,
      );
      filters.get(currentFilter).push(entry);
      continue;
    }

    assert.match(
      line.trim(),
      /^#/,
      `ci.yml filter block line "${line.trim()}" is neither a filter name, a quoted path, nor a comment - the routing model cannot classify it`,
    );
  }

  return filters;
}

// Parsing that silently finds nothing would make the coverage assertions pass
// vacuously, so the discovered filters are pinned to the outputs the `changes`
// job publishes.
function declaredFilterOutputs() {
  const outputs = [
    ...ciWorkflow.matchAll(
      /^\s*[A-Za-z0-9_-]+:\s*\$\{\{\s*steps\.filter\.outputs\.(?<filter>[A-Za-z0-9_-]+)\s*\}\}\s*$/gm,
    ),
  ].map((match) => match.groups.filter);

  assert.ok(
    outputs.length > 0,
    "ci.yml must publish the dorny filter results as job outputs",
  );

  return outputs;
}

function jobBody(jobId) {
  const lines = ciWorkflow.split("\n");
  const start = lines.findIndex((line) => line === `  ${jobId}:`);

  assert.notEqual(start, -1, `ci.yml must declare a "${jobId}" job`);

  const body = [];

  for (const line of lines.slice(start + 1)) {
    if (line.trim() !== "" && !line.startsWith("    ")) {
      break;
    }

    body.push(line);
  }

  return body.join("\n");
}

function jobName(jobId) {
  const name = jobBody(jobId).match(
    /^ {4}name:\s+(?<name>.+?)\s*$/m,
  )?.groups?.name;

  assert.ok(name, `ci.yml job "${jobId}" must declare a display name`);

  return name;
}

// Covered means every path the pattern can match also reaches the contract. A
// `dir/**` pattern matches arbitrarily deep paths, so only a contract prefix at
// or above `dir` covers it - a literal contract entry never can.
function contractCovers(pattern) {
  if (pattern.endsWith("/**")) {
    const directory = pattern.slice(0, -3);

    return CI_RELEVANT_PATHS.some(
      (entry) =>
        entry.endsWith("/**") &&
        (entry === pattern || matchesPattern(directory, entry)),
    );
  }

  return CI_RELEVANT_PATHS.some((entry) => matchesPattern(pattern, entry));
}

test("the routing contract exactly matches ci.yml's trigger", () => {
  assert.deepEqual(CI_RELEVANT_PATHS, ciTriggerPaths());
});

test("every path ci.yml treats as CI-relevant is in the routing contract", () => {
  const filters = ciFilterPatterns();

  for (const filter of declaredFilterOutputs()) {
    assert.ok(
      filters.get(filter)?.length,
      `ci.yml publishes the "${filter}" filter output but no paths were parsed for it - the contract coverage check would pass vacuously`,
    );
  }

  for (const [filter, patterns] of filters) {
    for (const pattern of patterns) {
      assertSupportedPattern(pattern, `ci.yml "${filter}" filter`);
      assert.ok(
        contractCovers(pattern),
        `ci.yml's "${filter}" filter treats "${pattern}" as CI-relevant, but the routing contract omits it. A PR touching only that path could reach the fallback while its verify job never runs.`,
      );
    }
  }
});

test("the pattern guard rejects every glob shape the model cannot evaluate", () => {
  for (const pattern of [
    "!docs/**",
    "docs/*.md",
    "docs/?.md",
    "docs/[ab].md",
    "web/{a,b}.astro",
    "AscendApp/**/*.swift",
    "@(docs|web)/**",
    "**",
    "/**",
    "",
  ]) {
    assert.throws(
      () => assertSupportedPattern(pattern, "test"),
      `"${pattern}" must be rejected rather than modelled as a literal filename`,
    );
  }

  for (const pattern of ["docs/**", "CLAUDE.md", "firestore.indexes.json"]) {
    assert.doesNotThrow(() => assertSupportedPattern(pattern, "test"));
  }
});

test("the fallback derives required check names from the real iOS jobs", () => {
  assert.match(
    fallbackWorkflow,
    /node scripts\/ci\/list-required-check-contexts\.mjs \.github\/workflows\/ci\.yml/,
  );
  assert.match(
    fallbackWorkflow,
    /context: \$\{\{ fromJSON\(needs\.route\.outputs\.required_contexts\) \}\}/,
  );

  for (const jobId of ["ios-verify", "ios-verify-release"]) {
    assert.doesNotMatch(
      fallbackWorkflow,
      new RegExp(`['\"]${jobName(jobId).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}['\"]`),
      `${jobId}'s context must come from ci.yml instead of being copied into the fallback`,
    );
  }
});

test("fallback claims each derived name only after a successful eligible route", () => {
  const safeRoute =
    "needs.route.result == 'success' && needs.route.outputs.fallback_eligible == 'true'";

  assert.ok(
    fallbackWorkflow.includes(
      `name: \${{ ${safeRoute} && matrix.context || 'iOS Verify Fallback (Not Required)' }}`,
    ),
  );
  assert.ok(fallbackWorkflow.includes(`if: ${safeRoute}`));
  assert.doesNotMatch(fallbackWorkflow, /^\s+paths(?:-ignore)?:/m);
});

test("the fallback routes through the classifier this suite covers", () => {
  assert.match(
    fallbackWorkflow,
    /node scripts\/ci\/classify-required-check-route\.mjs/,
    "the fallback must decide eligibility with the tested classifier",
  );
  assert.match(
    classifierScript,
    /from "\.\.\/lib\/required-check-routing\.mjs"/,
    "the classifier must decide eligibility with the tested routing module",
  );
  assert.match(
    fallbackWorkflow,
    /fallback_eligible: \$\{\{ steps\.classify\.outputs\.fallback_eligible \}\}/,
    "the route job must publish the classifier's verdict as its output",
  );
});

test("CI-relevant changes never reach the fallback", () => {
  const scenarios = [
    ["iOS code only", ["AscendApp/Features/Home/HomeView.swift"]],
    ["server code only", ["functions/src/index.ts"]],
    [
      "widget code only",
      ["AscendLiveActivityWidgets/AscendLiveActivityWidget.swift"],
    ],
    ["Firestore index only", ["firestore.indexes.json"]],
    ["Firestore rules only", ["firestore.rules"]],
    ["Storage rules only", ["storage.rules"]],
    ["Firebase config only", ["firebase.json"]],
    ["Firebase project aliases only", [".firebaserc"]],
    ["rules tests only", ["tests/firebase-rules/workout-contract.test.mjs"]],
    ["Gemfile only", ["Gemfile"]],
    ["Gemfile lock only", ["Gemfile.lock"]],
    ["Fastlane config only", ["fastlane/Fastfile"]],
    ["Ruby version only", [".ruby-version"]],
    ["workflow change", [".github/workflows/ci.yml"]],
    ["mixed code and docs", ["AscendApp/App/AscendApp.swift", "docs/plan.md"]],
    [
      "commerce doc the scripts suite asserts against",
      ["docs/superwall-paywall-setup.md"],
    ],
    [
      "project guide the scripts suite asserts against",
      ["CLAUDE.md", "docs/release-process.md"],
    ],
    ["the AGENTS.md symlink to that guide", ["AGENTS.md"]],
  ];

  for (const [name, paths] of scenarios) {
    const result = classifyChangedPaths(paths);

    assert.equal(result.fallbackEligible, false, name);
    assert.ok(
      result.blockedBy.length > 0,
      `${name} must name the paths that kept the fallback out`,
    );
  }
});

test("only explicitly allowlisted changes let the fallback claim the check", () => {
  const eligible = [
    ["ungated docs only", ["docs/release-process.md"]],
    ["nested docs only", ["docs/quality/contracts/issue-241.md"]],
    ["App Store assets only", ["AppStoreAssets/screenshots/01.png"]],
    ["readme only", ["README.md"]],
    ["docs and assets", ["README.md", "AppStoreAssets/qa/review.md"]],
    [
      "App Store product copy package",
      ["data/ascend-support-page-and-product-page-package/app-store-copy.md"],
    ],
    ["project skills only", [".claude/skills/ascend-deploy/SKILL.md"]],
    ["gitignore only", [".gitignore"]],
  ];

  for (const [name, paths] of eligible) {
    assert.equal(classifyChangedPaths(paths).fallbackEligible, true, name);
  }
});

test("deployment inputs route to real verification rather than the fallback", () => {
  const deploymentInputs = [
    "firestore.rules",
    "storage.rules",
    "firestore.indexes.json",
    "firebase.json",
    ".firebaserc",
    "tests/firebase-rules/workout-contract.test.mjs",
    "Gemfile",
    "Gemfile.lock",
    "fastlane/Fastfile",
    "fastlane/Matchfile",
    // Selects the Ruby that resolves the Gemfile, so it picks the Fastlane
    // build and signing toolchain despite looking like trivia.
    ".ruby-version",
  ];

  for (const path of deploymentInputs) {
    const result = classifyChangedPaths([path]);

    assert.equal(
      result.fallbackEligible,
      false,
      `${path} must route to real CI`,
    );
    assert.deepEqual(result.blockedBy, [path]);
  }

  assert.equal(
    classifyChangedPaths(["docs/plan.md", "firestore.rules"]).fallbackEligible,
    false,
    "one deployment input must route an otherwise allowlisted diff to real CI",
  );
});

test("deployment verify jobs execute the required checks", () => {
  const firebaseJob = jobBody("firebase-verify");
  const rubyJob = jobBody("ruby-verify");

  assert.match(firebaseJob, /if: needs\.changes\.outputs\.firebase == 'true'/);
  assert.match(firebaseJob, /run: npm ci --ignore-scripts/);
  assert.match(firebaseJob, /run: node scripts\/ci\/validate-firebase-config\.mjs/);
  assert.match(firebaseJob, /run: npm run test:firebase-rules/);
  assert.match(rubyJob, /if: needs\.changes\.outputs\.ruby == 'true'/);
  assert.match(rubyJob, /uses: ruby\/setup-ruby@v1/);
  assert.match(
    rubyJob,
    /run: bundle install --deployment --jobs 4 --retry 3/,
  );
  assert.match(rubyJob, /run: bundle exec fastlane lanes/);
});

test("unclassified paths fail closed", () => {
  const unlisted = [
    ["a brand new top-level directory", ["marketing/launch-plan.md"]],
    ["a new root file", ["Package.swift"]],
    ["harness configuration outside skills", [".claude/settings.json"]],
    ["data outside the allowlisted copy package", ["data/scratch-notes.md"]],
    ["a partly allowlisted diff", ["docs/plan.md", "marketing/plan.md"]],
    ["a file named like an allowlisted directory", ["docs"]],
  ];

  for (const [name, paths] of unlisted) {
    assert.equal(classifyChangedPaths(paths).fallbackEligible, false, name);
  }

  for (const [name, paths] of [
    ["an empty diff", []],
    ["a missing diff", undefined],
    ["an unreadable entry", [""]],
    ["a non-string entry", [null]],
  ]) {
    assert.equal(classifyChangedPaths(paths).fallbackEligible, false, name);
  }
});

test("a truncated or unreadable file list is refused, never classified", () => {
  const refusals = [
    ["a diff capped by the API", [{ filename: "docs/plan.md" }], 3000],
    ["more entries than the PR reports", [{ filename: "a" }, { filename: "b" }], 1],
    ["a non-array payload", { files: [] }, 0],
    ["a null payload", null, 0],
    ["an entry with no filename", [{ status: "added" }], 1],
    ["an entry with an empty filename", [{ filename: "" }], 1],
    ["a non-string filename", [{ filename: 7 }], 1],
    ["an empty previous_filename", [{ filename: "a", previous_filename: "" }], 1],
    [
      "a non-string previous_filename",
      [{ filename: "a", previous_filename: 7 }],
      1,
    ],
    ["a negative count", [], -1],
    ["a non-numeric count", [{ filename: "a" }], "one"],
    ["a partly numeric count", [{ filename: "a" }], "1abc"],
    ["a fractional count", [{ filename: "a" }], 1.5],
    ["a missing count", [{ filename: "a" }], undefined],
    ["a null count", [{ filename: "a" }], null],
  ];

  for (const [name, entries, expected] of refusals) {
    const result = changedPathsFromApiEntries(entries, expected);

    assert.equal(result.ok, false, name);
    assert.equal(typeof result.reason, "string", `${name} must explain itself`);
    assert.equal(result.paths, undefined, `${name} must yield no paths`);
  }
});

test("renames contribute both of their paths", () => {
  const renamedOut = changedPathsFromApiEntries(
    [{ filename: "docs/moved.md", previous_filename: "AscendApp/Moved.swift" }],
    1,
  );

  assert.deepEqual(renamedOut.paths, [
    "docs/moved.md",
    "AscendApp/Moved.swift",
  ]);
  assert.equal(
    classifyChangedPaths(renamedOut.paths).fallbackEligible,
    false,
    "moving a Swift file out of AscendApp/ is still an iOS change",
  );

  const plain = changedPathsFromApiEntries(
    [{ filename: "docs/a.md" }, { filename: "docs/b.md" }],
    2,
  );

  assert.deepEqual(plain.paths, ["docs/a.md", "docs/b.md"]);

  const duplicated = changedPathsFromApiEntries(
    [
      { filename: "docs/a.md", previous_filename: "docs/b.md" },
      { filename: "docs/b.md" },
    ],
    2,
  );

  assert.deepEqual(duplicated.paths, ["docs/a.md", "docs/b.md"]);
});

test("the classifier entry point publishes and fails closed end to end", () => {
  const script = fileURLToPath(
    new URL("../ci/classify-required-check-route.mjs", import.meta.url),
  );
  const workspace = mkdtempSync(join(tmpdir(), "required-check-route-"));

  function run(payload, expectedCount, { omitArguments = false } = {}) {
    const filesPath = join(workspace, "files.json");
    const outputPath = join(workspace, "github-output");

    writeFileSync(filesPath, payload);
    writeFileSync(outputPath, "");

    const result = spawnSync(
      process.execPath,
      omitArguments ? [script] : [script, filesPath, String(expectedCount)],
      { encoding: "utf8", env: { ...process.env, GITHUB_OUTPUT: outputPath } },
    );

    return {
      status: result.status,
      stderr: result.stderr,
      output: readFileSync(outputPath, "utf8").trim(),
    };
  }

  const eligible = run(
    JSON.stringify([{ filename: "docs/plan.md" }, { filename: ".gitignore" }]),
    2,
  );

  assert.equal(eligible.status, 0);
  assert.equal(eligible.output, "fallback_eligible=true");

  const blocked = run(JSON.stringify([{ filename: "firestore.rules" }]), 1);

  assert.equal(blocked.status, 0);
  assert.equal(blocked.output, "fallback_eligible=false");

  const ciRelevant = run(
    JSON.stringify([{ filename: "AscendApp/App/AscendApp.swift" }]),
    1,
  );

  assert.equal(ciRelevant.status, 0);
  assert.equal(ciRelevant.output, "fallback_eligible=false");

  // Every one of these must exit non-zero and publish nothing: the routing job
  // then fails, and the fallback's `if:` guard keeps it from claiming the name.
  const refusals = [
    ["a truncated diff", JSON.stringify([{ filename: "docs/plan.md" }]), 3000],
    ["malformed JSON", "not json", 1],
    ["a non-array payload", JSON.stringify({}), 0],
    ["an entry with no filename", JSON.stringify([{ status: "added" }]), 1],
    ["a non-numeric count", JSON.stringify([{ filename: "docs/a.md" }]), "one"],
  ];

  for (const [name, payload, expectedCount] of refusals) {
    const refused = run(payload, expectedCount);

    assert.notEqual(refused.status, 0, name);
    assert.equal(refused.output, "", `${name} must publish no verdict`);
    assert.match(refused.stderr, /^::error::/m, `${name} must annotate why`);
  }

  const withoutArguments = run("[]", 0, { omitArguments: true });

  assert.notEqual(withoutArguments.status, 0);
  assert.equal(withoutArguments.output, "");

  const missingFile = spawnSync(
    process.execPath,
    [script, join(workspace, "absent.json"), "1"],
    { encoding: "utf8" },
  );

  assert.notEqual(missingFile.status, 0);
  assert.match(missingFile.stderr, /^::error::/m);
});

test("the allowlist never overrides the CI trigger", () => {
  for (const pattern of CI_RELEVANT_PATHS) {
    const path = pattern.endsWith("/**")
      ? `${pattern.slice(0, -3)}/probe.txt`
      : pattern;

    assert.equal(
      classifyChangedPaths([path]).fallbackEligible,
      false,
      `"${path}" is CI-relevant and must route to ci.yml even when an allowlist entry also covers it`,
    );
  }

  assert.ok(
    VERIFICATION_IRRELEVANT_PATHS.length > 0,
    "the allowlist must not be empty",
  );
});
