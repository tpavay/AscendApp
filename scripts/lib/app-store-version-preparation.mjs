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
    throw new Error(
      "No MARKETING_VERSION found in the Xcode project. Refusing to guess the marketing version.",
    );
  }

  const distinct = [...new Set(values)];
  if (distinct.length > 1) {
    throw new Error(
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
    throw new Error(
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
 * The existing version record this run may write to, or `null` when the version has to be
 * created.
 *
 * The listing is re-filtered locally rather than trusted: a `filter[versionString]` Apple
 * silently ignored would otherwise hand back some other version - very possibly the live
 * one - as the record to attach a build to.
 */
export function selectPreparableVersionRecord(versionRecords, versionString) {
  assertVersionString(versionString);

  const records = versionRecords ?? [];
  const matching = records.filter(
    (record) => record?.attributes?.versionString === versionString,
  );

  if (matching.length === 0) return null;

  if (matching.length > 1) {
    throw new Error(
      `${matching.length} App Store version records share version string ${versionString}: ` +
        `${matching.map(describeVersion).join("; ")}. Resolve this in App Store Connect first.`,
    );
  }

  const [record] = matching;
  const state = versionState(record);
  if (!PREPARABLE_VERSION_STATES.has(state)) {
    throw new Error(
      `App Store version ${versionString} is ${state ?? "in an unreported state"}, which this ` +
        "script may not write to. A version that is in review, awaiting release, or already " +
        "released is the captain's to steer in App Store Connect. Bump MARKETING_VERSION if " +
        "this build is meant to be the next release.",
    );
  }

  return record;
}

function buildNumberOf(record) {
  return String(record?.build?.attributes?.version ?? "");
}

function describeBuild(record) {
  const attributes = record?.build?.attributes ?? {};
  return (
    `${attributes.version ?? "(unknown)"} (${attributes.processingState ?? "unknown state"}` +
    `${attributes.expired ? ", expired" : ""}, train ${record?.trainVersion ?? "unknown"})`
  );
}

/**
 * The build to attach.
 *
 * `--build` pins one exactly. Without it the rule is the newest processed, unexpired build
 * in this marketing version's train - the same build a human picks from the "Build" list in
 * App Store Connect, stated as a rule rather than left to whatever order Apple returns.
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
    throw new Error(
      `APP_STORE_CONTRACT_FILTER_IGNORED: App Store Connect returned ${records.length} build(s), ` +
        `none of them in train ${versionString}: ${records.map(describeBuild).join("; ")}. ` +
        "No returned build can be trusted to belong to this version.",
    );
  }

  if (requestedBuildNumber !== undefined && requestedBuildNumber !== null) {
    const requested = String(requestedBuildNumber);
    const matching = inTrain.filter((record) => buildNumberOf(record) === requested);

    if (matching.length === 0) {
      throw new Error(
        `No build ${requested} in train ${versionString}. Found: ` +
          `${inTrain.map(describeBuild).join("; ") || "(none)"}.`,
      );
    }
    if (matching.length > 1) {
      throw new Error(
        `${matching.length} builds in train ${versionString} report build number ${requested}: ` +
          `${matching.map(describeBuild).join("; ")}.`,
      );
    }

    const [record] = matching;
    assertBuildIsAttachable(record);
    return record;
  }

  const attachable = inTrain.filter(
    (record) =>
      record?.build?.attributes?.processingState === ATTACHABLE_BUILD_PROCESSING_STATE &&
      record?.build?.attributes?.expired !== true,
  );

  if (attachable.length === 0) {
    return null;
  }

  const highest = attachable.reduce((best, record) =>
    BigInt(buildNumberOf(record)) > BigInt(buildNumberOf(best)) ? record : best,
  );
  const tied = attachable.filter((record) => buildNumberOf(record) === buildNumberOf(highest));
  if (tied.length > 1) {
    throw new Error(
      `${tied.length} builds in train ${versionString} share build number ` +
        `${buildNumberOf(highest)}: ${tied.map(describeBuild).join("; ")}. ` +
        "Re-run with --build <number> to say which one you mean.",
    );
  }

  return highest;
}

export function assertBuildIsAttachable(record) {
  const attributes = record?.build?.attributes ?? {};

  if (attributes.expired === true) {
    throw new Error(
      `Build ${attributes.version ?? "(unknown)"} has expired and cannot be attached to a ` +
        "version. Upload a newer build.",
    );
  }
  if (attributes.processingState !== ATTACHABLE_BUILD_PROCESSING_STATE) {
    const reported = attributes.processingState ?? "in an unreported processing state";
    throw new Error(
      `Build ${attributes.version ?? "(unknown)"} is ${reported}, not ` +
        `${ATTACHABLE_BUILD_PROCESSING_STATE}. Apple only attaches a fully processed build.`,
    );
  }

  return record;
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
