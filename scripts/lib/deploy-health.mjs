/**
 * Health evaluation for the production deploy pipeline.
 *
 * This exists because GitHub's default notifications only fire on `failure`.
 * A workflow run that concludes `cancelled` is silent, and a production deploy
 * pipeline has three ways to conclude `cancelled` without anyone touching it:
 *
 *   - a job stalls waiting for `environment:` reviewer approval, which keeps
 *     the run `in_progress` and holds its concurrency group;
 *   - the held group forces later runs to sit `pending`, and GitHub keeps at
 *     most one pending run per group - each new run cancels the one it
 *     displaces, before that run has created a single job;
 *   - somebody cancels a run by hand.
 *
 * All three happened on `tpavay/AscendApp` between 2026-07-16 and 2026-07-29:
 * six runs were cancelled with zero jobs ever created, production sat on the
 * code from `6341ad6` for 13 days, and nothing said so.
 *
 * The functions here are pure. `check-deploy-production-health.mjs` supplies
 * the GitHub API data and turns the result into an issue and an exit code.
 */

/** Run statuses that mean "this run has not finished and is not moving". */
const STALLABLE_STATUSES = Object.freeze([
  "queued",
  "pending",
  "requested",
  "waiting",
  "action_required",
  "in_progress",
]);

/** Conclusions that leave production undeployed without a failure email. */
export const SILENT_CONCLUSIONS = Object.freeze([
  "cancelled",
  "skipped",
  "stale",
  "timed_out",
  "action_required",
  "neutral",
]);

export const DEFAULT_THRESHOLDS = Object.freeze({
  /** A run that has not finished within this long is stuck, not slow. */
  stalledRunMinutes: 180,
  /** How long `main` may sit undeployed before that is itself an alert. */
  undeployedCommitMinutes: 360,
});

const MINUTE_MS = 60_000;

/**
 * Parses an ISO timestamp into epoch milliseconds.
 * @param {string | number | Date | null | undefined} value Timestamp.
 * @return {number | null} Epoch milliseconds, or null when unparseable.
 */
