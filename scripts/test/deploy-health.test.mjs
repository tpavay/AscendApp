import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {
  WATCHDOG_MARKER,
  alertIdentity,
  classifyDrift,
  deployTriggeringFiles,
  evaluateDeployHealth,
  formatCoarseDuration,
  formatDuration,
  formatHealthReport,
  parseAlertIdentity,
  parsePushPathFilters,
  pathMatchesFilters,
  planIssueSync,
  selectWatchdogIssue,
} from "../lib/deploy-health.mjs";
import {applyIssuePlan} from "../check-deploy-production-health.mjs";
import {
  FUNCTIONS_LIST_ATTEMPT_DELAYS_MS,
  describeFunctionsListFailure,
  diffDeployedFunctions,
  formatFunctionsDiff,
  inactiveDeployedFunctions,
  listDeployedFunctionsWithRetry,
  parseDeployedFunctionNames,
  parseDeployedFunctions,
  parseExportedFunctionNames,
} from "../lib/deployed-functions.mjs";

const NOW = "2026-07-31T12:00:00Z";
const HEAD = {
  sha: "b3fe7972e7e7fe42ad1a72422c99fd4be23b35ec",
  committedAt: "2026-07-20T23:41:20Z",
  ref: "main",
};

/**
 * Builds a workflow run with sensible defaults.
 * @param {object} overrides Fields to override.
 * @return {object} A workflow run shaped like the GitHub API's.
 */
function run(overrides = {}) {
  return {
    id: 1,
    run_number: 1,
    status: "completed",
    conclusion: "success",
    head_sha: HEAD.sha,
    display_title: "a commit",
    html_url: "https://github.com/tpavay/AscendApp/actions/runs/1",
    created_at: "2026-07-31T11:00:00Z",
    run_started_at: "2026-07-31T11:00:00Z",
    ...overrides,
  };
}

test("a cancelled run raises the same alert a failed one does", () => {
  const cancelled = evaluateDeployHealth({
    runs: [run({id: 2, conclusion: "cancelled"}), run({id: 1, run_number: 0})],
    head: HEAD,
    now: NOW,
  });
  const failed = evaluateDeployHealth({
    runs: [run({id: 2, conclusion: "failure"}), run({id: 1, run_number: 0})],
    head: HEAD,
    now: NOW,
  });

  assert.equal(cancelled.healthy, false);
  assert.equal(failed.healthy, false);
  assert.deepEqual(
    cancelled.alerts.map((alert) => alert.kind),
    failed.alerts.map((alert) => alert.kind)
  );
});

test("a cancelled run is reported as one GitHub does not email about", () => {
  const {alerts} = evaluateDeployHealth({
    runs: [run({id: 2, conclusion: "cancelled"}), run({id: 1, run_number: 0})],
    head: HEAD,
    now: NOW,
  });

  const alert = alerts.find((entry) => entry.kind === "runs-not-succeeding");
  assert.match(alert.detail, /does not\s+email about/);
  assert.equal(alert.runs[0].conclusion, "cancelled");
});

test("a failed run is not described as silent", () => {
  const {alerts} = evaluateDeployHealth({
    runs: [run({id: 2, conclusion: "failure"}), run({id: 1, run_number: 0})],
    head: HEAD,
    now: NOW,
  });

  const alert = alerts.find((entry) => entry.kind === "runs-not-succeeding");
  assert.match(alert.detail, /failed loudly/);
});

test("the real July cancellation streak is caught", () => {
  // Reconstructed from the GitHub API: five of these runs concluded
  // `cancelled` with total_count: 0 jobs - they never started at all.
  const runs = [
    run({
      id: 29787993767,
      run_number: 10,
      conclusion: "cancelled",
      created_at: "2026-07-20T23:41:23Z",
      run_started_at: "2026-07-20T23:41:23Z",
    }),
    run({
      id: 29577969423,
      run_number: 9,
      conclusion: "cancelled",
      head_sha: "8ed6bf85bdf1ddd212bde01e2feec8cf416112f1",
      created_at: "2026-07-17T11:46:29Z",
    }),
    run({
      id: 29571604789,
      run_number: 8,
      conclusion: "cancelled",
      head_sha: "e841ecca71991aa35ed8e65c59e72d6aea379860",
      created_at: "2026-07-17T09:54:09Z",
    }),
    run({
      id: 29571478050,
      run_number: 7,
      conclusion: "cancelled",
      head_sha: "e661d0a44242a2a98bf4183b8b52bd7a6d8180d1",
      created_at: "2026-07-17T09:51:57Z",
    }),
    run({
      id: 29571233623,
      run_number: 6,
      conclusion: "cancelled",
      head_sha: "3a6a4117a27787b6279ea85a5b5f544e549b9998",
      created_at: "2026-07-17T09:47:43Z",
    }),
    run({
      id: 29550242067,
      run_number: 5,
      conclusion: "cancelled",
      head_sha: "88f25d4edcc9e99c7439a50cd574f46e39ba7e4f",
      created_at: "2026-07-17T02:34:11Z",
    }),
    run({
      id: 29541742572,
      run_number: 4,
      conclusion: "cancelled",
      head_sha: "6341ad61e386393e6ae03ccf9a11764f288a7d69",
      created_at: "2026-07-16T23:15:42Z",
    }),
    run({
      id: 29540507247,
      run_number: 3,
      conclusion: "cancelled",
      head_sha: "6341ad61e386393e6ae03ccf9a11764f288a7d69",
      created_at: "2026-07-16T22:46:47Z",
    }),
    run({
      id: 29540189415,
      run_number: 2,
      conclusion: "success",
      head_sha: "6341ad61e386393e6ae03ccf9a11764f288a7d69",
      created_at: "2026-07-16T22:39:47Z",
    }),
  ];

  const {healthy, alerts, lastSuccess} = evaluateDeployHealth({
    runs,
    head: HEAD,
    now: NOW,
  });

  assert.equal(healthy, false);
  assert.equal(lastSuccess.id, 29540189415);

  const streak = alerts.find((alert) => alert.kind === "runs-not-succeeding");
  assert.equal(streak.runs.length, 8, "the streak stops at the last success");
  assert.match(streak.title, /8 consecutive/);

  const behind = alerts.find(
    (alert) => alert.kind === "production-behind-default-branch"
  );
  assert.ok(behind, "production running 6341ad6 while main is at b3fe797");
  assert.match(behind.detail, /6341ad6/);
});

