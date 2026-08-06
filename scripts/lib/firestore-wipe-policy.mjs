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

/**
 * Reads the direct child collection matches under the Firestore database.
 * Those matches are the reviewed top-level data contract for the app.
 * @param {string} source Firestore rules source.
 * @return {string[]} Sorted top-level collection IDs.
 */
export function topLevelRuleCollectionIds(source) {
  const ids = [];
  const pattern = /^ {4}match \/([^/{}]+)\/\{[^}]+\} \{$/gm;

  for (const match of source.matchAll(pattern)) {
    ids.push(match[1]);
  }

  return [...new Set(ids)].sort();
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
    collectionsToDelete: existing.filter(
      (collectionId) => reviewed.has(collectionId) && !protectedSet.has(collectionId)
    ),
    protectedCollections: existing.filter((collectionId) => protectedSet.has(collectionId)),
    unknownCollections: existing.filter(
      (collectionId) => !reviewed.has(collectionId) && !protectedSet.has(collectionId)
    ),
  };
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
  const callPattern = /\b(?:db|firestore|this\.firestore)\s*\.collection\(\s*(?:["']([^"']+)["']|([A-Z][A-Z0-9_]*))\s*\)/g;
  for (const match of source.matchAll(callPattern)) {
    const collectionId = match[1] ?? constants.get(match[2]);
    if (collectionId) {
      ids.push(collectionId);
    }
  }

  return [...new Set(ids)].sort();
}
