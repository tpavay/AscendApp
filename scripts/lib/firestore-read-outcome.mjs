/**
 * The decision layer for read-only Firestore/Storage investigation.
 *
 * Everything here is pure so the one distinction that matters can be tested
 * without a network: a read that FAILED must never be renderable as a read that
 * came back empty. Four of the six wrong answers that motivated this module were
 * the same mistake - a broken command, a broken URL, or a grep against generic
 * help text produced no output, and no output was reported to the captain as
 * "there is nothing there". Absence is a claim; it needs evidence.
 */

export const OUTCOME = Object.freeze({
  found: "FOUND",
  emptyVerified: "EMPTY (verified)",
  emptyUnverified: "EMPTY (UNVERIFIED)",
  failed: "FAILED",
});

// A caller chaining with `&&` must not read an unproven emptiness as success.
export const EXIT_CODE = Object.freeze({
  found: 0,
  emptyVerified: 0,
  emptyUnverified: 3,
  failed: 2,
});

export const ENVIRONMENTS = Object.freeze({
  dev: "ascend-f2e4f",
  staging: "ascend-staging-fa7d5",
  prod: "ascend-prod-9c8f2",
  production: "ascend-prod-9c8f2",
});

export const PRODUCTION_PROJECT_ID = ENVIRONMENTS.prod;
export const DEFAULT_EMULATOR_HOST = "127.0.0.1:8080";

/**
 * Resolves where a read will actually be sent.
 *
 * Silence is the enemy, so this never guesses: an explicit `--env` always means
 * the real backend for that environment, and the emulator is only chosen when no
 * environment was named or `--emulator` asked for it. Every rendered report
 * repeats the resolved target, because a correct answer about the wrong database
 * is one of the wrong answers this tool exists to stop.
 * @param {object} options Resolution inputs.
 * @return {{kind: string, projectId: string, label: string, emulatorHost: ?string}} Target.
 */
export function resolveTarget({
  env = null,
  emulator = false,
  emulatorHost = null,
  emulatorRunning = false,
  confirmProduction = false,
} = {}) {
  const wantsEmulator = emulator || (env === null && (emulatorRunning || emulatorHost !== null));

  if (wantsEmulator) {
    const host = emulatorHost ?? DEFAULT_EMULATOR_HOST;
    if (emulator && !emulatorRunning && emulatorHost === null) {
      throw new Error(
        `--emulator was requested but nothing is listening on ${DEFAULT_EMULATOR_HOST}. ` +
          "Start it with `npx firebase-tools emulators:start --only firestore`."
      );
    }
    return {
      kind: "emulator",
      projectId: env === null ? "demo-ascendapp" : requireProjectId(env),
      label: `emulator ${host}`,
      emulatorHost: host,
    };
  }

  if (env === null) {
    throw new Error(
      "No target. Pass --env dev|staging|prod, or start the Firestore emulator " +
        "and re-run with no --env to read it instead."
    );
  }

  const projectId = requireProjectId(env);
  if (projectId === PRODUCTION_PROJECT_ID && !confirmProduction) {
    throw new Error("Reading production requires --confirm-production.");
  }

  return {
    kind: "backend",
    projectId,
    label: `${projectId} (${env === "production" ? "prod" : env})`,
    emulatorHost: null,
  };
}

/**
 * Maps an environment alias to its Firebase project ID.
 *
 * Aliases only. A raw project ID would let a `prod` read past the confirmation
 * flag by spelling the project out, which is the guard removing itself.
 * @param {string} env Environment alias.
 * @return {string} Firebase project ID.
 */
export function requireProjectId(env) {
  const projectId = Object.hasOwn(ENVIRONMENTS, env) ? ENVIRONMENTS[env] : undefined;
  if (projectId === undefined) {
    throw new Error(
      `Unknown environment "${env}". Use one of: ${Object.keys(ENVIRONMENTS).join(", ")}.`
    );
  }
  return projectId;
}

/**
 * Classifies one read into exactly one of four outcomes.
 *
 * A zero-result read is only ever "verified empty" when the SAME method returned
 * a positive result against a path already known to hold data. Without that
 * control, or with a control that failed or was itself empty, the method has not
 * been shown capable of detecting presence and the honest answer is that nothing
 * is known - not that nothing is there.
 * @param {object} read The read result.
 * @return {object} Classified outcome.
 */
export function classifyRead({failure = null, matchCount = null, control = null} = {}) {
  if (failure) {
    return {
      outcome: OUTCOME.failed,
      exitCode: EXIT_CODE.failed,
      matchCount: null,
      failure: String(failure.message ?? failure),
      reason: "The read did not complete, so it says nothing about what is there.",
    };
  }

  if (!Number.isInteger(matchCount) || matchCount < 0) {
    return {
      outcome: OUTCOME.failed,
      exitCode: EXIT_CODE.failed,
      matchCount: null,
      failure: `Read returned no usable count (${JSON.stringify(matchCount)}).`,
      reason: "A missing count is a failed read, never an empty one.",
    };
  }

  if (matchCount > 0) {
    return {
      outcome: OUTCOME.found,
      exitCode: EXIT_CODE.found,
      matchCount,
      failure: null,
      reason: null,
    };
  }

  const verdict = controlVerdict(control);
  if (verdict.proves) {
    return {
      outcome: OUTCOME.emptyVerified,
      exitCode: EXIT_CODE.emptyVerified,
      matchCount: 0,
      failure: null,
      reason: verdict.reason,
      control,
    };
  }

  return {
    outcome: OUTCOME.emptyUnverified,
    exitCode: EXIT_CODE.emptyUnverified,
    matchCount: 0,
    failure: null,
    reason: verdict.reason,
    control,
  };
}