test("a run stalled on approval is caught while it is still holding the group", () => {
  const {healthy, alerts} = evaluateDeployHealth({
    // The shape of run 29540507247 on 2026-07-17: still open, one job sitting
    // in `waiting` on the production environment's required reviewer.
    runs: [
      run({
        id: 29540507247,
        run_number: 3,
        status: "in_progress",
        conclusion: null,
        created_at: "2026-07-16T22:46:47Z",
        run_started_at: "2026-07-16T23:19:24Z",
      }),
      run({id: 29540189415, run_number: 2, created_at: "2026-07-16T22:39:47Z"}),
    ],
    head: {...HEAD, sha: "6341ad61e386393e6ae03ccf9a11764f288a7d69"},
    now: "2026-07-17T09:00:00Z",
  });

  assert.equal(healthy, false);
  const stalled = alerts.find((alert) => alert.kind === "run-stalled");
  assert.match(stalled.title, /is stuck in in_progress$/);
  assert.match(stalled.detail, /concurrency group/);
  assert.match(stalled.detail, /in_progress for under a day/);
});

test("a run inside the stall threshold is not an alert", () => {
  const {healthy} = evaluateDeployHealth({
    runs: [
      run({id: 3, status: "in_progress", conclusion: null, created_at: NOW,
        run_started_at: NOW}),
      run({id: 2}),
    ],
    head: HEAD,
    now: NOW,
  });

  assert.equal(healthy, true);
});

test("the deployed head on the newest successful run is healthy", () => {
  const {healthy, alerts} = evaluateDeployHealth({
    runs: [run({id: 2, run_number: 2})],
    head: HEAD,
    now: NOW,
  });

  assert.deepEqual(alerts, []);
  assert.equal(healthy, true);
});

test("a fresh commit is given time to deploy before drift is an alert", () => {
  const head = {...HEAD, sha: "cafe".repeat(10), committedAt: NOW};
  const {healthy} = evaluateDeployHealth({
    runs: [run({id: 2, run_number: 2})],
    head,
    now: NOW,
  });

  assert.equal(healthy, true, "a commit pushed seconds ago is not yet drift");
});

const DEPLOY_WORKFLOW = fileURLToPath(
  new URL("../../.github/workflows/deploy-production.yml", import.meta.url)
);
const DEPLOY_PATH_FILTERS = parsePushPathFilters(
  readFileSync(DEPLOY_WORKFLOW, "utf8")
);

test("the deploy filters are read from the workflow, not copied", () => {
  assert.ok(
    DEPLOY_PATH_FILTERS.includes("AscendApp/**"),
    "the real workflow's allowlist parses"
  );
  assert.ok(DEPLOY_PATH_FILTERS.includes("functions/**"));
  assert.ok(DEPLOY_PATH_FILTERS.includes("firebase.json"));
  assert.ok(
    !DEPLOY_PATH_FILTERS.includes("main"),
    "`branches: [main]` is not mistaken for a path filter"
  );
});

test("path filters follow GitHub's glob rules", () => {
  assert.equal(pathMatchesFilters("AscendApp/Features/Home/View.swift", ["AscendApp/**"]), true);
  assert.equal(pathMatchesFilters("docs/notes.md", ["AscendApp/**"]), false);
  assert.equal(pathMatchesFilters("web/src/a.ts", ["*.md"]), false);
  assert.equal(pathMatchesFilters("README.md", ["*.md"]), true);
  assert.equal(pathMatchesFilters("docs/a.md", ["*.md"]), false, "* does not span /");
  assert.equal(pathMatchesFilters("firebase.json", ["firebase.json"]), true);
  assert.equal(pathMatchesFilters("scripts/x.mjs", ["scripts/**", "!scripts/x.mjs"]), false);
  assert.deepEqual(
    deployTriggeringFiles(["docs/a.md", "functions/src/index.ts"], DEPLOY_PATH_FILTERS),
    ["functions/src/index.ts"]
  );
  assert.deepEqual(
    deployTriggeringFiles(["docs/a.md"], []),
    ["docs/a.md"],
    "no allowlist means everything triggers"
  );
});

/** A deploy that succeeded on some commit other than the current head. */
const DEPLOYED_ELSEWHERE = [
  run({id: 2, run_number: 2, head_sha: "old".repeat(13) + "a"}),
];

