import assert from "node:assert/strict";

// The workflow-level trigger is only one of ci.yml's path sources. Every
// job-level dorny filter also declares paths ci.yml treats as CI-relevant, and
// a path that reaches a verify job without reaching the trigger never runs.
export function ciFilterPatterns(ciWorkflow) {
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