function toEpochMs(value) {
  if (value === null || value === undefined) {
    return null;
  }
  const parsed = value instanceof Date ? value.getTime() : Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

/**
 * Formats a millisecond span as a short human duration ("13d 2h", "45m").
 * @param {number} ms Span in milliseconds.
 * @return {string} Rounded duration.
 */
export function formatDuration(ms) {
  const totalMinutes = Math.max(0, Math.round(ms / MINUTE_MS));
  const days = Math.floor(totalMinutes / 1440);
  const hours = Math.floor((totalMinutes % 1440) / 60);
  const minutes = totalMinutes % 60;

  if (days > 0) {
    return hours > 0 ? `${days}d ${hours}h` : `${days}d`;
  }
  if (hours > 0) {
    return minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`;
  }
  return `${minutes}m`;
}

/**
 * Reads the `on.push.paths` allowlist out of a workflow file.
 *
 * The drift check needs to know which commits could ever have triggered a
 * deploy, and the only authority on that is the workflow's own filter. Parsing
 * it beats copying it: a second hand-maintained list drifts the moment somebody
 * edits the workflow, and a drift alert that fires on a docs-only commit trains
 * the reader to ignore the one channel this watchdog exists to create.
 *
 * @param {string} source Contents of a workflow YAML file.
 * @return {Array<string>} The declared path filters, empty when there are none.
 */
export function parsePushPathFilters(source) {
  const patterns = [];
  let onIndent = null;
  let pushIndent = null;
  let pathsIndent = null;

  for (const raw of String(source ?? "").split("\n")) {
    if (raw.trim() === "" || raw.trimStart().startsWith("#")) {
      continue;
    }
    const indent = raw.length - raw.trimStart().length;
    const line = raw.trim();

    if (pathsIndent !== null) {
      if (indent > pathsIndent && line.startsWith("- ")) {
        const value = line.slice(2).trim().replace(/^["']|["']$/g, "");
        if (value) {
          patterns.push(value);
        }
        continue;
      }
      pathsIndent = null;
    }

    if (pushIndent !== null && indent <= pushIndent) {
      pushIndent = null;
    }
    if (onIndent !== null && indent <= onIndent) {
      onIndent = null;
    }

    if (onIndent === null) {
      if (/^["']?on["']?:\s*$/.test(line)) {
        onIndent = indent;
      }
      continue;
    }
    if (pushIndent === null) {
      if (indent > onIndent && /^push:\s*$/.test(line)) {
        pushIndent = indent;
      }
      continue;
    }
    if (indent > pushIndent && /^paths:\s*$/.test(line)) {
      pathsIndent = indent;
    }
  }

  return patterns;
}

/**
 * Compiles one GitHub path filter into a regular expression.
 *
 * Follows GitHub's own glob rules: `**` spans directory separators, `*` and `?`
 * do not.
 *
 * @param {string} pattern A single filter pattern, without any `!` prefix.
 * @return {RegExp} An anchored matcher.
 */
function pathFilterToRegExp(pattern) {
  let source = "^";
  for (let index = 0; index < pattern.length; index += 1) {
    const char = pattern[index];
    if (char === "*") {
      if (pattern[index + 1] === "*") {
        source += ".*";
        index += 1;
      } else {
        source += "[^/]*";
      }
    } else if (char === "?") {
      source += "[^/]";
    } else if ("\\^$.|+()[]{}".includes(char)) {
      source += `\\${char}`;
    } else {
      source += char;
    }
  }
  return new RegExp(`${source}$`);
}

/**
 * Decides whether one changed file would trigger a workflow.
 *
 * Later patterns win, so a `!`-prefixed exclusion can undo an earlier match,
 * matching how GitHub evaluates the list.
 *
 * @param {string} path A repository-relative file path.
 * @param {Array<string>} patterns The workflow's path filters.
 * @return {boolean} True when the path is inside the allowlist.
 */
export function pathMatchesFilters(path, patterns) {
  let matched = false;
  for (const pattern of patterns ?? []) {
    const negated = pattern.startsWith("!");
    const body = negated ? pattern.slice(1) : pattern;
    if (pathFilterToRegExp(body).test(path)) {
      matched = !negated;
    }
  }
  return matched;
}

/**
 * Keeps only the files that would actually trigger a deploy.
 *
 * An empty filter list means the workflow has no `paths:` restriction, so every
 * file triggers it.
 *
 * @param {Array<string>} files Changed file paths.
 * @param {Array<string>} patterns The workflow's path filters.
 * @return {Array<string>} The triggering subset.
 */
export function deployTriggeringFiles(files, patterns) {
  const list = files ?? [];
  if (!Array.isArray(patterns) || patterns.length === 0) {
    return [...list];
  }
  return list.filter((file) => pathMatchesFilters(file, patterns));
}

/**
 * Sorts runs newest-first by the time the run entered the queue.
 * @param {Array<object>} runs Workflow runs from the GitHub API.
 * @return {Array<object>} A new, newest-first array.
 */
function newestFirst(runs) {
  return [...runs].sort(
    (a, b) => (toEpochMs(b.created_at) ?? 0) - (toEpochMs(a.created_at) ?? 0)
  );
}

/**
 * Describes a run compactly enough for an alert line.
 * @param {object} run A workflow run.
 * @return {string} `#run_number sha (title)` style label.
 */
function runLabel(run) {
  const number = run.run_number ? `#${run.run_number}` : `run ${run.id}`;
  const sha = typeof run.head_sha === "string" ? run.head_sha.slice(0, 7) : "?";
  const title = run.display_title ? ` - ${run.display_title}` : "";
  return `${number} (${sha})${title}`;
}

/**
 * Evaluates whether the production deploy pipeline is actually delivering.
 *
 * Three independent checks, because each catches a failure the others miss:
 * the streak check catches runs that concluded without deploying, the stall
 * check catches the run that is holding the concurrency group *right now*, and
 * the drift check catches the case where no run was ever triggered at all.
 *
 * @param {object} input Evaluation input.
 * @param {Array<object>} input.runs Recent `Deploy Production` workflow runs.
 * @param {{sha: string, committedAt: string} | null} input.head Default-branch
 *   head commit, or null when it could not be resolved.
 * @param {string | number | Date} input.now Evaluation time.
 * @param {object} [input.thresholds] Overrides for `DEFAULT_THRESHOLDS`.
 * @param {Array<string> | null} [input.undeployedFiles] Files changed between
 *   the last deployed commit and the head. Null means "could not be resolved",
 *   which is treated as possibly-deployable rather than assumed harmless.
 * @param {Array<string>} [input.deployPathFilters] The deploy workflow's
 *   `on.push.paths` allowlist, from `parsePushPathFilters`.
 * @return {{healthy: boolean, alerts: Array<object>, lastSuccess: object|null}}
 *   The evaluation result.
 */
export function evaluateDeployHealth({
  runs,
  head,
  now,
  thresholds,
  undeployedFiles = null,
  deployPathFilters = [],
} = {}) {
  const limits = {...DEFAULT_THRESHOLDS, ...(thresholds ?? {})};
  const nowMs = toEpochMs(now);
  if (nowMs === null) {
    throw new Error("evaluateDeployHealth requires a parseable `now`.");
  }

  const ordered = newestFirst(runs ?? []);
  const completed = ordered.filter((run) => run.status === "completed");
  const lastSuccess = completed.find((run) => run.conclusion === "success") ?? null;
  const alerts = [];

  // 1. Runs that concluded without deploying. `cancelled` is the one that
  //    matters: GitHub sends no email for it, so the streak grows in silence.
  const unsuccessful = [];
  for (const run of completed) {
    if (run.conclusion === "success") {
      break;
    }
    unsuccessful.push(run);
  }

  if (unsuccessful.length > 0) {
    const silent = unsuccessful.filter((run) =>
      SILENT_CONCLUSIONS.includes(run.conclusion)
    );
    alerts.push({
      kind: "runs-not-succeeding",
      title:
        `${unsuccessful.length} consecutive Deploy Production ` +
        `run${unsuccessful.length === 1 ? "" : "s"} did not succeed`,
      detail:
        silent.length > 0 ?
          `${silent.length} of them concluded with a status GitHub does not ` +
            "email about, so nothing fired." :
          "Every one of them failed loudly.",
      runs: unsuccessful.map((run) => ({
        id: run.id,
        label: runLabel(run),
        conclusion: run.conclusion,
        url: run.html_url ?? null,
        createdAt: run.created_at ?? null,
      })),
    });
  }

  // 2. A run that is still open long past any plausible deploy duration. This
  //    is the live version of the bug: while it sits there it holds the
  //    concurrency group and every later run is cancelled before it starts.
  const stalled = ordered
    .filter((run) => STALLABLE_STATUSES.includes(run.status))
    .map((run) => {
      const startedMs =
        toEpochMs(run.run_started_at) ?? toEpochMs(run.created_at);
      return {run, waitingMs: startedMs === null ? 0 : nowMs - startedMs};
    })
    .filter(({waitingMs}) => waitingMs > limits.stalledRunMinutes * MINUTE_MS);

  for (const {run, waitingMs} of stalled) {
    alerts.push({
      kind: "run-stalled",
      title:
        `Deploy Production ${runLabel(run)} has been ` +
        `${run.status} for ${formatDuration(waitingMs)}`,
      detail:
        "A run that never finishes holds the deploy-production concurrency " +
        "group, and every run queued behind it is cancelled without ever " +
        "creating a job. Approve or cancel it.",
      runs: [
        {
          id: run.id,
          label: runLabel(run),
          conclusion: run.status,
          url: run.html_url ?? null,
          createdAt: run.created_at ?? null,
        },
      ],
    });
  }

  // 3. Production is not running the code on the default branch. This is the
  //    only check that survives the workflow never being triggered at all.
  if (head?.sha) {
    const headAgeMs = toEpochMs(head.committedAt);
    const staleEnough =
      headAgeMs === null ||
      nowMs - headAgeMs > limits.undeployedCommitMinutes * MINUTE_MS;

    if (!lastSuccess && staleEnough) {
      alerts.push({
        kind: "never-deployed",
        title: "No successful Deploy Production run in the inspected window",
        detail:
          `Nothing in the last ${ordered.length} runs deployed ` +
          `${head.sha.slice(0, 7)} or anything before it.`,
        runs: [],
      });
    } else if (lastSuccess && lastSuccess.head_sha !== head.sha && staleEnough) {
      // Deploy Production only runs on a `paths:` allowlist, so a head made of
      // docs-only commits was never meant to deploy and production is current.
      // Alerting on it would fire every three hours forever with nothing to do
      // about it. Unresolvable file lists stay noisy on purpose - silence has
      // to be earned by evidence, not by a failed lookup.
      const triggering =
        undeployedFiles === null ?
          null :
          deployTriggeringFiles(undeployedFiles, deployPathFilters);

      if (triggering === null || triggering.length > 0) {
        const behindMs = headAgeMs === null ? null : nowMs - headAgeMs;
        const undeployedDetail =
          triggering === null ?
            "" :
            ` ${triggering.length} undeployed file` +
              `${triggering.length === 1 ? "" : "s"} match the workflow's ` +
              `paths filter, starting with \`${triggering[0]}\`.`;
        alerts.push({
          kind: "production-behind-default-branch",
          title:
            `Production is behind ${head.ref ?? "the default branch"}` +
            (behindMs === null ? "" : ` by ${formatDuration(behindMs)}`),
          detail:
            `Last successful deploy was ${runLabel(lastSuccess)}; ` +
            `the default branch is now at ${head.sha.slice(0, 7)}.` +
            undeployedDetail,
          runs: [
            {
              id: lastSuccess.id,
              label: runLabel(lastSuccess),
              conclusion: "success",
              url: lastSuccess.html_url ?? null,
              createdAt: lastSuccess.created_at ?? null,
            },
          ],
        });
      }
    }
  }

  return {healthy: alerts.length === 0, alerts, lastSuccess};
}

/** Hidden marker that lets the watchdog find the issue it owns. */
export const WATCHDOG_MARKER = "<!-- ascend-deploy-production-watchdog -->";

/**
 * Renders an alert set as a stable issue body.
 *
 * Stability is the point: the watchdog rewrites the body only when it changes,
 * and comments only when it rewrites, so a standing problem does not email
 * every three hours while a *new* problem still does.
 *
 * @param {Array<object>} alerts Alerts from `evaluateDeployHealth`.
 * @param {{repository?: string, workflow?: string}} [context] Repo context.
 * @return {string} Markdown issue body.
 */
export function formatHealthReport(alerts, context = {}) {
  const workflow = context.workflow ?? "Deploy Production";
  const lines = [
    WATCHDOG_MARKER,
    "",
    `\`${workflow}\` is not delivering code to production.`,
    "",
    "GitHub only emails on `failure`. A run that concludes `cancelled` - " +
      "including one cancelled while still queued behind another run - sends " +
      "nothing at all. This issue is that missing email.",
    "",
  ];

  for (const alert of alerts) {
    lines.push(`## ${alert.title}`, "", alert.detail, "");
    for (const run of alert.runs) {
      const link = run.url ? `[${run.label}](${run.url})` : run.label;
      lines.push(`- \`${run.conclusion}\` - ${link}`);
    }
    if (alert.runs.length > 0) {
      lines.push("");
    }
  }

  lines.push(
    "---",
    "",
    "This issue is opened, updated, and closed by " +
      "`.github/workflows/deploy-production-watchdog.yml`. It closes itself " +
      "once a `Deploy Production` run succeeds on the default-branch head."
  );

  return lines.join("\n");
}

/**
 * Picks the one issue the watchdog owns out of the open issues.
 *
 * Matching is on the hidden marker rather than on a label, because a label can
 * be removed by hand and the watchdog would then open a second issue rather
 * than update the first. Duplicates are still possible - two runs racing the
 * list endpoint will both see nothing and both create - so the oldest wins and
 * the rest are reported for closing. That makes the state self-correcting
 * instead of accumulating a new issue every three hours.
 *
 * @param {Array<object>} issues Open issues from the GitHub API.
 * @return {{canonical: {number: number, body: string} | null,
 *   duplicates: Array<number>}} The issue to keep and the ones to close.
 */
export function selectWatchdogIssue(issues) {
  const owned = (issues ?? [])
    .filter(
      (issue) =>
        !issue.pull_request && (issue.body ?? "").includes(WATCHDOG_MARKER)
    )
    .sort((a, b) => a.number - b.number);

  if (owned.length === 0) {
    return {canonical: null, duplicates: []};
  }

  const [first, ...rest] = owned;
  return {
    canonical: {number: first.number, body: first.body ?? ""},
    duplicates: rest.map((issue) => issue.number),
  };
}

/**
 * Decides what the watchdog should do to its issue this run.
 *
 * Kept separate from the API client so the notification decision - the part
 * that must not regress - is unit-testable without touching GitHub.
 *
 * @param {object} input Decision input.
 * @param {boolean} input.healthy Whether the pipeline is healthy.
 * @param {string} input.body The rendered report body (ignored when healthy).
 * @param {{number: number, body: string} | null} input.existingIssue The open
 *   watchdog issue, if one exists.
 * @return {{action: string, issueNumber: number|null, comment: string|null}}
 *   The action to take.
 */
export function planIssueSync({healthy, body, existingIssue}) {
  if (healthy) {
    if (!existingIssue) {
      return {action: "none", issueNumber: null, comment: null};
    }
    return {
      action: "close",
      issueNumber: existingIssue.number,
      comment:
        "A `Deploy Production` run has succeeded on the default-branch head " +
        "and no run is stalled. Closing.",
    };
  }

  if (!existingIssue) {
    return {action: "create", issueNumber: null, comment: null};
  }

  // Body edits do not notify; comments do. Comment only when the report
  // actually changed, so a standing problem stays quiet and a new one shouts.
  const changed = (existingIssue.body ?? "").trim() !== body.trim();
  return {
    action: changed ? "update" : "noop",
    issueNumber: existingIssue.number,
    comment: changed ? "The deploy-pipeline health report changed." : null,
  };
}