/**
 * Evaluates drift for one compare result against the real workflow filters.
 * @param {object | null} comparison The compare result, or null.
 * @return {object} The evaluation result.
 */
function driftFor(comparison) {
  return evaluateDeployHealth({
    runs: DEPLOYED_ELSEWHERE,
    head: HEAD,
    now: NOW,
    comparison,
    deployPathFilters: DEPLOY_PATH_FILTERS,
  });
}

test("every compare status is classified deliberately, never by falling through", () => {
  const filters = DEPLOY_PATH_FILTERS;
  const docs = ["docs/a.md", "README.md"];
  const code = ["functions/src/index.ts"];

  assert.deepEqual(
    classifyDrift({comparison: {status: "identical", files: []}, deployPathFilters: filters}),
    {alert: false, reason: "identical", triggering: []}
  );
  assert.equal(
    classifyDrift({comparison: {status: "ahead", files: docs}, deployPathFilters: filters}).alert,
    false
  );
  assert.equal(
    classifyDrift({comparison: {status: "ahead", files: code}, deployPathFilters: filters}).alert,
    true
  );
  assert.equal(
    classifyDrift({comparison: {status: "diverged", files: code}, deployPathFilters: filters}).alert,
    true
  );
  assert.deepEqual(
    classifyDrift({comparison: {status: "behind", files: []}, deployPathFilters: filters}),
    {alert: true, reason: "behind", triggering: null},
    "an empty file list from `behind` must never read as nothing to deploy"
  );
  assert.equal(
    classifyDrift({comparison: {status: "ahead", files: null}, deployPathFilters: filters}).reason,
    "unresolved"
  );
  assert.equal(
    classifyDrift({comparison: {status: "surprising", files: []}, deployPathFilters: filters}).reason,
    "unknown"
  );
  assert.equal(classifyDrift({comparison: null, deployPathFilters: filters}).alert, true);
  assert.equal(classifyDrift().alert, true, "no input at all still errs loud");
});

test("the deployed head being the branch head is not drift", () => {
  assert.deepEqual(driftFor({status: "identical", files: []}).alerts, []);
});

test("a docs-only commit ahead of the last deploy is not drift", () => {
  const {healthy, alerts} = driftFor({
    status: "ahead",
    files: [
      "docs/production-backend-rollout-runbook.md",
      ".claude/skills/ascend-deploy/SKILL.md",
      "README.md",
    ],
  });

  assert.deepEqual(alerts, [], "nothing in that commit could ever have deployed");
  assert.equal(healthy, true);
});

test("a commit touching deployable paths ahead of the last deploy is drift", () => {
  const {healthy, alerts} = driftFor({
    status: "ahead",
    files: [
      "docs/notes.md",
      "AscendApp/Features/Home/HomeView.swift",
      "functions/src/index.ts",
    ],
  });

  assert.equal(healthy, false);
  assert.deepEqual(
    alerts.map((alert) => alert.kind),
    ["production-behind-default-branch"]
  );
  assert.match(alerts[0].detail, /2 undeployed files match/);
});

test("a head that no longer contains the deployed commit is its own alert", () => {
  // A force-push or reset under production. The compare reports zero files
  // because the head does not contain the deployed commit at all, so reading
  // the file list alone would call a rewritten history healthy.
  const {healthy, alerts} = driftFor({status: "behind", files: []});

  assert.equal(healthy, false);
  assert.deepEqual(
    alerts.map((alert) => alert.kind),
    ["deployed-commit-not-on-default-branch"]
  );
  assert.match(alerts[0].title, /not on main/);
  assert.match(alerts[0].detail, /rewritten, reset, or force-pushed/);
});

test("a compare status the watchdog cannot classify alerts rather than stays quiet", () => {
  for (const comparison of [
    {status: "unrecognised", files: []},
    {status: null, files: []},
    {status: "ahead", files: null},
    null,
  ]) {
    const {healthy, alerts} = driftFor(comparison);
    assert.equal(healthy, false, `status ${comparison?.status ?? "none"} must alert`);
    assert.deepEqual(alerts.map((alert) => alert.kind), [
      "production-behind-default-branch",
    ]);
    assert.match(alerts[0].detail, /could not be established/);
  }
});

test("no successful run at all is its own alert", () => {
  const {alerts} = evaluateDeployHealth({
    runs: [run({id: 2, conclusion: "cancelled"})],
    head: HEAD,
    now: NOW,
  });

  assert.ok(alerts.some((alert) => alert.kind === "never-deployed"));
});

test("an empty run list with a stale head still alerts", () => {
  const {healthy, alerts} = evaluateDeployHealth({
    runs: [],
    head: HEAD,
    now: NOW,
  });

  assert.equal(healthy, false);
  assert.deepEqual(
    alerts.map((alert) => alert.kind),
    ["never-deployed"]
  );
});

test("durations read the way a human would say them", () => {
  assert.equal(formatDuration(0), "0m");
  assert.equal(formatDuration(45 * 60_000), "45m");
  assert.equal(formatDuration(90 * 60_000), "1h 30m");
  assert.equal(formatDuration(2 * 60 * 60_000), "2h");
  assert.equal(formatDuration(13 * 24 * 60 * 60_000), "13d");
});