/**
 * Whether a control probe proves the method can see data that is present.
 * @param {?object} control Control probe result.
 * @return {{proves: boolean, reason: string}} Verdict and its wording.
 */
function controlVerdict(control) {
  if (control === null || control === undefined) {
    return {
      proves: false,
      reason:
        "No control probe ran, so this method has not been shown capable of " +
        "seeing data that IS present. Re-run with --control <populated path>.",
    };
  }
  if (control.failure) {
    return {
      proves: false,
      reason: `The control probe at ${control.path} failed (${control.failure}), so it proves nothing.`,
    };
  }
  if (!Number.isInteger(control.matchCount) || control.matchCount <= 0) {
    return {
      proves: false,
      reason:
        `The control probe at ${control.path} also returned nothing. Either that ` +
        "path is not populated after all, or the method is blind. Pick a path you " +
        "have independently confirmed holds data.",
    };
  }
  return {
    proves: true,
    reason:
      `The same method returned ${control.matchCount} at the known-populated ` +
      `control path ${control.path}, so it can see data that is present.`,
  };
}

/**
 * Renders a classified outcome for a human.
 *
 * A failure renders on stderr and never carries a count, so no caller can pipe
 * it into a `grep -c` and read the zero as an answer.
 * @param {object} report Report inputs.
 * @return {{stdout: string, stderr: string, exitCode: number}} Rendered output.
 */
export function renderReport({target, command, path, classified, detail = []}) {
  const header = `${command} ${path}  @ ${target.label}`;

  if (classified.outcome === OUTCOME.failed) {
    return {
      stdout: "",
      stderr: [
        `FAILED  ${header}`,
        `  ${classified.failure}`,
        `  ${classified.reason}`,
        "  This is NOT an empty result. Nothing about this path has been established.",
      ].join("\n"),
      exitCode: classified.exitCode,
    };
  }

  const lines = [`${classified.outcome}  ${header}`];

  if (classified.outcome === OUTCOME.found) {
    lines.push(`  matches: ${classified.matchCount}`);
  } else {
    lines.push("  matches: 0");
    lines.push(`  ${classified.reason}`);
    if (classified.outcome === OUTCOME.emptyUnverified) {
      lines.push("  Do NOT report this path as empty on the strength of this run.");
    }
  }

  for (const line of detail) {
    lines.push(`  ${line}`);
  }

  return {stdout: lines.join("\n"), stderr: "", exitCode: classified.exitCode};
}

/**
 * Splits a Firestore path and says whether it names a document or a collection.
 * @param {string} path Slash-separated Firestore path.
 * @return {{segments: string[], kind: string}} Parsed path.
 */
export function parseFirestorePath(path) {
  if (typeof path !== "string" || path.trim() === "") {
    throw new Error("Path is required.");
  }
  const segments = path.replace(/^\/+|\/+$/g, "").split("/");
  if (segments.some((segment) => segment === "")) {
    throw new Error(`Path "${path}" has an empty segment.`);
  }
  return {
    segments,
    kind: segments.length % 2 === 0 ? "document" : "collection",
  };
}

/**
 * Requires a path of the given kind, naming the mistake when it is not.
 * @param {string} path Slash-separated Firestore path.
 * @param {string} kind Either "document" or "collection".
 * @return {string[]} Path segments.
 */
export function requirePathKind(path, kind) {
  const parsed = parseFirestorePath(path);
  if (parsed.kind !== kind) {
    throw new Error(
      `"${path}" is a ${parsed.kind} path (${parsed.segments.length} segments); ` +
        `this command needs a ${kind} path.`
    );
  }
  return parsed.segments;
}

/**
 * Whether a Storage object name sits directly under a prefix.
 *
 * `profile_pictures/` and `users/<uid>/profile_pictures/` are different places.
 * A substring match counts the second as the first, which is how six flat-path
 * objects were once reported as nineteen. Prefixes anchor at the start.
 * @param {string} objectName Full object name.
 * @param {string} prefix Prefix to anchor against.
 * @return {boolean} Whether the object is under the prefix.
 */
export function objectMatchesPrefix(objectName, prefix) {
  return typeof objectName === "string" && objectName.startsWith(prefix);
}

/**
 * Builds a Firebase console deep link for a Firestore path.
 *
 * The console encodes path separators as `~2F`, and it shows a document's
 * subcollections only once that document is selected - so a link to the parent
 * collection is the link that makes data look absent.
 * @param {string} projectId Firebase project ID.
 * @param {string} path Firestore path.
 * @return {string} Console URL.
 */
export function firestoreConsoleUrl(projectId, path) {
  const encoded = parseFirestorePath(path)
    .segments.map((segment) => encodeURIComponent(segment))
    .join("~2F");
  return `https://console.firebase.google.com/project/${projectId}/firestore/databases/-default-/data/~2F${encoded}`;
}
