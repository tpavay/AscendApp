// The required `iOS Verify (Staging)` check is owned by ci.yml's ios-verify job
// whenever ci.yml triggers. This module decides the one case where the fallback
// workflow may claim that name instead: a pull request whose every changed path
// is positively known to need no verification.
//
// It is an allowlist, not the inverse of the CI trigger. ci.yml gates only the
// paths its jobs verify, so unverified-but-shippable inputs - firestore.rules,
// storage.rules, firebase.json, .firebaserc, Gemfile, fastlane/** - are neither
// CI-relevant nor safe to auto-green: deploy-staging.yml ships them on merge.
// Anything unrecognised stays blocked.

// Mirrors the `required-check-paths` block in .github/workflows/ci.yml. The two
// are asserted byte-identical by scripts/test/ci-required-check-routing.test.mjs.
export const CI_RELEVANT_PATHS = [
  "AscendApp/**",
  "AscendAppTests/**",
  "AscendLiveActivityWidgets/**",
  "AscendApp.xcodeproj/**",
  "functions/**",
  "firestore.indexes.json",
  "scripts/**",
  "web/**",
  "package.json",
  "package-lock.json",
  "SharedTestVectors/**",
  "docs/superwall-paywall-setup.md",
  "docs/onboarding-design-guide.md",
  "docs/app-store-brief.md",
  "docs/launch-readiness-audit.md",
  "CLAUDE.md",
  // AGENTS.md is a git-mode-120000 symlink to CLAUDE.md and nothing reads it by
  // name, so it gates exactly as CLAUDE.md does. Allowlisting it would let a PR
  // replace the symlink with a divergent file behind an unverified check.
  "AGENTS.md",
  ".github/workflows/**",
];

// Every entry here has to be defensible as "no job anywhere verifies this, and
// nothing deploys it". `docs/**` qualifies only because the four docs the
// scripts suite reads are in CI_RELEVANT_PATHS, which is checked first.
//
// `.ruby-version` is deliberately absent: it selects the Ruby that resolves the
// Gemfile, which is the Fastlane build and signing toolchain.
export const VERIFICATION_IRRELEVANT_PATHS = [
  "docs/**",
  "AppStoreAssets/**",
  "data/ascend-support-page-and-product-page-package/**",
  ".claude/skills/**",
  "README.md",
  ".gitignore",
];

// dorny/paths-filter and GitHub both accept full picomatch syntax, and this
// module models exactly two shapes. Every other metacharacter has to be a hard
// error rather than a silent fall-through to an exact-filename comparison - a
// leading `!` in particular would otherwise invert the decision it encodes.
const UNSUPPORTED_PATTERN_CHARACTERS = /[!?*[\]{}()\\]/;

export function assertSupportedPattern(pattern, source) {
  if (typeof pattern !== "string" || pattern.length === 0) {
    throw new Error(`${source} contains a non-string or empty path pattern`);
  }

  const body = pattern.endsWith("/**") ? pattern.slice(0, -3) : pattern;

  if (body.length === 0 || UNSUPPORTED_PATTERN_CHARACTERS.test(body)) {
    throw new Error(
      `${source} uses the glob "${pattern}", which this routing model cannot evaluate. Use a literal path or a "dir/**" prefix, or teach matchesPattern the new shape.`,
    );
  }
}

export function matchesPattern(path, pattern) {
  if (pattern.endsWith("/**")) {
    return path.startsWith(`${pattern.slice(0, -3)}/`);
  }

  return path === pattern;
}

export function matchesAny(path, patterns) {
  return patterns.some((pattern) => matchesPattern(path, pattern));
}

for (const [source, patterns] of [
  ["CI_RELEVANT_PATHS", CI_RELEVANT_PATHS],
  ["VERIFICATION_IRRELEVANT_PATHS", VERIFICATION_IRRELEVANT_PATHS],
]) {
  for (const pattern of patterns) {
    assertSupportedPattern(pattern, source);
  }
}

