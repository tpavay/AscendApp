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

const HALLOWEEN_IMAGES = "images/drops/halloween-2026";

/**
 * The thumbnail the app itself draws for an item (`AthleteGear.thumbnailName`,
 * `Assets.xcassets/Gear`), copied to the marketing site.
 * @param {string} itemId - Catalogue item id
 * @return {string} Site-relative path
 */
function halloweenItemImage(itemId: string): string {
  return `${HALLOWEEN_IMAGES}/${itemId}.png`;
}

/**
 * Halloween 2026 (`halloween-2026` in `web/public/unlocks/catalog.json`,
 * October 1-31). Item names are `AthleteGear.title`; requirements are
 * `UnlockCopy.requirement`'s wording for each item's catalogue threshold.
 * The send script re-checks every requirement against the hosted catalogue
 * of the environment it sends from, so a threshold changed in the catalogue
 * stops the send instead of mailing a stale ladder.
 *
 * The round 13 mock drew a Spiderweb Tank and a Pumpkin Stripe Tank; the
 * shipped catalogue dropped both printed tanks, so Candy Corn (15 climbs)
 * and the Chocolate Bar (10K steps) stand where the app has them.
 */
const HALLOWEEN_2026: DropEmailDefinition = {
  minimumAppStoreVersion: "1.2.2",
  content: {
    banner: "All October, the first 5,000 steps of every climb are haunted.",
    ctaLabel: "Climb tonight",
    ctaUrl: APP_STORE_URL,
    dropId: "halloween-2026",
    earnHeading: "How to earn",
    eyebrow: "October 1 to 31",
    facts: [
      {value: "15", label: "To earn"},
      {value: "Oct 31", label: "Last day"},
      {value: "Forever", label: "Yours to keep"},
    ],
    groups: [
      {
        heading: "Open the app",
        lead: {
          badge: "Free",
          catalogItemId: "pumpkin_classic",
          description: "Open Ascend in October. Carry it up the mountain.",
          imagePath: halloweenItemImage("pumpkin_classic"),
          name: "Pumpkin",
          requirement: "OPEN ASCEND",
        },
        items: [],
      },
      {
        heading: "Climb in October",
        items: [
          ["pumpkin_ghost", "Ghost Pumpkin", "1 CLIMB"],
          ["witch_hat", "Witch Hat", "3 CLIMBS"],
          ["pumpkin_heirloom", "Heirloom Pumpkin", "5 CLIMBS"],
          ["pumpkin_lantern", "Jack-o'-Lantern", "10 CLIMBS"],
          ["candy_corn", "Candy Corn", "15 CLIMBS"],
          ["ghost_sheet", "Ghost Sheet", "20 CLIMBS"],
        ].map(([catalogItemId, name, requirement]) => ({
          catalogItemId,
          imagePath: halloweenItemImage(catalogItemId),
          name,
          requirement,
        })),
      },
      {
        heading: "Show up",
        items: [
          ["witching_shorts", "Witching Hour Shorts", "7 DAYS"],
          ["ember_trainers", "Ember Trainers", "CLIMB OCT 31"],
        ].map(([catalogItemId, name, requirement]) => ({
          catalogItemId,
          imagePath: halloweenItemImage(catalogItemId),
          name,
          requirement,
        })),
        legendary: {
          catalogItemId: "pumpkin_head",
          description: "Climb every day in October. " +
            "Wear the pumpkin on your shoulders.",
          imagePath: halloweenItemImage("pumpkin_head"),
          name: "Pumpkin Head",
          requirement: "EVERY DAY",
        },
      },
      {
        heading: "Steps in October",
        items: [
          ["chocolate_bar", "Chocolate Bar", "10K STEPS"],
          ["pumpkin_midnight", "Midnight Pumpkin", "25K STEPS"],
          ["pumpkin_giant", "Giant Pumpkin", "50K STEPS"],
          ["glow_trainers", "Glow Trainers", "75K STEPS"],
        ].map(([catalogItemId, name, requirement]) => ({
          catalogItemId,
          imagePath: halloweenItemImage(catalogItemId),
          name,
          requirement,
        })),
        legendary: {
          catalogItemId: "pumpkin_giant_lantern",
          description: "100,000 October steps. " +
            "Pressed overhead, lit, the whole climb.",
          imagePath: halloweenItemImage("pumpkin_giant_lantern"),
          name: "Giant Jack-o'-Lantern",
          requirement: "100K STEPS",
        },
      },
    ],
    headlineLines: ["HALLOWEEN", "IS ON."],
    heroImageAlt: "Carrying a jack-o'-lantern through a webbed gate",
    heroImagePath: `${HALLOWEEN_IMAGES}/hero.jpg`,
    intro: "Open Ascend in October and your pumpkin is in. Every climb " +
      "this month counts toward 14 more. Earn them and they stay yours.",
    motifImagePath: `${HALLOWEEN_IMAGES}/cobweb.png`,
    preheader: "Your pumpkin is in. 14 more to earn by climbing in October.",
    subject: "Halloween is on",
    tag: "Halloween",
    theme: "halloween",
    whyReceived: "You received this because you turned on drop emails " +
      "in Ascend.",
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
  };
}
