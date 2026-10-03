import {DROP_ASSETS} from "./dropAssets.generated";
import type {DropEmailPayload} from "./types";

/**
 * A drop announcement as content. The whole payload minus the asset site
 * travels on every job, so the deployed renderer draws a new drop without a
 * new build.
 *
 * `minimumAppStoreVersion` is the first App Store version that contains what
 * the email promises; the send script refuses a production send until the App
 * Store reports at least that version live, because a climber who opens the
 * email before the update would look for items their build cannot give them.
 */
export interface DropEmailDefinition {
  content: Omit<DropEmailPayload, "assetBaseUrl">;
  minimumAppStoreVersion: string;
}

/**
 * Ascend's production App Store listing. Every recap and drop CTA points
 * here rather than at a deep link (`ascend-web-email`): no universal link
 * exists yet, and for a climber who has the app it is also the Update button.
 */
export const APP_STORE_URL = "https://apps.apple.com/app/id6757202987";

/**
 * The published, content-hashed path of one of a drop's pictures, by its
 * source name in `web/drop-email-assets/<dropId>/`. Never typed by hand: the
 * names come from `scripts/build-drop-email-assets.mjs`, so a changed picture
 * is always a new address that no mailbox can have cached.
 * @param {string} dropId - Drop id
 * @param {string} source - Source file name, e.g. "pumpkin_ghost.png"
 * @return {string} Site-relative path
 */
export function dropAsset(dropId: string, source: string): string {
  const path = DROP_ASSETS[dropId]?.[source];
  if (!path) {
    throw new Error(`No published picture "${source}" for drop "${dropId}". ` +
      "Run: node scripts/build-drop-email-assets.mjs");
  }
  return path;
}

/**
 * The thumbnail the app itself draws for an item (`AthleteGear.thumbnailName`,
 * `Assets.xcassets/Gear`), copied into the drop's assets.
 * @param {string} itemId - Catalogue item id
 * @return {string} Site-relative path
 */
function halloweenItemImage(itemId: string): string {
  return dropAsset("halloween-2026", `${itemId}.png`);
}

/**
 * The sender's postal address for the footer of every drop, or null to leave
 * the line out. Whether and which address Ascend publishes is the captain's
 * decision; nothing refuses a send without one.
 */
export const SENDER_POSTAL_ADDRESS: string | null = null;

/**
 * Builds a group's tiles from `[catalogItemId, name, requirement]` rows.
 * @param {Array<[string, string, string]>} rows - Item rows
 * @return {DropEmailPayload["groups"][number]["items"]} Tiles
 */
function halloweenTiles(
  rows: Array<[string, string, string]>
): DropEmailPayload["groups"][number]["items"] {
  return rows.map(([catalogItemId, name, requirement]) => ({
    catalogItemId,
    imagePath: halloweenItemImage(catalogItemId),
    name,
    requirement,
  }));
}

/**
 * Halloween 2026 (`halloween-2026` in `web/public/unlocks/catalog.json`,
 * October 1-31), worded to the approved Halloween redesign (2026-10-02): the
 * October page's headline and subline, all 15 items in the page's three
 * groups, item names as the redesign names them ("The Giant"), thresholds as
 * bare counts, and the ruling that every climb saved in October counts from
 * October 1, however late the update lands. No rarity labels: the redesign
 * removed them from the app.
 *
 * The send script re-checks every requirement against the hosted catalogue
 * of the environment it sends from, so a threshold changed in the catalogue
 * stops the send instead of mailing a stale ladder.
 */