function parseChangedFileCount(value) {
  if (typeof value === "number") {
    return Number.isInteger(value) && value >= 0 ? value : null;
  }

  if (typeof value === "string" && /^\d+$/.test(value.trim())) {
    return Number.parseInt(value.trim(), 10);
  }

  return null;
}

// Turns the pull request files endpoint's payload into the path list to
// classify, refusing rather than guessing whenever the payload cannot be
// trusted. This lives here, not in the entry point, because the truncation
// guard is the only thing standing between a silently capped diff and an
// allowlist-only verdict over paths the API never returned.
export function changedPathsFromApiEntries(entries, expectedChangedFiles) {
  if (!Array.isArray(entries)) {
    return {
      ok: false,
      reason: "The pull request file list was not a JSON array.",
    };
  }

  const expected = parseChangedFileCount(expectedChangedFiles);

  if (expected === null) {
    return {
      ok: false,
      reason: `"${expectedChangedFiles}" is not a valid changed-file count.`,
    };
  }

  const filenames = entries.map((entry) => entry?.filename);

  if (filenames.some((name) => typeof name !== "string" || name.length === 0)) {
    return {
      ok: false,
      reason: "The pull request file list contained an entry with no filename.",
    };
  }

  // The files endpoint caps out at 3000 entries, and a silently truncated diff
  // would classify the paths it never saw as absent.
  if (filenames.length !== expected) {
    return {
      ok: false,
      reason: `The pull request reports ${expected} changed files but the API listed ${filenames.length}. Refusing to classify a truncated diff.`,
    };
  }

  const previousNames = entries.map((entry) => entry?.previous_filename);

  if (
    previousNames.some(
      (name) =>
        name !== undefined && (typeof name !== "string" || name.length === 0),
    )
  ) {
    return {
      ok: false,
      reason:
        "The pull request file list contained an unreadable previous_filename.",
    };
  }

  // A rename reports only its new path in `filename`, so the old path is pulled
  // in separately - moving a Swift file out of AscendApp/ is still an iOS
  // change.
  const paths = [
    ...new Set(
      entries.flatMap((entry) =>
        [entry.filename, entry.previous_filename].filter(
          (path) => typeof path === "string" && path.length > 0,
        ),
      ),
    ),
  ];

  return { ok: true, paths };
}

// CI-relevance is decided before the allowlist, so a path may appear under both
// and still route to real CI. That precedence is what lets `docs/**` be
// allowlisted while the four docs the scripts suite asserts against are not.
export function classifyChangedPaths(changedPaths) {
  if (!Array.isArray(changedPaths) || changedPaths.length === 0) {
    return {
      fallbackEligible: false,
      reason:
        "No changed paths were classified, so the diff could not be proven verification-irrelevant.",
      blockedBy: [],
    };
  }

  const malformed = changedPaths.filter(
    (path) => typeof path !== "string" || path.length === 0,
  );

  if (malformed.length > 0) {
    return {
      fallbackEligible: false,
      reason: `The diff contained ${malformed.length} unreadable path entries.`,
      blockedBy: [],
    };
  }

  const ciRelevant = changedPaths.filter((path) =>
    matchesAny(path, CI_RELEVANT_PATHS),
  );

  if (ciRelevant.length > 0) {
    return {
      fallbackEligible: false,
      reason:
        "CI-relevant paths changed, so ci.yml owns the required check for this pull request.",
      blockedBy: ciRelevant,
    };
  }

  const unclassified = changedPaths.filter(
    (path) => !matchesAny(path, VERIFICATION_IRRELEVANT_PATHS),
  );

  if (unclassified.length > 0) {
    return {
      fallbackEligible: false,
      reason:
        "Paths outside the verification-irrelevant allowlist changed. Nothing verifies or auto-greens them; add a verify job and the paths to the CI trigger, or allowlist them deliberately.",
      blockedBy: unclassified,
    };
  }

  return {
    fallbackEligible: true,
    reason:
      "Every changed path is on the verification-irrelevant allowlist, so no verification job exists to run.",
    blockedBy: [],
  };
}
