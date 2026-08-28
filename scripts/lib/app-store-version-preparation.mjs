/**
 * Pure helpers for preparing the next App Store version record, split out of
 * `scripts/appstore-prepare-version.mjs` so every choice is testable without App Store
 * Connect.
 *
 * NOTHING HERE SUBMITS FOR REVIEW, AND NOTHING HERE MAY EVER BE EXTENDED TO.
 * The captain presses Submit himself, deliberately, after reading the version record this
 * code prepares. `scripts/test/app-store-submission-guard.test.mjs` enforces that across
 * the whole pipeline; do not "finish the job".
 */

/**
 * A refusal that will say the same thing on every retry.
 *
 * The build wait retries a rate limit or an outage inside its budget, and decides that from
 * `error.status` - which a refusal raised here does not carry. Without this marker every
 * deterministic refusal (an ignored filter, an expired binary, an ambiguous build number)
 * was retried once a minute for the whole budget and then surfaced as a processing timeout,
 * pointing the operator at Apple's queue rather than at the real cause.
 */
export class AppStorePreparationRefusal extends Error {
  constructor(message) {
    super(message);
    this.name = "AppStorePreparationRefusal";
  }
}

/** Apple accepts one to three numeric components in `CFBundleShortVersionString`. */
export const VERSION_STRING_PATTERN = /^\d+(?:\.\d+){0,2}$/;

const MARKETING_VERSION_PATTERN = /^\s*MARKETING_VERSION = ([^;]+);\s*$/gm;

/**
 * App Store version states whose record still accepts a build.
 *
 * Everything else is either mid-review, live, or historical, and writing to it either
 * fails or changes something a human did not ask for. Refusing by allowlist means an
 * App Store state Apple adds later stops this script instead of being silently treated
 * as editable.
 */
export const PREPARABLE_VERSION_STATES = new Set([
  "PREPARE_FOR_SUBMISSION",
  "DEVELOPER_REJECTED",
  "REJECTED",
  "METADATA_REJECTED",
  "INVALID_BINARY",
]);

/** Build processing states Apple can report; only `VALID` can be attached to a version. */
export const ATTACHABLE_BUILD_PROCESSING_STATE = "VALID";

/**
 * Processing states a build never leaves. Waiting on one is waiting forever, so it is a
 * refusal rather than a poll.
 */
export const TERMINAL_BUILD_PROCESSING_STATES = new Set(["FAILED", "INVALID"]);

/**
 * The single `MARKETING_VERSION` every target in the Xcode project shares.
 *
 * A project whose targets disagree has no one marketing version, and picking either value
 * would archive one number and prepare a version record for another. Refuse instead: this
 * is exactly the drift that leaves a build orphaned from its version in App Store Connect.
 */
export function parseMarketingVersion(projectFileContents) {
  const values = [...String(projectFileContents ?? "").matchAll(MARKETING_VERSION_PATTERN)].map(
    (match) => match[1].trim(),
  );

  if (values.length === 0) {
    throw new AppStorePreparationRefusal(
      "No MARKETING_VERSION found in the Xcode project. Refusing to guess the marketing version.",
    );
  }

  const distinct = [...new Set(values)];
  if (distinct.length > 1) {
    throw new AppStorePreparationRefusal(
      `The Xcode project declares ${distinct.length} different MARKETING_VERSION values ` +
        `(${distinct.join(", ")}). Every target must share one before a version record can be ` +
        "prepared.",
    );
  }

  const [versionString] = distinct;
  assertVersionString(versionString);
  return versionString;
}

export function assertVersionString(versionString) {
  if (!VERSION_STRING_PATTERN.test(String(versionString ?? ""))) {
    throw new AppStorePreparationRefusal(
      `Marketing version must be one to three numeric components, got '${versionString}'.`,
    );
  }
  return String(versionString);
}

/**
 * Apple renamed this attribute: `appVersionState` is current, `appStoreState` is the
 * deprecated name still returned for older apps. Reading only one of them reports
 * "(unknown)" for a version whose state decides whether this script may write to it.
 */
export function versionState(versionRecord) {
  return (
    versionRecord?.attributes?.appVersionState ??
    versionRecord?.attributes?.appStoreState ??
    null
  );
}

