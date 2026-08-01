import assert from "node:assert/strict";
import test from "node:test";
import {
  WATCHDOG_MARKER,
  evaluateDeployHealth,
  formatDuration,
  formatHealthReport,
  planIssueSync,
  selectWatchdogIssue,
} from "../lib/deploy-health.mjs";
import {
  diffDeployedFunctions,
  formatFunctionsDiff,
  inactiveDeployedFunctions,
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
  assert.match(stalled.title, /in_progress for 9h/);
  assert.match(stalled.detail, /concurrency group/);
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
  const plan = planIssueSync({healthy: false, body: "b", existingIssue: null});
  assert.equal(plan.action, "create");
});

test("an unchanged report does not re-notify", () => {
  const plan = planIssueSync({
    healthy: false,
    body: "same",
    existingIssue: {number: 7, body: "same"},
  });

  assert.equal(plan.action, "noop");
  assert.equal(plan.comment, null);
});

test("a changed report comments, because body edits do not email", () => {
  const plan = planIssueSync({
    healthy: false,
    body: "new",
    existingIssue: {number: 7, body: "old"},
  });

  assert.equal(plan.action, "update");
  assert.ok(plan.comment);
});

test("recovery closes the issue and says why", () => {
  const plan = planIssueSync({
    healthy: true,
    body: "",
    existingIssue: {number: 7, body: "old"},
  });

  assert.equal(plan.action, "close");
  assert.equal(plan.issueNumber, 7);
  assert.match(plan.comment, /succeeded/);
});

test("a healthy pipeline with no issue does nothing", () => {
  const plan = planIssueSync({healthy: true, body: "", existingIssue: null});
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
    "export const joinWaitlist = onRequest(handler);",
    "import {setGlobalOptions} from \"firebase-functions/v2\";",
  ].join("\n");

  assert.deepEqual(parseExportedFunctionNames(source), [
    "cleanupDeletedUserData",
    "joinWaitlist",
    "registerPushDevice",
    "sendDrop",
  ]);
});

test("the checked-in production gap is what the diff reports", () => {
  // Source exports on `main` at b3fe797 vs the eleven functions the production
  // project actually had on 2026-07-31.
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
  // 2ca544d. A deploy log cannot show this; only a reconciliation can.
  const diff = diffDeployedFunctions({
    exported: ["joinWaitlist"],
    deployed: [
      "joinWaitlist",
      "stravaCallback",
      "stravaCreateActivity",
      "stravaCreateOAuthState",
      "stravaDisconnect",
    ],
  });

  assert.deepEqual(diff.orphaned, [
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
      {id: "joinWaitlist", platform: "gcfv2"},
      {id: "processEmailJobs", platform: "gcfv2"},
      {id: "joinWaitlist", platform: "gcfv2"},
    ],
  });

  assert.deepEqual(parseDeployedFunctionNames(payload), [
    "joinWaitlist",
    "processEmailJobs",
  ]);
});

test("a deployed function that is not ACTIVE is not serving, so it fails", () => {
  // "Deployed" and "working" are different claims. A v2 function can be
  // present and in FAILED, which a name-only reconciliation would call fine.
  const deployed = parseDeployedFunctions({
    status: "success",
    result: [
      {id: "joinWaitlist", state: "ACTIVE"},
      {id: "processEmailJobs", state: "FAILED"},
    ],
  });
  const inactive = inactiveDeployedFunctions(deployed, [
    "joinWaitlist",
    "processEmailJobs",
  ]);

  assert.deepEqual(inactive, [{id: "processEmailJobs", state: "FAILED"}]);

  const diff = diffDeployedFunctions({
    exported: ["joinWaitlist", "processEmailJobs"],
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
    result: [{id: "joinWaitlist"}],
  });

  assert.deepEqual(deployed, [{id: "joinWaitlist", state: null}]);
  assert.deepEqual(inactiveDeployedFunctions(deployed, ["joinWaitlist"]), []);
});

test("an orphan's state is irrelevant - it should not be there at all", () => {
  const deployed = parseDeployedFunctions({
    status: "success",
    result: [{id: "stravaCallback", state: "FAILED"}],
  });

  assert.deepEqual(
    inactiveDeployedFunctions(deployed, ["joinWaitlist"]),
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
