import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const ciWorkflow = readFileSync(
  new URL("../../.github/workflows/ci.yml", import.meta.url),
  "utf8",
);
const fallbackWorkflow = readFileSync(
  new URL(
    "../../.github/workflows/ci-required-check-fallback.yml",
    import.meta.url,
  ),
  "utf8",
);

// The routing model understands exactly two pattern shapes: a `dir/**` prefix
// and an exact literal. Anything else has to fail loudly rather than degrade
// into a literal comparison that models neither GitHub nor dorny/paths-filter.
function assertSupportedPattern(pattern, source) {
  const isPrefix =
    pattern.endsWith("/**") && !pattern.slice(0, -3).includes("*");
  const isLiteral = !pattern.includes("*");

  assert.ok(
    isPrefix || isLiteral,
    `${source} uses the glob "${pattern}", which this routing model cannot evaluate. Use a literal path or a "dir/**" prefix, or teach pathMatchesPattern the new shape.`,
  );
}

function contractPaths(workflow, source) {
  const block = workflow.match(
    /# required-check-paths:start\n(?<paths>[\s\S]*?)# required-check-paths:end/,
  )?.groups?.paths;

  assert.ok(block, `${source} must contain the required-check path contract`);

  const paths = [...block.matchAll(/^\s*-\s+"(?<path>[^"]+)"\s*$/gm)].map(
    (match) => match.groups.path,
  );

  assert.ok(
    paths.length > 0,
    `${source} required-check path contract must not be empty`,
  );
  assert.equal(
    new Set(paths).size,
    paths.length,
    `${source} required-check path contract must not contain duplicates`,
  );

  for (const path of paths) {
    assertSupportedPattern(path, `${source} required-check path contract`);
  }

  return paths;
}

// The workflow-level trigger is only one of ci.yml's path sources. Every
// job-level dorny filter also declares paths ci.yml treats as CI-relevant, and
// a path that reaches a verify job without reaching the trigger never runs.
function ciFilterPatterns(workflow) {
  const filters = new Map();
  let blockIndent = null;
  let currentFilter = null;

  for (const line of workflow.split("\n")) {
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

// Parsing that silently finds nothing would make every coverage assertion pass
// vacuously, so the discovered filters are pinned to the outputs the `changes`
// job publishes.
function declaredFilterOutputs(workflow) {
  const outputs = [
    ...workflow.matchAll(
      /^\s*(?<output>[A-Za-z0-9_-]+):\s*\$\{\{\s*steps\.filter\.outputs\.(?<filter>[A-Za-z0-9_-]+)\s*\}\}\s*$/gm,
    ),
  ].map((match) => match.groups.filter);

  assert.ok(
    outputs.length > 0,
    "ci.yml must publish the dorny filter results as job outputs",
  );

  return outputs;
}

function jobName(workflow, jobId) {
  const lines = workflow.split("\n");
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

function pathMatchesPattern(path, pattern) {
  if (pattern.endsWith("/**")) {
    const directory = pattern.slice(0, -3);
    return path === directory || path.startsWith(`${directory}/`);
  }

  return path === pattern;
}

function routesToRealCI(paths, patterns) {
  return paths.some((path) =>
    patterns.some((pattern) => pathMatchesPattern(path, pattern)),
  );
}

// Covered means every path the pattern can match also reaches the contract. A
// `dir/**` pattern matches arbitrarily deep paths, so only a contract prefix at
// or above `dir` covers it - a literal contract entry never can.
function contractCovers(pattern, contract) {
  if (pattern.endsWith("/**")) {
    const directory = pattern.slice(0, -3);

    return contract.some(
      (entry) => entry.endsWith("/**") && pathMatchesPattern(directory, entry),
    );
  }

  return routesToRealCI([pattern], contract);
}

test("fallback path contract exactly matches the real CI trigger", () => {
  assert.deepEqual(
    contractPaths(fallbackWorkflow, "ci-required-check-fallback.yml"),
    contractPaths(ciWorkflow, "ci.yml"),
  );
});

test("every path ci.yml treats as CI-relevant is in the required-check contract", () => {
  const contract = contractPaths(ciWorkflow, "ci.yml");
  const filters = ciFilterPatterns(ciWorkflow);

  for (const filter of declaredFilterOutputs(ciWorkflow)) {
    assert.ok(
      filters.get(filter)?.length,
      `ci.yml publishes the "${filter}" filter output but no paths were parsed for it - the contract coverage check would pass vacuously`,
    );
  }

  for (const [filter, patterns] of filters) {
    for (const pattern of patterns) {
      assertSupportedPattern(pattern, `ci.yml "${filter}" filter`);
      assert.ok(
        contractCovers(pattern, contract),
        `ci.yml's "${filter}" filter treats "${pattern}" as CI-relevant, but the required-check contract omits it. A PR touching only that path would let the fallback claim the required check while its verify job never runs.`,
      );
    }
  }
});

test("the fallback claims the real iOS job's exact check name", () => {
  const requiredCheckName = jobName(ciWorkflow, "ios-verify");
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

test("fallback claims the required name only after a successful non-CI route", () => {
  const safeRoute =
    "needs.route.result == 'success' && needs.route.outputs.ci_relevant == 'false'";
  const requiredCheckName = jobName(ciWorkflow, "ios-verify");

  assert.ok(
    fallbackWorkflow.includes(
      `name: \${{ ${safeRoute} && '${requiredCheckName}'`,
    ),
  );
  assert.ok(fallbackWorkflow.includes(`if: ${safeRoute}`));
  assert.doesNotMatch(fallbackWorkflow, /^\s+paths(?:-ignore)?:/m);
});

test("required check routing is mutually exclusive and exhaustive", () => {
  const patterns = contractPaths(ciWorkflow, "ci.yml");
  const scenarios = [
    {
      name: "iOS code only",
      paths: ["AscendApp/Features/Home/HomeView.swift"],
      realCI: true,
    },
    {
      name: "server code only",
      paths: ["functions/src/index.ts"],
      realCI: true,
    },
    {
      name: "widget code only",
      paths: ["AscendLiveActivityWidgets/AscendLiveActivityWidget.swift"],
      realCI: true,
    },
    {
      name: "Firestore index only",
      paths: ["firestore.indexes.json"],
      realCI: true,
    },
    {
      name: "docs only",
      paths: ["README.md", "docs/release-process.md"],
      realCI: false,
    },
    {
      name: "App Store assets only",
      paths: ["AppStoreAssets/en-US/01.png"],
      realCI: false,
    },
    {
      name: "mixed code and docs",
      paths: ["AscendApp/App/AscendApp.swift", "docs/architecture.md"],
      realCI: true,
    },
    {
      name: "workflow change",
      paths: [".github/workflows/ci.yml"],
      realCI: true,
    },
    {
      name: "commerce doc the scripts suite asserts against",
      paths: ["docs/superwall-paywall-setup.md"],
      realCI: true,
    },
    {
      name: "project guide the scripts suite asserts against",
      paths: ["CLAUDE.md"],
      realCI: true,
    },
  ];

  for (const scenario of scenarios) {
    assert.equal(
      routesToRealCI(scenario.paths, patterns),
      scenario.realCI,
      scenario.name,
    );
  }
});