function describeVersion(versionRecord) {
  return `${versionRecord?.attributes?.versionString ?? "(unknown)"} (${
    versionState(versionRecord) ?? "unknown state"
  })`;
}

/**
 * What this run may do with the version record for `versionString`:
 * `create` (none exists), `reuse` (an editable one exists), or `not-editable`.
 *
 * The listing is re-filtered locally rather than trusted: a `filter[versionString]` Apple
 * silently ignored would otherwise hand back some other version - very possibly the live
 * one - as the record to attach a build to.
 *
 * Whether `not-editable` is a failure or a no-op is the caller's decision, not this
 * function's: a human who asked for a run by name wants it to fail loudly, while the run
 * chained off a backend-only production deploy is finding the expected answer.
 */
export function resolveVersionRecordOutcome(versionRecords, versionString) {
  assertVersionString(versionString);

  const records = versionRecords ?? [];
  const matching = records.filter(
    (record) => record?.attributes?.versionString === versionString,
  );

  if (matching.length === 0) return {outcome: "create", record: null, state: null};

  if (matching.length > 1) {
    throw new AppStorePreparationRefusal(
      `${matching.length} App Store version records share version string ${versionString}: ` +
        `${matching.map(describeVersion).join("; ")}. Resolve this in App Store Connect first.`,
    );
  }

  const [record] = matching;
  const state = versionState(record);
  if (!PREPARABLE_VERSION_STATES.has(state)) {
    return {outcome: "not-editable", record, state};
  }

  return {outcome: "reuse", record, state};
}

/** Why a run a human asked for by name stops at a version that is past editing. */
export function nonEditableVersionRefusal(versionString, state) {
  return (
    `App Store version ${versionString} is ${state ?? "in an unreported state"}, which this ` +
    "script may not write to. A version that is in review, awaiting release, or already " +
    "released is the captain's to steer in App Store Connect. Bump MARKETING_VERSION if " +
    "this build is meant to be the next release."
  );
}

/**
 * The same fact, reported as the expected outcome it is on the chained path.
 *
 * A backend-only merge to `main` still archives and uploads a build while the previous
 * version sits with Apple. Failing that run would train everyone to ignore a red run.
 */
export function nonEditableVersionNotice(versionString, state) {
  return (
    `App Store version ${versionString} is ${state ?? "in an unreported state"}: it is already ` +
    "with Apple, or already released, so there is nothing to prepare and nothing was written. " +
    "Bump MARKETING_VERSION when the next release is meant to go out."
  );
}

function buildNumberOf(record) {
  return String(record?.build?.attributes?.version ?? "");
}

/**
 * Build numbers order numerically, not lexicographically, so `10` outranks `9`. A build
 * number Apple reports as something other than digits cannot be ordered at all, and
 * guessing an order would pick a binary nobody named.
 */
function buildNumberValue(record) {
  const raw = buildNumberOf(record);
  if (!/^\d+$/.test(raw)) {
    throw new AppStorePreparationRefusal(
      `Build ${raw || "(unknown)"} in this train reports a non-numeric build number, so the ` +
        "newest build cannot be identified. Re-run with --build <number> to say which one you " +
        "mean.",
    );
  }
  return BigInt(raw);
}

function describeBuild(record) {
  const attributes = record?.build?.attributes ?? {};
  return (
    `${attributes.version ?? "(unknown)"} (${attributes.processingState ?? "unknown state"}` +
    `${attributes.expired ? ", expired" : ""}, train ${record?.trainVersion ?? "unknown"})`
  );
}

function newestBuildInTrain(inTrain, versionString) {
  const newest = inTrain.reduce((best, record) =>
    buildNumberValue(record) > buildNumberValue(best) ? record : best,
  );

  const tied = inTrain.filter((record) => buildNumberOf(record) === buildNumberOf(newest));
  if (tied.length > 1) {
    throw new AppStorePreparationRefusal(
      `${tied.length} builds in train ${versionString} share build number ` +
        `${buildNumberOf(newest)}: ${tied.map(describeBuild).join("; ")}. ` +
        "Re-run with --build <number> to say which one you mean.",
    );
  }

  return newest;
}

