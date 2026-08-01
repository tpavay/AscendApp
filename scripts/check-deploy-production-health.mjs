#!/usr/bin/env node
/**
 * Deploy Production watchdog.
 *
 * Answers one question - "is the code on the default branch actually running in
 * production?" - from outside the deploy workflow, and makes a `cancelled` run
 * as loud as a failed one.
 *
 * It has to live outside `deploy-production.yml` because the failure it exists
 * to catch destroys the workflow's own ability to report. A run cancelled while
 * still queued behind another run never creates a single job, so no in-workflow
 * step - not even one guarded by `always()` - can ever run to complain about it.
 * That is exactly how six runs disappeared between 2026-07-16 and 2026-07-29.
 *
 * Usage:
 *   node scripts/check-deploy-production-health.mjs [options]
 *
 *   --repo <owner/name>   Defaults to $GITHUB_REPOSITORY, then the git remote.
 *   --workflow <file>     Workflow filename. Default deploy-production.yml.
 *   --branch <name>       Deploy branch. Default main.
 *   --limit <n>           Runs to inspect. Default 20.
 *   --dry-run             Print the verdict and the issue payload; write nothing.
 *   --no-fail             Always exit 0 (for local inspection).
 *
 * Requires GITHUB_TOKEN (or GH_TOKEN) with `actions: read` and `issues: write`.
 */

import {execFileSync} from "node:child_process";
import process from "node:process";
import {
  evaluateDeployHealth,
  formatHealthReport,
  planIssueSync,
  selectWatchdogIssue,
} from "./lib/deploy-health.mjs";

const ISSUE_TITLE = "Deploy Production is not reaching production";
const ISSUE_LABEL = "deploy-health";
const API_ROOT = "https://api.github.com";

/**
 * Parses the supported flags out of argv.
 * @param {Array<string>} argv Raw arguments.
 * @return {object} Parsed options.
 */
function parseArgs(argv) {
  const options = {
    repo: process.env.GITHUB_REPOSITORY ?? null,
    workflow: "deploy-production.yml",
    branch: "main",
    limit: 20,
    dryRun: false,
    fail: true,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case "--repo":
        options.repo = argv[++index];
        break;
      case "--workflow":
        options.workflow = argv[++index];
        break;
      case "--branch":
        options.branch = argv[++index];
        break;
      case "--limit":
        options.limit = Number.parseInt(argv[++index], 10);
        break;
      case "--dry-run":
        options.dryRun = true;
        break;
      case "--no-fail":
        options.fail = false;
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!options.repo) {
    options.repo = repoFromGitRemote();
  }
  if (!options.repo) {
    throw new Error("Could not resolve the repository. Pass --repo owner/name.");
  }
  if (!Number.isInteger(options.limit) || options.limit < 1) {
    throw new Error("--limit must be a positive integer.");
  }

  return options;
}

/**
 * Reads `owner/name` off the `origin` remote.
 * @return {string | null} The slug, or null when it cannot be determined.
 */
function repoFromGitRemote() {
  try {
    const url = execFileSync("git", ["remote", "get-url", "origin"], {
      encoding: "utf8",
    }).trim();
    const match = url.match(/github\.com[:/](.+?)(?:\.git)?$/);
    return match ? match[1] : null;
  } catch {
    return null;
  }
}

/**
 * Creates a thin authenticated GitHub REST client.
 * @param {string} token A GitHub token.
 * @return {(path: string, init?: object) => Promise<any>} Request function.
 */
function createClient(token) {
  return async function request(path, init = {}) {
    const response = await fetch(
      path.startsWith("http") ? path : `${API_ROOT}${path}`,
      {
        ...init,
        headers: {
          accept: "application/vnd.github+json",
          authorization: `Bearer ${token}`,
          "x-github-api-version": "2022-11-28",
          ...(init.body ? {"content-type": "application/json"} : {}),
          ...(init.headers ?? {}),
        },
      }
    );

    if (!response.ok) {
      const detail = await response.text();
      throw new Error(
        `GitHub API ${init.method ?? "GET"} ${path} failed ` +
          `(${response.status}): ${detail.slice(0, 400)}`
      );
    }

    return response.status === 204 ? null : response.json();
  };
}

/**
 * Runs the health check and syncs the alert issue.
 * @return {Promise<number>} The process exit code.
 */