test("the issue body carries the marker and every alert", () => {
  const {alerts} = evaluateDeployHealth({
    runs: [run({id: 2, conclusion: "cancelled"}), run({id: 1, run_number: 0})],
    head: HEAD,
    now: NOW,
  });
  const body = formatHealthReport(alerts);

  assert.ok(body.startsWith(WATCHDOG_MARKER));
  for (const alert of alerts) {
    assert.ok(body.includes(alert.title), `body mentions "${alert.title}"`);
  }
  assert.match(body, /GitHub only emails on `failure`/);
});

test("the issue body is stable for the same alerts", () => {
  const {alerts} = evaluateDeployHealth({
    runs: [run({id: 2, conclusion: "cancelled"}), run({id: 1, run_number: 0})],
    head: HEAD,
    now: NOW,
  });

  assert.equal(formatHealthReport(alerts), formatHealthReport(alerts));
});

test("the watchdog issue is found by its marker, not by its label", () => {
  const {canonical, duplicates} = selectWatchdogIssue([
    {number: 12, body: "unrelated issue"},
    {number: 7, body: `${WATCHDOG_MARKER}\n\nreport`},
  ]);

  assert.equal(canonical.number, 7);
  assert.deepEqual(duplicates, []);
});

test("a pull request is never mistaken for the watchdog issue", () => {
  const {canonical} = selectWatchdogIssue([
    {number: 9, body: WATCHDOG_MARKER, pull_request: {url: "..."}},
  ]);

  assert.equal(canonical, null);
});

test("racing runs that both opened an issue converge on the oldest", () => {
  // Two watchdog runs can both read an un-indexed list and both create. The
  // next run has to heal that rather than keep one thread per race.
  const {canonical, duplicates} = selectWatchdogIssue([
    {number: 293, body: WATCHDOG_MARKER},
    {number: 292, body: WATCHDOG_MARKER},
    {number: 300, body: WATCHDOG_MARKER},
  ]);

  assert.equal(canonical.number, 292);
  assert.deepEqual(duplicates, [293, 300]);
});

test("no watchdog issue open reads as none, not as an error", () => {
  assert.deepEqual(selectWatchdogIssue([]), {canonical: null, duplicates: []});
});

test("an unhealthy pipeline with no open issue opens one", () => {
  const plan = planIssueSync({healthy: false, alerts: [], existingIssue: null});
  assert.equal(plan.action, "create");
});

/**
 * Builds the open watchdog issue a rendered report would have left behind.
 * @param {Array<object>} alerts The alerts that report described.
 * @return {object} The canonical issue, as `selectWatchdogIssue` returns it.
 */
function issueReporting(alerts) {
  const {canonical} = selectWatchdogIssue([
    {number: 7, body: formatHealthReport(alerts)},
  ]);
  return canonical;
}

test("a standing problem stays quiet even as its durations tick on", () => {
  // The same stall and the same drift, evaluated an hour apart. The rendered
  // prose is allowed to differ; the notification decision must not.
  const stalling = run({id: 9, status: "queued", conclusion: null,
    created_at: "2026-07-16T23:22:38Z", run_started_at: "2026-07-16T23:22:38Z"});
  const deployed = run({id: 2, run_number: 2, head_sha: "old".repeat(13) + "a"});
  const evaluate = (now) => evaluateDeployHealth({
    runs: [stalling, deployed],
    head: HEAD,
    now,
    comparison: {status: "ahead", files: ["functions/src/index.ts"]},
    deployPathFilters: DEPLOY_PATH_FILTERS,
  }).alerts;

  const earlier = evaluate("2026-07-31T12:00:00Z");
  const later = evaluate("2026-07-31T13:00:00Z");

  assert.ok(
    earlier.some((alert) => alert.kind === "run-stalled") &&
      earlier.some((alert) => alert.kind === "production-behind-default-branch"),
    "both duration-bearing alerts are active"
  );
  assert.notEqual(
    formatDuration(Date.parse("2026-07-31T12:00:00Z") - Date.parse(stalling.created_at)),
    formatDuration(Date.parse("2026-07-31T13:00:00Z") - Date.parse(stalling.created_at)),
    "the underlying durations really did change"
  );
  assert.equal(alertIdentity(earlier), alertIdentity(later));

  const plan = planIssueSync({
    healthy: false,
    alerts: later,
    existingIssue: issueReporting(earlier),
  });

  assert.equal(plan.action, "noop");
  assert.equal(plan.comment, null);
});

test("neither duration-bearing alert puts a clock in its title", () => {
  const {alerts} = evaluateDeployHealth({
    runs: [
      run({id: 9, status: "queued", conclusion: null,
        created_at: "2026-07-16T23:22:38Z",
        run_started_at: "2026-07-16T23:22:38Z"}),
      run({id: 2, run_number: 2, head_sha: "old".repeat(13) + "a"}),
    ],
    head: HEAD,
    now: NOW,
    comparison: {status: "ahead", files: ["functions/src/index.ts"]},
    deployPathFilters: DEPLOY_PATH_FILTERS,
  });

  for (const alert of alerts) {
    assert.doesNotMatch(
      alert.title,
      /\d+\s*(?:d|h|m)\b/,
      `"${alert.title}" names the condition, not its age`
    );
  }
  assert.ok(
    alerts.some((alert) => /over \d+ days|under a day|under 6 hours/.test(alert.detail)),
    "the age still reaches the reader, coarsely, in the body"
  );
});

