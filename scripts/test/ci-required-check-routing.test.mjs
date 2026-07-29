import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  CI_RELEVANT_PATHS,
  VERIFICATION_IRRELEVANT_PATHS,
  assertSupportedPattern,
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

function jobName(jobId) {
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

  const name = body
    .join("\n")
    .match(/^ {4}name:\s+(?<name>.+?)\s*$/m)?.groups?.name;

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

test("the fallback claims the real iOS job's exact check name", () => {
  const requiredCheckName = jobName("ios-verify");
  const claimed = fallbackWorkflow.match(
    /name:\s+\$\{\{\s*.*?&&\s*'(?<required>[^']+)'\s*\|\|\s*'(?<inert>[^']+)'\s*\}\}/,
  )?.groups;

  assert.ok(
    claimed,
    "the fallback job must name itself through a conditional expression",
  );
  assert.equal(
    claimed.required,
    requiredCheckName,
    "the fallback must claim exactly the name ci.yml's ios-verify job publishes, or renaming that job leaves CI-relevant PRs with no required check at all",
  );
  assert.notEqual(
    claimed.inert,
    requiredCheckName,
    "the fallback's non-claiming name must differ from the required check name",
  );
});

test("fallback claims the required name only after a successful eligible route", () => {
  const safeRoute =
    "needs.route.result == 'success' && needs.route.outputs.fallback_eligible == 'true'";
  const requiredCheckName = jobName("ios-verify");

  assert.ok(
    fallbackWorkflow.includes(
      `name: \${{ ${safeRoute} && '${requiredCheckName}'`,
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
    classifierScript,
    /fallback_eligible=\$\{result\.fallbackEligible\}/,
    "the classifier must publish the routing decision as fallback_eligible",
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
  ];

  for (const [name, paths] of eligible) {
    assert.equal(classifyChangedPaths(paths).fallbackEligible, true, name);
  }
});

test("unverified deployment inputs stay blocked rather than auto-greened", () => {
  // deploy-staging.yml ships every one of these on merge to develop, and no
  // ci.yml job verifies any of them. Auto-greening them would deploy security
  // rules and signing configuration with no pull-request gate at all.
  const deploymentInputs = [
    "firestore.rules",
    "storage.rules",
    "firebase.json",
    ".firebaserc",
    "Gemfile",
    "Gemfile.lock",
    "fastlane/Fastfile",
    "fastlane/Matchfile",
  ];

  for (const path of deploymentInputs) {
    const result = classifyChangedPaths([path]);

    assert.equal(
      result.fallbackEligible,
      false,
      `${path} must not be auto-greened by the fallback`,
    );
    assert.deepEqual(result.blockedBy, [path]);
  }

  assert.equal(
    classifyChangedPaths(["docs/plan.md", "firestore.rules"]).fallbackEligible,
    false,
    "one unverified deployment input must block an otherwise allowlisted diff",
  );
});

test("unclassified paths fail closed", () => {
  const unlisted = [
    ["a brand new top-level directory", ["marketing/launch-plan.md"]],
    ["a new root file", ["Package.swift"]],
    ["a dotfile", [".gitignore"]],
    ["project skills", [".claude/skills/ascend-deploy/SKILL.md"]],
    ["the product copy package", ["data/app-store-copy.md"]],
    ["rules tests", ["tests/firebase-rules/firestore.test.mjs"]],
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