/**
 * The build to attach, or `null` while Apple is still processing it.
 *
 * `--build` pins one exactly. Without it the rule is the NEWEST build in this marketing
 * version's train, waited for until it is processed - not the newest build that happens to
 * be processed already. This workflow starts seconds after the deploy uploads, so an
 * earlier VALID build in the same train (a re-deploy, a rebuilt submission, a backend
 * hotfix) would otherwise be attached and reported as success while the binary the captain
 * actually merged was still processing. A timeout waiting for the right build is a loud
 * failure; attaching the wrong one is a silent wrong result.
 *
 * Records whose train does not match are a filter Apple ignored, not a build to fall back
 * on: attaching another train's binary is how a version record ends up shipping the wrong
 * app.
 */
export function selectAttachableBuild(buildRecords, {versionString, requestedBuildNumber} = {}) {
  assertVersionString(versionString);

  const records = buildRecords ?? [];
  const inTrain = records.filter((record) => record?.trainVersion === versionString);

  if (inTrain.length === 0 && records.length > 0) {
    throw new AppStorePreparationRefusal(
      `APP_STORE_CONTRACT_FILTER_IGNORED: App Store Connect returned ${records.length} build(s), ` +
        `none of them in train ${versionString}: ${records.map(describeBuild).join("; ")}. ` +
        "No returned build can be trusted to belong to this version.",
    );
  }

  if (requestedBuildNumber !== undefined && requestedBuildNumber !== null) {
    const requested = String(requestedBuildNumber);
    const matching = inTrain.filter((record) => buildNumberOf(record) === requested);

    if (matching.length === 0) {
      throw new AppStorePreparationRefusal(
        `No build ${requested} in train ${versionString}. Found: ` +
          `${inTrain.map(describeBuild).join("; ") || "(none)"}.`,
      );
    }
    if (matching.length > 1) {
      throw new AppStorePreparationRefusal(
        `${matching.length} builds in train ${versionString} report build number ${requested}: ` +
          `${matching.map(describeBuild).join("; ")}.`,
      );
    }

    const [record] = matching;
    assertBuildIsAttachable(record);
    return record;
  }

  if (inTrain.length === 0) return null;

  const newest = newestBuildInTrain(inTrain, versionString);
  const attributes = newest.build?.attributes ?? {};

  if (attributes.expired === true) {
    throw new AppStorePreparationRefusal(
      `The newest build in train ${versionString} is ${describeBuild(newest)}, which has ` +
        "expired and cannot be attached. Upload a newer build.",
    );
  }
  if (TERMINAL_BUILD_PROCESSING_STATES.has(attributes.processingState)) {
    throw new AppStorePreparationRefusal(
      `The newest build in train ${versionString} is ${describeBuild(newest)}. Apple will not ` +
        "process it any further, so there is nothing to wait for. Fix the upload and deploy " +
        "again.",
    );
  }
  if (attributes.processingState !== ATTACHABLE_BUILD_PROCESSING_STATE) {
    return null;
  }

  return newest;
}

export function assertBuildIsAttachable(record) {
  const attributes = record?.build?.attributes ?? {};

  if (attributes.expired === true) {
    throw new AppStorePreparationRefusal(
      `Build ${attributes.version ?? "(unknown)"} has expired and cannot be attached to a ` +
        "version. Upload a newer build.",
    );
  }
  if (attributes.processingState !== ATTACHABLE_BUILD_PROCESSING_STATE) {
    const reported = attributes.processingState ?? "in an unreported processing state";
    throw new AppStorePreparationRefusal(
      `Build ${attributes.version ?? "(unknown)"} is ${reported}, not ` +
        `${ATTACHABLE_BUILD_PROCESSING_STATE}. Apple only attaches a fully processed build.`,
    );
  }

  return record;
}

/** A build number can only be ordered against another when both are plain digits. */
export function isComparableBuildNumber(buildNumber) {
  return /^\d+$/.test(String(buildNumber ?? ""));
}

/**
 * What this run may do about the build already attached to the version record, decided
 * before anything is written.
 *
 * Two rules the captain set have to hold at once, and the obvious implementation of either
 * one breaks the other:
 *
 *   - Never silently swap the binary under a version somebody may be part-way through
 *     preparing, and never step backwards onto an older build.
 *   - Never produce a red run for an outcome that is expected. Ordinary iteration is a
 *     prepared version carrying build 100, a fix merged, the deploy uploading 101, and the
 *     chained run finding 100 attached - refusing that is refusing the exact case the
 *     automation exists to handle.
 *
 * So a strictly NEWER build replaces an older one and says so loudly, `--build` replaces
 * whatever a human named, an identical build is an idempotent no-op, and anything else -
 * an attached build that is newer, equal-but-different, or not comparable at all - is a
 * refusal.
 */
