/**
 * Pure helpers for picking which App Store version a phased-release command acts on, split
 * out of `scripts/appstore-phased-release.mjs` so the choice is testable without App Store
 * Connect.
 *
 * App Store Connect does not document a default ordering for `/apps/{id}/appStoreVersions`,
 * so "take the first record" is not "take the newest". An operator pausing a bad rollout
 * under pressure has to be certain the pause landed on the version that is actually rolling
 * out, so selection here is explicit and refuses rather than guesses.
 */

/** Phased release states that mean a rollout is live and can still be steered. */
export const IN_FLIGHT_PHASED_RELEASE_STATES = new Set(["ACTIVE", "PAUSED"]);

/** Commands that steer a rollout already in flight, rather than preparing the next one. */
export const IN_FLIGHT_COMMANDS = new Set(["pause", "resume", "release-to-all"]);

/**
 * Orders two version strings newest-first by numeric component, so 1.10.0 beats 1.9.0 -
 * which lexicographic sorting, the only ordering the API offers, gets backwards.
 * Non-numeric suffixes are compared as text so the result is total rather than arbitrary.
 */
export function compareVersionStrings(a, b) {
  const partsOf = (value) => String(value ?? "").split(".");
  const left = partsOf(a);
  const right = partsOf(b);

  for (let index = 0; index < Math.max(left.length, right.length); index += 1) {
    const leftPart = left[index] ?? "";
    const rightPart = right[index] ?? "";
    const leftNumber = Number.parseInt(leftPart, 10);
    const rightNumber = Number.parseInt(rightPart, 10);

    if (Number.isNaN(leftNumber) || Number.isNaN(rightNumber)) {
      if (leftPart !== rightPart) return leftPart < rightPart ? 1 : -1;
      continue;
    }

    if (leftNumber !== rightNumber) return rightNumber - leftNumber;
  }

  return 0;
}

/** The candidates whose rollout is live and can still be steered. */
export function inFlightCandidates(candidates) {
  return (candidates ?? []).filter((candidate) =>
    IN_FLIGHT_PHASED_RELEASE_STATES.has(candidate.phasedRelease?.attributes?.phasedReleaseState),
  );
}

/**
 * The highest version record, without judging ties. `selectVersion` layers the ambiguity
 * check on top; callers that only need something to compare against use this directly.
 */
export function newestCandidate(candidates) {
  return [...(candidates ?? [])].sort((a, b) =>
    compareVersionStrings(a.version.attributes?.versionString, b.version.attributes?.versionString),
  )[0];
}

function describeCandidate({version, phasedRelease}) {
  const versionString = version.attributes?.versionString ?? "(unknown)";
  const appStoreState = version.attributes?.appStoreState ?? "(unknown)";
  const phasedReleaseState = phasedRelease?.attributes?.phasedReleaseState ?? "none";
  return `${versionString} (${appStoreState}, phased release: ${phasedReleaseState})`;
}

/**
 * Picks the version a command should act on.
 *
 * - An explicit `--version` always wins, and is an error if it does not exist.
 * - A command that steers a live rollout requires exactly one version whose phased release
 *   is ACTIVE or PAUSED. Zero and more than one both throw, naming what was found, because
 *   both mean the operator's intent cannot be inferred.
 * - `status` reports on the same version those commands would act on, falling back to the
 *   newest when nothing is rolling out. Reporting on a newer, unsubmitted version while an
 *   older one is mid-rollout is the reading an operator gets wrong under pressure.
 * - `enable` takes the newest version by version string, and throws if two records share it.
 */
export function selectVersion(candidates, {command, requestedVersionString} = {}) {
  if (!candidates || candidates.length === 0) {
    throw new Error("No iOS App Store version found for this app.");
  }

  if (requestedVersionString) {
    const matches = candidates.filter(
      (candidate) => candidate.version.attributes?.versionString === requestedVersionString,
    );
    if (matches.length === 0) {
      throw new Error(
        `No iOS App Store version ${requestedVersionString}. Found: ` +
          `${candidates.map(describeCandidate).join("; ")}`,
      );
    }
    if (matches.length > 1) {
      throw new Error(
        `Version ${requestedVersionString} matches ${matches.length} records. ` +
          "Resolve this in App Store Connect before running a phased-release command.",
      );
    }
    return matches[0];
  }

  const inFlight = inFlightCandidates(candidates);

  if (IN_FLIGHT_COMMANDS.has(command)) {
    if (inFlight.length === 0) {
      throw new Error(
        `No version has a phased release in progress, so there is nothing to \`${command}\`. ` +
          `Found: ${candidates.map(describeCandidate).join("; ")}`,
      );
    }
    if (inFlight.length > 1) {
      throw new Error(
        `${inFlight.length} versions have a phased release in progress: ` +
          `${inFlight.map(describeCandidate).join("; ")}. ` +
          "Re-run with --version <versionString> to say which one you mean.",
      );
    }
    return inFlight[0];
  }

  if (command === "status" && inFlight.length > 0) {
    return newestCandidate(inFlight);
  }

  const sorted = [...candidates].sort((a, b) =>
    compareVersionStrings(a.version.attributes?.versionString, b.version.attributes?.versionString),
  );
  const newest = sorted[0];
  const tied = sorted.filter(
    (candidate) =>
      compareVersionStrings(
        candidate.version.attributes?.versionString,
        newest.version.attributes?.versionString,
      ) === 0,
  );

  if (tied.length > 1) {
    throw new Error(
      `${tied.length} version records share the newest version string: ` +
        `${tied.map(describeCandidate).join("; ")}. ` +
        "Re-run with --version <versionString> to say which one you mean.",
    );
  }

  return newest;
}