test("coarse durations do not churn between watchdog runs", () => {
  const hour = 60 * 60_000;
  assert.equal(formatCoarseDuration(0), "under 6 hours");
  assert.equal(formatCoarseDuration(5.9 * hour), "under 6 hours");
  assert.equal(formatCoarseDuration(7 * hour), "under a day");
  assert.equal(formatCoarseDuration(25 * hour), "over a day");
  assert.equal(formatCoarseDuration(11 * 24 * hour + hour), "over 11 days");
  assert.equal(
    formatCoarseDuration(11 * 24 * hour + hour),
    formatCoarseDuration(11 * 24 * hour + 4 * hour),
    "three hours later reads identically"
  );
});

test("a genuinely new alert kind re-notifies", () => {
  const existing = [{kind: "runs-not-succeeding", runs: [{id: 1}]}];
  const grown = [...existing, {kind: "run-stalled", runs: [{id: 5}]}];

  const plan = planIssueSync({
    healthy: false,
    alerts: grown,
    existingIssue: issueReporting(existing),
  });

  assert.equal(plan.action, "update");
  assert.ok(plan.comment);
});

test("a new run inside an existing alert kind re-notifies", () => {
  const existing = [{kind: "runs-not-succeeding", runs: [{id: 1}, {id: 2}]}];
  const grown = [{kind: "runs-not-succeeding", runs: [{id: 1}, {id: 2}, {id: 3}]}];

  const plan = planIssueSync({
    healthy: false,
    alerts: grown,
    existingIssue: issueReporting(existing),
  });

  assert.equal(plan.action, "update");
  assert.ok(plan.comment);
});

test("run order within an alert does not fake a new problem", () => {
  const alerts = [{kind: "runs-not-succeeding", runs: [{id: 2}, {id: 1}]}];
  const reordered = [{kind: "runs-not-succeeding", runs: [{id: 1}, {id: 2}]}];

  assert.equal(alertIdentity(alerts), alertIdentity(reordered));
});

test("an issue with no readable identity is treated as changed, never as matching", () => {
  const alerts = [{kind: "runs-not-succeeding", runs: [{id: 1}]}];

  for (const body of [
    `${WATCHDOG_MARKER}\n\nan issue written before the identity token existed`,
    `${WATCHDOG_MARKER}\n<!-- ascend-deploy-production-watchdog-id -->\n\nmangled`,
  ]) {
    const {canonical} = selectWatchdogIssue([{number: 7, body}]);
    assert.equal(canonical.identity, null);
    const plan = planIssueSync({healthy: false, alerts, existingIssue: canonical});
    assert.equal(plan.action, "update", "erring loud beats erring silent");
    assert.ok(plan.comment);
  }
});

test("the identity survives a rewording of the report prose", () => {
  const alerts = [{kind: "run-stalled", runs: [{id: 42}]}];
  const {canonical} = selectWatchdogIssue([
    {
      number: 7,
      body: `${WATCHDOG_MARKER}\n<!-- ascend-deploy-production-watchdog-id:${alertIdentity(alerts)} -->\n\ntotally different prose`,
    },
  ]);

  assert.equal(
    planIssueSync({healthy: false, alerts, existingIssue: canonical}).action,
    "noop"
  );
});

/**
 * Records the writes `applyIssuePlan` performs against a fake API client.
 * @param {object} plan The plan to apply.
 * @param {string} body The rendered report body.
 * @return {Promise<Array<object>>} One entry per request, in order.
 */
async function writesFor(plan, body) {
  const calls = [];
  await applyIssuePlan({
    request: async (path, init = {}) => {
      calls.push({
        path,
        method: init.method ?? "GET",
        body: init.body ? JSON.parse(init.body) : null,
      });
      return {html_url: "https://example.invalid/1"};
    },
    owner: "tpavay",
    repo: "AscendApp",
    plan,
    body,
  });
  return calls;
}

/**
 * Renders the drift report for a head undeployed for a given span.
 * @param {string} now Evaluation time.
 * @return {{alerts: Array<object>, body: string}} The report.
 */
function driftReportAt(now) {
  const {alerts} = evaluateDeployHealth({
    runs: [run({id: 2, run_number: 2, head_sha: "old".repeat(13) + "a"})],
    head: HEAD,
    now,
    comparison: {status: "ahead", files: ["functions/src/index.ts"]},
    deployPathFilters: DEPLOY_PATH_FILTERS,
  });
  return {alerts, body: formatHealthReport(alerts)};
}

test("a standing problem's prose is refreshed even though it stays silent", () => {
  // The same drift, one day later: the identity holds, so nothing should
  // email - but the age in the body has moved on and must not read as day one.
  const day0 = driftReportAt("2026-07-21T12:00:00Z");
  const day5 = driftReportAt("2026-07-26T12:00:00Z");

  assert.notEqual(day0.body, day5.body, "the prose really did go stale");
  assert.match(day0.body, /under a day/);
  assert.match(day5.body, /over 5 days/);

  const plan = planIssueSync({
    healthy: false,
    alerts: day5.alerts,
    body: day5.body,
    existingIssue: {number: 292, identity: alertIdentity(day0.alerts), body: day0.body},
  });

  assert.equal(plan.action, "noop");
  assert.equal(plan.comment, null, "a standing problem must not re-notify");
  assert.equal(plan.updateBody, true, "but its text must not freeze");
});