export function resolveAttachmentPlan({
  versionString,
  attachment,
  selectedBuildId,
  selectedBuildNumber,
  buildExplicitlyRequested = false,
}) {
  assertVersionString(versionString);

  if (!attachment?.buildId) {
    return {action: "attach", message: null};
  }

  if (attachment.buildId === selectedBuildId) {
    return {
      action: "already-attached",
      message: `Build ${selectedBuildNumber} is already attached to version ${versionString}.`,
    };
  }

  const attachedBuildNumber = attachment.buildNumber ?? "(unknown)";
  const replacement = (why) => ({
    action: "replace",
    message:
      `Replacing the build attached to version ${versionString}: build ${attachedBuildNumber} ` +
      `is being swapped out for build ${selectedBuildNumber}, ${why}.`,
  });

  if (buildExplicitlyRequested) return replacement("which --build named explicitly");

  const comparable =
    isComparableBuildNumber(attachment.buildNumber) &&
    isComparableBuildNumber(selectedBuildNumber);
  if (comparable && BigInt(selectedBuildNumber) > BigInt(attachment.buildNumber)) {
    return replacement("which is newer than the one attached");
  }

  return {
    action: "refuse",
    message:
      `App Store version ${versionString} already has build ${attachedBuildNumber} attached, ` +
      `which is not older than build ${selectedBuildNumber}. Refusing to swap the binary under ` +
      "a version somebody may be part-way through preparing. Re-run with " +
      `--build ${selectedBuildNumber} to say that is what you mean, or attach it in App Store ` +
      "Connect.",
  };
}

/**
 * The one conflict decidable before the wait: an attached build whose number cannot be
 * ordered can never turn out to be older, so without an explicit `--build` this run can
 * only ever refuse. Saying so now costs seconds instead of the whole polling budget.
 */
export function earlyAttachmentRefusal({
  versionString,
  attachment,
  buildExplicitlyRequested = false,
}) {
  if (!attachment?.buildId || buildExplicitlyRequested) return null;
  if (isComparableBuildNumber(attachment.buildNumber)) return null;

  return (
    `App Store version ${versionString} has build ` +
    `${attachment.buildNumber ?? "(unknown)"} attached, whose build number cannot be ordered ` +
    "against the one this run would select, so no build can be shown to be newer than it. " +
    "Re-run with --build <number> to name the build you mean, or attach it in App Store Connect."
  );
}

/**
 * Locales whose release notes are still empty.
 *
 * Apple requires "What's New" on every update, and this pipeline deliberately does not write
 * it: the repository's App Store copy (`data/ascend-support-page-and-product-page-package/`)
 * records the listing that is already live rather than driving it, so pushing from here would
 * overwrite the captain's listing from a document that is a transcript, not a source.
 * Reporting the gap is the honest half.
 */
export function localesMissingReleaseNotes(localizations) {
  return (localizations ?? [])
    .filter((localization) => String(localization?.attributes?.whatsNew ?? "").trim() === "")
    .map((localization) => localization?.attributes?.locale ?? "(unknown locale)")
    .sort();
}

/**
 * What a human still has to do. This list is the end of the automation, on purpose.
 */
export function manualNextSteps({appId, versionString, buildNumber, missingReleaseNotes = []}) {
  const steps = [];

  if (missingReleaseNotes.length > 0) {
    steps.push(
      `Write the "What's New" release notes - still empty for: ${missingReleaseNotes.join(", ")}. ` +
        "Apple rejects an update without them, and nothing in this repository owns that copy.",
    );
  }

  steps.push(
    `Read version ${versionString} end to end in App Store Connect, build ${buildNumber} attached.`,
    "Confirm the App Privacy answers, age rating, and pricing still match what shipped.",
    "Press Submit for Review yourself. No automation in this repository does that, by design.",
  );

  if (appId) {
    steps.push(`https://appstoreconnect.apple.com/apps/${appId}/distribution`);
  }

  return steps;
}
