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

function contractPaths(workflow) {
  const block = workflow.match(
    /# required-check-paths:start\n(?<paths>[\s\S]*?)# required-check-paths:end/,
  )?.groups?.paths;

  assert.ok(block, "workflow must contain the required-check path contract");

  const paths = [...block.matchAll(/^\s*-\s+"(?<path>[^"]+)"\s*$/gm)].map(
    (match) => match.groups.path,
  );

  assert.ok(paths.length > 0, "required-check path contract must not be empty");
  assert.equal(
    new Set(paths).size,
    paths.length,
    "required-check path contract must not contain duplicates",
  );

  return paths;
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

test("fallback path contract exactly matches the real CI trigger", () => {
  assert.deepEqual(contractPaths(fallbackWorkflow), contractPaths(ciWorkflow));
});

test("fallback claims the required name only after a successful non-CI route", () => {
  const safeRoute =
    "needs.route.result == 'success' && needs.route.outputs.ci_relevant == 'false'";

  assert.ok(
    fallbackWorkflow.includes(
      `name: \${{ ${safeRoute} && 'iOS Verify (Staging)'`,
    ),
  );
  assert.ok(fallbackWorkflow.includes(`if: ${safeRoute}`));
  assert.doesNotMatch(fallbackWorkflow, /^\s+paths(?:-ignore)?:/m);
});

test("required check routing is mutually exclusive and exhaustive", () => {
  const patterns = contractPaths(ciWorkflow);
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
  ];

  for (const scenario of scenarios) {
    const realCI = routesToRealCI(scenario.paths, patterns);
    const fallback = !realCI;

    assert.equal(realCI, scenario.realCI, scenario.name);
    assert.notEqual(realCI, fallback, `${scenario.name} must route only once`);
    assert.equal(
      Number(realCI) + Number(fallback),
      1,
      `${scenario.name} must always route to one required check`,
    );
  }
});