test("the identity token is byte-identical across a body-only refresh", () => {
  const day0 = driftReportAt("2026-07-21T12:00:00Z");
  const day5 = driftReportAt("2026-07-26T12:00:00Z");

  assert.equal(
    parseAlertIdentity(day0.body),
    parseAlertIdentity(day5.body),
    "a refresh that moved the token would masquerade as a new problem"
  );
});

test("a noop with stale prose patches the body and posts no comment", async () => {
  const calls = await writesFor(
    {action: "noop", issueNumber: 292, comment: null, updateBody: true},
    "refreshed body"
  );

  assert.deepEqual(
    calls.map((call) => `${call.method} ${call.path}`),
    ["PATCH /repos/tpavay/AscendApp/issues/292"]
  );
  assert.deepEqual(calls[0].body, {body: "refreshed body"});
});

test("a noop with identical prose writes nothing at all", async () => {
  const calls = await writesFor(
    {action: "noop", issueNumber: 292, comment: null, updateBody: false},
    "unchanged body"
  );

  assert.deepEqual(calls, []);
});

test("a changed identity patches the body and comments", async () => {
  const calls = await writesFor(
    {
      action: "update",
      issueNumber: 292,
      comment: "The deploy-pipeline health report changed.",
      updateBody: true,
    },
    "new body"
  );

  assert.deepEqual(
    calls.map((call) => `${call.method} ${call.path}`),
    [
      "PATCH /repos/tpavay/AscendApp/issues/292",
      "POST /repos/tpavay/AscendApp/issues/292/comments",
    ]
  );
});

test("a healthy pipeline with no issue writes nothing", async () => {
  assert.deepEqual(
    await writesFor(
      {action: "none", issueNumber: null, comment: null, updateBody: false},
      ""
    ),
    []
  );
});

test("recovery comments before it closes, so the close is not silent", async () => {
  const calls = await writesFor(
    {
      action: "close",
      issueNumber: 292,
      comment: "A `Deploy Production` run has succeeded.",
      updateBody: false,
    },
    ""
  );

  assert.deepEqual(
    calls.map((call) => `${call.method} ${call.path}`),
    [
      "POST /repos/tpavay/AscendApp/issues/292/comments",
      "PATCH /repos/tpavay/AscendApp/issues/292",
    ]
  );
  assert.deepEqual(calls[1].body, {state: "closed", state_reason: "completed"});
});

test("recovery closes the issue and says why", () => {
  const plan = planIssueSync({
    healthy: true,
    alerts: [],
    existingIssue: {number: 7, identity: "run-stalled@9"},
  });

  assert.equal(plan.action, "close");
  assert.equal(plan.issueNumber, 7);
  assert.match(plan.comment, /succeeded/);
});

test("a healthy pipeline with no issue does nothing", () => {
  const plan = planIssueSync({healthy: true, alerts: [], existingIssue: null});
  assert.equal(plan.action, "none");
});

test("index.ts exports are read in both shapes the file uses", () => {
  const source = [
    'export {cleanupDeletedUserData} from "./accountCleanup";',
    "export {",
    "  registerPushDevice,",
    "  sendClimbDropNotification as sendDrop,",
    "} from \"./pushNotifications\";",
    "export type {Foo} from \"./types\";",
    "export const unsubscribeFromEmails = onRequest(handler);",
    "import {setGlobalOptions} from \"firebase-functions/v2\";",
  ].join("\n");

  assert.deepEqual(parseExportedFunctionNames(source), [
    "cleanupDeletedUserData",
    "registerPushDevice",
    "sendDrop",
    "unsubscribeFromEmails",
  ]);
});

test("the checked-in production gap is what the diff reports", () => {
  // Source exports on `main` at b3fe797 vs the eleven functions the production
  // project actually had on 2026-07-31. A dated snapshot, so `joinWaitlist`
  // stays in it even though #330 removed the function from source.
  const exported = [
    "cleanupDeletedUserData",
    "finalizeLeaderboardAchievements",
    "joinWaitlist",
    "onFeedbackCreated",
    "onLifecycleEventEmailAutomation",
    "onWorkoutReplaySplitsWritten",
    "onWorkoutWritten",
    "processEmailJobs",
    "recordLifecycleEvent",
    "registerPushDevice",
    "sendClimbDropNotification",
    "unregisterPushDevice",
    "unsubscribeFromEmails",
    "updatePushNotificationPreferences",
  ];
  const deployed = exported.filter(
    (name) =>
      ![
        "cleanupDeletedUserData",
        "onWorkoutWritten",
        "unsubscribeFromEmails",
      ].includes(name)
  );

  const diff = diffDeployedFunctions({exported, deployed});
  assert.deepEqual(diff.missing, [
    "cleanupDeletedUserData",
    "onWorkoutWritten",
    "unsubscribeFromEmails",
  ]);
  assert.deepEqual(diff.orphaned, []);

  const {ok, lines} = formatFunctionsDiff({projectId: "ascend-prod-9c8f2", diff});
  assert.equal(ok, false);
  assert.equal(lines.filter((line) => line.startsWith("::error::")).length, 3);
});