async function main() {
  const options = parseArgs(process.argv.slice(2));
  const token = process.env.GITHUB_TOKEN ?? process.env.GH_TOKEN;
  if (!token) {
    throw new Error("GITHUB_TOKEN (or GH_TOKEN) is required.");
  }

  const request = createClient(token);
  const [owner, repo] = options.repo.split("/");

  const runsPath =
    `/repos/${owner}/${repo}/actions/workflows/${options.workflow}/runs` +
    `?branch=${encodeURIComponent(options.branch)}&per_page=${options.limit}`;
  const runs = (await request(runsPath)).workflow_runs ?? [];

  const branch = await request(
    `/repos/${owner}/${repo}/branches/${encodeURIComponent(options.branch)}`
  );
  const head = {
    sha: branch.commit?.sha ?? null,
    committedAt: branch.commit?.commit?.committer?.date ?? null,
    ref: options.branch,
  };

  const {healthy, alerts} = evaluateDeployHealth({
    runs,
    head,
    now: new Date().toISOString(),
  });

  const body = formatHealthReport(alerts, {
    repository: options.repo,
    workflow: "Deploy Production",
  });

  for (const alert of alerts) {
    console.log(`::error title=Deploy pipeline::${alert.title}`);
    console.log(`  ${alert.detail}`);
    for (const run of alert.runs) {
      console.log(`  - ${run.conclusion}: ${run.label}`);
    }
  }
  if (healthy) {
    console.log(
      `Deploy Production is healthy: ${head.sha?.slice(0, 7)} is deployed and ` +
        "no run is stalled."
    );
  }

  const openIssues = await request(
    `/repos/${owner}/${repo}/issues?state=open&per_page=100`
  );
  const {canonical, duplicates} = selectWatchdogIssue(openIssues);
  const plan = planIssueSync({healthy, body, existingIssue: canonical});
  console.log(`Issue action: ${plan.action}`);

  if (options.dryRun) {
    if (duplicates.length > 0) {
      console.log(`Would close duplicates: ${duplicates.join(", ")}`);
    }
    if (!healthy) {
      console.log("\n--- issue body (dry run) ---\n");
      console.log(body);
    }
    return healthy || !options.fail ? 0 : 1;
  }

  await applyIssuePlan({request, owner, repo, plan, body});
  await closeDuplicates({request, owner, repo, duplicates, canonical});

  return healthy || !options.fail ? 0 : 1;
}

/**
 * Closes any extra watchdog issues so only one alert thread survives.
 * @param {object} input Application input.
 * @param {Function} input.request The API client.
 * @param {string} input.owner Repository owner.
 * @param {string} input.repo Repository name.
 * @param {Array<number>} input.duplicates Issue numbers to close.
 * @param {{number: number} | null} input.canonical The issue being kept.
 * @return {Promise<void>} Resolves once the duplicates are closed.
 */
async function closeDuplicates({request, owner, repo, duplicates, canonical}) {
  for (const number of duplicates) {
    const path = `/repos/${owner}/${repo}/issues/${number}`;
    await request(`${path}/comments`, {
      method: "POST",
      body: JSON.stringify({
        body:
          "Duplicate watchdog alert; the live one is " +
          `#${canonical?.number ?? "unknown"}.`,
      }),
    });
    await request(path, {
      method: "PATCH",
      body: JSON.stringify({state: "closed", state_reason: "not_planned"}),
    });
    console.log(`Closed duplicate issue #${number}`);
  }
}

/**
 * Applies the issue plan: create, update-and-comment, close, or nothing.
 * @param {object} input Application input.
 * @param {Function} input.request The API client.
 * @param {string} input.owner Repository owner.
 * @param {string} input.repo Repository name.
 * @param {object} input.plan The plan from `planIssueSync`.
 * @param {string} input.body The rendered report body.
 * @return {Promise<void>} Resolves once GitHub is in sync.
 */
async function applyIssuePlan({request, owner, repo, plan, body}) {
  if (plan.action === "none" || plan.action === "noop") {
    return;
  }

  if (plan.action === "create") {
    await ensureLabel(request, owner, repo);
    const created = await request(`/repos/${owner}/${repo}/issues`, {
      method: "POST",
      body: JSON.stringify({
        title: ISSUE_TITLE,
        body,
        labels: [ISSUE_LABEL],
        assignees: [owner],
      }),
    });
    console.log(`Opened ${created.html_url}`);
    return;
  }

  const path = `/repos/${owner}/${repo}/issues/${plan.issueNumber}`;

  if (plan.action === "update") {
    await request(path, {method: "PATCH", body: JSON.stringify({body})});
  }

  if (plan.comment) {
    // The comment, not the body edit, is what sends the email.
    await request(`${path}/comments`, {
      method: "POST",
      body: JSON.stringify({body: plan.comment}),
    });
  }

  if (plan.action === "close") {
    await request(path, {
      method: "PATCH",
      body: JSON.stringify({state: "closed", state_reason: "completed"}),
    });
    console.log(`Closed issue #${plan.issueNumber}`);
  }
}

/**
 * Creates the watchdog label when the repository does not have it yet.
 * @param {Function} request The API client.
 * @param {string} owner Repository owner.
 * @param {string} repo Repository name.
 * @return {Promise<void>} Resolves once the label exists.
 */
async function ensureLabel(request, owner, repo) {
  try {
    await request(`/repos/${owner}/${repo}/labels/${ISSUE_LABEL}`);
  } catch {
    await request(`/repos/${owner}/${repo}/labels`, {
      method: "POST",
      body: JSON.stringify({
        name: ISSUE_LABEL,
        color: "b60205",
        description: "Raised by the Deploy Production watchdog.",
      }),
    });
  }
}

main()
  .then((code) => {
    process.exitCode = code;
  })
  .catch((error) => {
    console.error(`::error::${error.message}`);
    process.exitCode = 1;
  });