const HALLOWEEN_2026: DropEmailDefinition = {
  minimumAppStoreVersion: "1.2.2",
  content: {
    banner: "All October, the first 5,000 steps of every climb are haunted.",
    bannerDetail: "Lit jack-o'-lanterns, drifting ghosts and webbed gates " +
      "line that stretch of Ascend Mountain.",
    ctaLabel: "Climb tonight",
    ctaUrl: APP_STORE_URL,
    dropId: "halloween-2026",
    earnHeading: "How to earn",
    eyebrow: "October 1 to 31",
    facts: [
      {value: "15", label: "To earn"},
      {value: "Oct 1", label: "First day"},
      {value: "Oct 31", label: "Last day"},
    ],
    groups: [
      {
        heading: "Open the app",
        lead: {
          badge: "Free",
          catalogItemId: "pumpkin_classic",
          description: "Yours free for opening Ascend in October.",
          imagePath: halloweenItemImage("pumpkin_classic"),
          name: "Pumpkin",
          requirement: "Open Ascend in October",
        },
        items: [],
      },
      {
        heading: "Climbs in October",
        items: halloweenTiles([
          ["pumpkin_ghost", "Ghost Pumpkin", "1 climb"],
          ["witch_hat", "Witch Hat", "3 climbs"],
          ["pumpkin_heirloom", "Heirloom Pumpkin", "5 climbs"],
          ["pumpkin_lantern", "Jack-o'-Lantern", "10 climbs"],
          ["candy_corn", "Candy Corn", "15 climbs"],
          ["ghost_sheet", "Ghost Sheet", "20 climbs"],
        ]),
      },
      {
        heading: "Steps in October",
        items: halloweenTiles([
          ["chocolate_bar", "Chocolate Bar", "10K steps"],
          ["pumpkin_midnight", "Midnight Pumpkin", "25K steps"],
          ["pumpkin_giant", "The Giant", "50K steps"],
          ["glow_trainers", "Glow Trainers", "75K steps"],
          ["pumpkin_giant_lantern", "Giant Jack-o'-Lantern", "100K steps"],
        ]),
      },
      {
        heading: "Days in October",
        items: halloweenTiles([
          ["witching_shorts", "Witching Hour Shorts", "7 days"],
          ["pumpkin_head", "Pumpkin Head", "20 days"],
          ["ember_trainers", "Ember Trainers", "Oct 31"],
        ]),
      },
    ],
    headlineLines: ["Halloween", "is on."],
    cobweb: dropAsset("halloween-2026", "cobweb.png"),
    feature: {
      alt: "The haunted stretch: carrying a jack-o'-lantern up a webbed " +
        "stairwell",
      path: dropAsset("halloween-2026", "haunted-band.jpg"),
    },
    headerArt: {
      alt: "Jack-o'-Lantern",
      path: halloweenItemImage("pumpkin_lantern"),
    },
    intro: "Climb in October to earn Halloween gear for your athlete on " +
      "Ascend Mountain. Open the app for a free Pumpkin, then earn 14 more " +
      "by climbing. Climbs you've done since October 1 already count.",
    preheader: "Open Ascend for a free Pumpkin, then climb for 14 more " +
      "pieces of Halloween gear.",
    subject: "Halloween on the stair stepper",
    theme: "halloween",
    whyReceived: "You're getting this because you turned on email from " +
      "Ascend.",
  },
};

export const DROP_EMAILS: Readonly<Record<string, DropEmailDefinition>> =
  Object.freeze({
    [HALLOWEEN_2026.content.dropId]: HALLOWEEN_2026,
  });

/**
 * Builds the job payload for a drop, with images served from `assetBaseUrl`.
 * @param {string} dropId - Drop id, e.g. "halloween-2026"
 * @param {string} assetBaseUrl - https site the drop's images are deployed to
 * @return {DropEmailPayload} Payload to queue
 */
export function buildDropEmailPayload(
  dropId: string,
  assetBaseUrl: string
): DropEmailPayload {
  const definition = DROP_EMAILS[dropId];
  if (!definition) {
    throw new Error(`Unknown drop "${dropId}". Known: ` +
      `${Object.keys(DROP_EMAILS).join(", ")}.`);
  }
  return {
    ...definition.content,
    assetBaseUrl: assetBaseUrl.replace(/\/+$/, ""),
    ...(SENDER_POSTAL_ADDRESS ? {postalAddress: SENDER_POSTAL_ADDRESS} : {}),
  };
}