test("functions left behind after removal from source are orphans", () => {
  // The four `strava*` functions still live in dev, removed from source in
  // 2ca544d, and `joinWaitlist` joins them as of #330. A deploy log cannot
  // show this; only a reconciliation can.
  const diff = diffDeployedFunctions({
    exported: ["unsubscribeFromEmails"],
    deployed: [
      "unsubscribeFromEmails",
      "joinWaitlist",
      "stravaCallback",
      "stravaCreateActivity",
      "stravaCreateOAuthState",
      "stravaDisconnect",
    ],
  });

  assert.deepEqual(diff.orphaned, [
    "joinWaitlist",
    "stravaCallback",
    "stravaCreateActivity",
    "stravaCreateOAuthState",
    "stravaDisconnect",
  ]);
  assert.deepEqual(diff.missing, []);
  assert.equal(
    formatFunctionsDiff({projectId: "ascend-f2e4f", diff}).ok,
    false,
    "an orphan is a defect, not a warning"
  );
});

test("a project in the state the source describes passes", () => {
  const names = ["a", "b"];
  const diff = diffDeployedFunctions({exported: names, deployed: [...names]});

  assert.equal(formatFunctionsDiff({projectId: "p", diff}).ok, true);
  assert.deepEqual(diff.matched, names);
});

test("the firebase functions:list payload is read by id", () => {
  const payload = JSON.stringify({
    status: "success",
    result: [
      {id: "processEmailJobs", platform: "gcfv2"},
      {id: "unsubscribeFromEmails", platform: "gcfv2"},
      {id: "processEmailJobs", platform: "gcfv2"},
    ],
  });

  assert.deepEqual(parseDeployedFunctionNames(payload), [
    "processEmailJobs",
    "unsubscribeFromEmails",
  ]);
});

test("a deployed function that is not ACTIVE is not serving, so it fails", () => {
  // "Deployed" and "working" are different claims. A v2 function can be
  // present and in FAILED, which a name-only reconciliation would call fine.
  const deployed = parseDeployedFunctions({
    status: "success",
    result: [
      {id: "unsubscribeFromEmails", state: "ACTIVE"},
      {id: "processEmailJobs", state: "FAILED"},
    ],
  });
  const inactive = inactiveDeployedFunctions(deployed, [
    "unsubscribeFromEmails",
    "processEmailJobs",
  ]);

  assert.deepEqual(inactive, [
    {id: "processEmailJobs", region: null, state: "FAILED"},
  ]);

  const diff = diffDeployedFunctions({
    exported: ["unsubscribeFromEmails", "processEmailJobs"],
    deployed: deployed.map((entry) => entry.id),
  });
  const {ok, lines} = formatFunctionsDiff({projectId: "p", diff, inactive});

  assert.equal(ok, false, "names all match, but one is not serving");
  assert.ok(lines.some((line) => line.includes("not ACTIVE")));
});

test("a payload with no state field is not invented into a failure", () => {
  // v1 functions and older CLI payloads omit `state`; a missing field is not
  // evidence of anything, and must not block a deploy.
  const deployed = parseDeployedFunctions({
    status: "success",
    result: [{id: "unsubscribeFromEmails"}],
  });

  assert.deepEqual(deployed, [
    {id: "unsubscribeFromEmails", region: null, state: null},
  ]);
  assert.deepEqual(
    inactiveDeployedFunctions(deployed, ["unsubscribeFromEmails"]),
    []
  );
});

test("one function serving in one region and broken in another is not serving", () => {
  // Keying the state check on `id` alone lets whichever region the CLI listed
  // last speak for all of them, so a FAILED region hides behind an ACTIVE one.
  const deployed = parseDeployedFunctions({
    status: "success",
    result: [
      {id: "onWorkoutWritten", region: "us-central1", state: "ACTIVE"},
      {id: "onWorkoutWritten", region: "europe-west1", state: "FAILED"},
    ],
  });

  assert.equal(deployed.length, 2, "regions are separate deployments");

  const inactive = inactiveDeployedFunctions(deployed, ["onWorkoutWritten"]);
  assert.deepEqual(inactive, [
    {id: "onWorkoutWritten", region: "europe-west1", state: "FAILED"},
  ]);

  const diff = diffDeployedFunctions({
    exported: ["onWorkoutWritten"],
    deployed: deployed.map((entry) => entry.id),
  });
  assert.deepEqual(diff.missing, [], "the name-level diff still keys on id");
  assert.deepEqual(diff.orphaned, []);

  const {ok, lines} = formatFunctionsDiff({projectId: "p", diff, inactive});
  assert.equal(ok, false);
  assert.ok(lines.some((line) => line.includes("europe-west1")));
});

test("a multi-region function is one name, not one name per region", () => {
  const payload = {
    status: "success",
    result: [
      {id: "unsubscribeFromEmails", region: "us-central1"},
      {id: "unsubscribeFromEmails", region: "europe-west1"},
    ],
  };

  assert.deepEqual(parseDeployedFunctionNames(payload), [
    "unsubscribeFromEmails",
  ]);
});

test("an orphan's state is irrelevant - it should not be there at all", () => {
  const deployed = parseDeployedFunctions({
    status: "success",
    result: [{id: "stravaCallback", state: "FAILED"}],
  });

  assert.deepEqual(
    inactiveDeployedFunctions(deployed, ["unsubscribeFromEmails"]),
    [],
    "an unexported function is reported as an orphan, not as inactive"
  );
});

test("an unexpected functions:list payload is refused, not read as empty", () => {
  assert.throws(
    () => parseDeployedFunctionNames(JSON.stringify({status: "error"})),
    /no `result` array/
  );
});

