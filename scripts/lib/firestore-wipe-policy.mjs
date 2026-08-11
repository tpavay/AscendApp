import {readFileSync} from "node:fs";
import {resolve} from "node:path";

// Migration history answers whether a repair has already run in an environment.
// A database reset must not erase that audit trail or cause completed repairs to
// run again against newly seeded data.
export const PROTECTED_WIPE_COLLECTION_IDS = Object.freeze([
  "_migrations",
]);

// These collections outlived their producers and therefore have no current
// Firestore rule declaration to act as their reviewed deletion contract.
// Keeping them here preserves the only cleanup path for their retained data.
export const LEGACY_DELETABLE_WIPE_COLLECTION_IDS = Object.freeze([
  "email_rate_limits",
  "oauthStates",
]);

// Deleting these fires the Firestore triggers that rederive the public
// projections, so they have to be deleted before the projections they feed.
// Deleting a projection first only invites the trigger to write the row back,
// which leaves rederived standings behind a wipe that reported success.
export const WIPE_SOURCE_COLLECTION_IDS = Object.freeze([
  "users",
]);

const DOCUMENTS_MATCH_PATTERN = /^match\s+\/databases\/\{[^{}]*\}\/documents\s*\{?$/;
const COLLECTION_MATCH_PATTERN = /^match\s+\/([^/{}\s]+)\/\{[^{}]*\}\s*\{?$/;

/**
 * Reads the direct child collection matches under the Firestore database.
 * Those matches are the reviewed top-level data contract for the app.
 *
 * Nesting is resolved from brace depth rather than indentation, so reformatting
 * the rules cannot silently promote a subcollection into the deletable set.
 * @param {string} source Firestore rules source.
 * @return {string[]} Sorted top-level collection IDs.
 */
export function topLevelRuleCollectionIds(source) {
  const ids = [];
  let depth = 0;
  let documentsDepth = null;

  for (const rawLine of source.split("\n")) {
    const line = rawLine.replace(/\/\/.*$/, "").trim();
    if (line !== "") {
      if (documentsDepth === null && DOCUMENTS_MATCH_PATTERN.test(line)) {
        documentsDepth = depth + 1;
      } else if (depth === documentsDepth) {
        const collection = COLLECTION_MATCH_PATTERN.exec(line);
        if (collection) {
          ids.push(collection[1]);
        }
      }

      depth += braceDepthDelta(line);
    }
  }

  return [...new Set(ids)].sort();
}

/**
 * Net block-nesting change one rules line contributes.
 *
 * Brace pairs that open and close on the same line - path variables such as
 * `{userId}` - change no nesting, so they are removed before counting.
 * @param {string} line One comment-stripped rules line.
 * @return {number} Net brace depth change.
 */
function braceDepthDelta(line) {
  let remaining = line;
  let previous = null;
  while (remaining !== previous) {
    previous = remaining;
    remaining = remaining.replace(/\{[^{}]*\}/g, "");
  }

  let delta = 0;
  for (const character of remaining) {
    if (character === "{") {
      delta += 1;
    } else if (character === "}") {
      delta -= 1;
    }
  }
  return delta;
}

/**
 * Returns every collection the wipe may delete without a second hand-maintained
 * allowlist. Adding a reviewed top-level rule automatically keeps resets current.
 * @param {string} repoRoot Repository root.
 * @return {string[]} Sorted collection IDs.
 */
export function reviewedWipeCollectionIds(repoRoot) {
  const rules = readFileSync(resolve(repoRoot, "firestore.rules"), "utf8");
  return [...new Set([
    ...topLevelRuleCollectionIds(rules),
    ...LEGACY_DELETABLE_WIPE_COLLECTION_IDS,
  ])].sort();
}

/**
 * Classifies live top-level collections before any destructive work begins.
 * @param {string[]} existingIds Collection IDs currently present in Firestore.
 * @param {Iterable<string>} reviewedIds Reviewed, deletable collection IDs.
 * @param {Iterable<string>} protectedIds Recognized collection IDs to preserve.
 * @return {{collectionsToDelete: string[], protectedCollections: string[], unknownCollections: string[]}}
 *   The complete wipe decision.
 */
export function classifyWipeCollections(
  existingIds,
  reviewedIds,
  protectedIds = PROTECTED_WIPE_COLLECTION_IDS
) {
  const reviewed = new Set(reviewedIds);
  const protectedSet = new Set(protectedIds);
  const existing = [...new Set(existingIds)].sort();

  return {
    collectionsToDelete: orderedForDeletion(existing.filter(
      (collectionId) => reviewed.has(collectionId) && !protectedSet.has(collectionId)
    )),
    protectedCollections: existing.filter((collectionId) => protectedSet.has(collectionId)),
    unknownCollections: existing.filter(
      (collectionId) => !reviewed.has(collectionId) && !protectedSet.has(collectionId)
    ),
  };
}

/**
 * Orders one deletion set so every trigger source precedes the projections its
 * triggers rederive. Everything else keeps its stable alphabetical order.
 * @param {string[]} collectionIds Collections the wipe will delete.
 * @return {string[]} The same collections in a safe deletion order.
 */
function orderedForDeletion(collectionIds) {
  const sources = WIPE_SOURCE_COLLECTION_IDS.filter(
    (collectionId) => collectionIds.includes(collectionId)
  );
  return [
    ...sources,
    ...collectionIds.filter((collectionId) => !sources.includes(collectionId)),
  ];
}

/**
 * Finds literal root collection calls in one JavaScript or TypeScript source.
 * This is used by regression coverage to ensure server writers declare their
 * collection in Firestore rules or in the protected set.
 * @param {string} source JavaScript or TypeScript source.
 * @return {string[]} Sorted collection IDs.
 */
export function sourceDeclaredTopLevelCollectionIds(source) {
  const constants = new Map();
  const constantPattern = /\bconst\s+([A-Z][A-Z0-9_]*)\s*(?::[^=;]+)?=\s*["']([^"']+)["']\s*;/g;
  for (const match of source.matchAll(constantPattern)) {
    constants.set(match[1], match[2]);
  }

  const ids = [];
  const callPattern = /(?:\b(?:admin\.firestore|getFirestore)\(\s*[^()]*\)|\b(?:db|firestore|this\.firestore))\s*\.collection\(\s*(?:["']([^"']+)["']|([A-Z][A-Z0-9_]*))\s*\)/g;
  for (const match of source.matchAll(callPattern)) {
    const collectionId = match[1] ?? constants.get(match[2]);
    if (collectionId) {
      ids.push(collectionId);
    }
  }

  return [...new Set(ids)].sort();
}
