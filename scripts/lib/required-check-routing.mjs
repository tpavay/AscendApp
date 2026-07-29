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
  ".github/workflows/**",
];

// Every entry here has to be defensible as "no job anywhere verifies this, and
// nothing deploys it". `docs/**` qualifies only because the four docs the
// scripts suite reads are in CI_RELEVANT_PATHS, which is checked first.
export const VERIFICATION_IRRELEVANT_PATHS = [
  "docs/**",
  "AppStoreAssets/**",
  "README.md",
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