/**
 * Builds the error `execFileSync` throws for a non-zero exit.
 * @param {object} overrides Fields to override.
 * @return {object} An error shaped like execFileSync's.
 */
function execFailure(overrides = {}) {
  return {status: 1, stdout: "", stderr: "", code: undefined,
    signal: null, ...overrides};
}

test("a --json failure is diagnosed from stdout, where firebase puts it", () => {
  // The exact shape run 33426121857 hit: `firebase functions:list --json`
  // exits 1, writes its error envelope to stdout and leaves stderr empty.
  // Reading only stderr reported `no diagnostic output` and cost the cause.
  const message = describeFunctionsListFailure({
    projectId: "ascend-staging-fa7d5",
    error: execFailure({
      stdout: JSON.stringify({
        status: "error",
        error: "Failed to list functions for ascend-staging-fa7d5",
      }),
    }),
  });

  assert.match(message, /Failed to list functions for ascend-staging-fa7d5/);
  assert.doesNotMatch(
    message,
    /no diagnostic output/,
    "the envelope on stdout is a diagnostic; reporting none discards it"
  );
});

test("a --json payload that is not the error envelope is still reported", () => {
  const message = describeFunctionsListFailure({
    projectId: "p",
    error: execFailure({stdout: "not json at all"}),
  });

  assert.match(message, /not json at all/);
});

test("stderr still speaks when the CLI dies before --json handling", () => {
  const message = describeFunctionsListFailure({
    projectId: "p",
    error: execFailure({stderr: "node: bad option --json"}),
  });

  assert.match(message, /bad option --json/);
});

test("a spawn failure names the code it has, not an empty exit", () => {
  const message = describeFunctionsListFailure({
    projectId: "p",
    error: execFailure({status: undefined, stdout: null, stderr: null,
      code: "ENOENT"}),
  });

  assert.match(message, /exit unknown/);
  assert.match(message, /ENOENT/);
});

test("only a failure with nothing at all reports no diagnostic output", () => {
  assert.match(
    describeFunctionsListFailure({projectId: "p", error: execFailure()}),
    /no diagnostic output/
  );
});

test("the diagnostic never reproduces argv, which is where a token would be",
  () => {
    const error = execFailure({
      stdout: JSON.stringify({status: "error", error: "boom"}),
      message: "Command failed: npx firebase --token SECRET-TOKEN-VALUE",
    });

    assert.doesNotMatch(
      describeFunctionsListFailure({projectId: "p", error}),
      /SECRET-TOKEN-VALUE/
    );
  });

test("a read that could not run is retried, not turned into a failed deploy",
  () => {
    const waited = [];
    let calls = 0;

    const payload = listDeployedFunctionsWithRetry({
      listOnce: () => {
        calls += 1;
        if (calls < 3) {
          throw execFailure();
        }
        return '{"status":"success","result":[]}';
      },
      sleep: (ms) => waited.push(ms),
      delaysMs: [1, 2],
    });

    assert.equal(calls, 3);
    assert.deepEqual(waited, [1, 2]);
    assert.equal(payload, '{"status":"success","result":[]}');
  });

test("the retry budget is bounded and rethrows the last failure", () => {
  let calls = 0;

  assert.throws(
    () =>
      listDeployedFunctionsWithRetry({
        listOnce: () => {
          calls += 1;
          throw execFailure({stdout: `attempt ${calls}`});
        },
        sleep: () => {},
        delaysMs: [1, 2],
      }),
    (thrown) => {
      // The original error is rethrown untouched so the caller keeps the
      // streams `describeFunctionsListFailure` reads.
      assert.equal(
        thrown.stdout,
        "attempt 3",
        "the caller must see the final failure, not the first"
      );
      return true;
    }
  );
  assert.equal(calls, 3, "delaysMs.length retries means one more attempt");
});

test("a read that succeeds first time waits for nothing", () => {
  const waited = [];

  listDeployedFunctionsWithRetry({
    listOnce: () => "{}",
    sleep: (ms) => waited.push(ms),
    delaysMs: [5000, 15000],
  });

  assert.deepEqual(waited, []);
});

test("the shipped retry schedule is bounded and non-empty", () => {
  assert.ok(
    FUNCTIONS_LIST_ATTEMPT_DELAYS_MS.length > 0,
    "a single unretried read is what failed the deploy in the first place"
  );
  const total = FUNCTIONS_LIST_ATTEMPT_DELAYS_MS.reduce((a, b) => a + b, 0);
  assert.ok(
    total <= 60_000,
    "a verification read may not stall a deploy job for a minute"
  );
});

test("retrying the read never softens the reconciliation it feeds", () => {
  // The budget buys tolerance for the API, never for the deploy: a payload
  // that comes back missing a function is still a first-attempt failure.
  const deployed = parseDeployedFunctionNames(
    listDeployedFunctionsWithRetry({
      listOnce: () =>
        JSON.stringify({status: "success", result: [{id: "onWorkoutWritten"}]}),
      sleep: () => assert.fail("a successful read must not be retried"),
    })
  );

  const diff = diffDeployedFunctions({
    exported: ["onWorkoutWritten", "unsubscribeFromEmails"],
    deployed,
  });

  assert.deepEqual(diff.missing, ["unsubscribeFromEmails"]);
  assert.equal(
    formatFunctionsDiff({projectId: "p", diff, inactive: []}).ok,
    false
  );
});
