/**
 * Repairs the placeholder identities real accounts leave on staging boards.
 *
 * The seed dresses its own synthetic climbers, and `seed-content-ready.mjs`
 * dresses the one account being captured. Nobody owned the rest: the QA and
 * tester accounts that signed into staging, finished a climb, and left a real
 * finisher document behind carrying whatever name the sign-in produced. Staging
 * boards therefore carried "CHANGE ME" - the placeholder `SignInNamePlaceholder`
 * publishes for an Apple account that supplied no name - beside "Content
 * Capture" and "Climber 6J84R7", on the same podiums a marketing capture points
 * a camera at.
 *
 * Three rules keep this honest:
 *
 * - It only touches an identity the shared contract already calls unfit to
 *   photograph. A real climber who published a real name keeps it.
 * - It writes `users/{uid}/public_profile/current` and nothing else. That is the
 *   one validated write path for account-authored identity, and the deployed
 *   `onPublicProfileIdentityWritten` trigger fans the new name out to
 *   `leaderboard_stats` and every replay projection. Writing those directly is
 *   how two copies of an identity become two different identities.
 * - It never renames an identity a seed owns. A persona publishing an unfit name
 *   is a defect in `profile-fixtures.mjs`, and renaming it here would fix the
 *   board until the next seed wrote the fixture name straight back - a repair
 *   that has to be re-run to stay true is not a repair. Those fail the run.
 *
 * The names are assigned by uid, so a re-run reassigns the same name rather than
 * shuffling who is who between capture sessions.
 */

import {createHash} from "node:crypto";

import {unphotographableDisplayName} from "../seed/lib/content-ready-contract.mjs";
import {isAllowedDisplayName} from "../seed/lib/public-identity-contract.mjs";

/**
 * Names for accounts that published none of their own.
 *
 * Deliberately disjoint from `SEEDED_DISPLAY_NAMES` and from the profile
 * personas: these climbers stand on the same boards, and a repeated name reads
 * as one person posting twice.
 */
export const REPAIR_DISPLAY_NAMES = Object.freeze([
  "Adrian Voss",
  "Bianca Ferrell",
  "Camille Duarte",
  "Desmond Okoye",
  "Elena Marchetti",
  "Felix Nordstrom",
  "Georgia Vance",
  "Hassan Rahimi",
  "Imogen Halloway",
  "Julian Este",
  "Karina Belmonte",
  "Lucian Ward",
  "Marisol Aguirre",
  "Nikolai Brandt",
  "Olivia Renard",
  "Patrick Devlin",
]);

/**
 * Chooses one account's replacement name, deterministically and without
 * colliding with a name already standing on the boards.
 * @param {string} uid Account being repaired.
 * @param {Set<string>} taken Names already in use, lowercased.
 * @return {string} The name to publish.
 */
export function repairNameFor(uid, taken) {
  const digest = createHash("sha256").update(uid).digest();
  const start = digest.readUInt32BE(0) % REPAIR_DISPLAY_NAMES.length;

  for (let offset = 0; offset < REPAIR_DISPLAY_NAMES.length; offset += 1) {
    const candidate = REPAIR_DISPLAY_NAMES[(start + offset) % REPAIR_DISPLAY_NAMES.length];
    if (!taken.has(candidate.toLowerCase())) {
      return candidate;
    }
  }

  throw new Error(
    `Every name in REPAIR_DISPLAY_NAMES is already published, so ${uid} has ` +
    "nothing left to take. Add more names."
  );
}

/**
 * Decides what to rename, given every published identity in the environment.
 *
 * Pure, so the decision is testable without an environment: the caller reads the
 * mirrors and applies the plan.
 * @param {object[]} identities `{uid, displayName, photoURL}` per published mirror.
 * @param {object} options Planning options.
 * @param {string} options.protectedUid Account being captured; never renamed here.
 * @param {Set<string>} [options.seedOwnedUids] Identities a fixture republishes every run.
 * @return {object} `{renames, photoless, seedOwnedFailures}`.
 */
export function planIdentityRepair(identities, {protectedUid, seedOwnedUids = new Set()} = {}) {
  const keepers = identities.filter((identity) =>
    identity.uid !== protectedUid &&
    unphotographableDisplayName(identity.displayName) === null
  );
  const taken = new Set(keepers.map((identity) => identity.displayName.trim().toLowerCase()));

  const renames = [];
  const seedOwnedFailures = [];
  for (const identity of identities) {
    if (identity.uid === protectedUid) {
      continue;
    }

    const reason = unphotographableDisplayName(identity.displayName);
    if (reason === null) {
      continue;
    }

    if (seedOwnedUids.has(identity.uid)) {
      seedOwnedFailures.push({uid: identity.uid, displayName: identity.displayName, reason});
      continue;
    }

    const displayName = repairNameFor(identity.uid, taken);
    taken.add(displayName.toLowerCase());

    // The repair pool is fixed and screened, so this can only fire if somebody
    // adds a name to it that the shared policy rejects.
    if (!isAllowedDisplayName(displayName)) {
      throw new Error(`REPAIR_DISPLAY_NAMES contains an unpublishable name: ${displayName}`);
    }

    renames.push({
      uid: identity.uid,
      from: identity.displayName ?? null,
      to: displayName,
      reason,
    });
  }

  // Reported, never invented. A face has to come from an image somebody chose;
  // the seed has exactly one avatar per synthetic climber and one reserved for
  // the capture account, with none spare.
  const photoless = identities
    .filter((identity) => typeof identity.photoURL !== "string" || identity.photoURL.trim() === "")
    .map((identity) => identity.uid);

  return {renames, photoless, seedOwnedFailures};
}
