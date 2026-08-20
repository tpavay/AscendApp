/**
 * The climb-drop timing contract.
 *
 * The sender has to keep the promise the shipped strings make, and the only
 * authority on that promise is the strings themselves - not a backlog record,
 * not a design guide. Every user-facing climb-drop surface says the alert
 * arrives *when* a climb opens, so `announceClimbDrops` sends at the open.
 *
 * The advance-notice assertions are the ones that matter. A document that
 * re-introduces "24-hour advance notice" is a promise no server-side sender
 * can keep: the hosted catalogue carries no unlock timestamp to count back
 * from, and withholding an already-published climb until a scheduled moment
 * would take a client change.
 */

import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

/** The five surfaces that make the climb-drop promise, and what they say. */
const CLIMB_DROP_COPY_SURFACES = [
  {
    file: "AscendApp/Features/Onboarding/Views/PostAuthOnboardingFlowView.swift",
    strings: [
      "Get an Ascend alert when new climbs open.",
      "Email me when climbs drop.",
    ],
  },
  {
    file: "AscendApp/Features/Profile/Views/CollectionSection.swift",
    strings: ["Be the first to know when new climbs drop."],
  },
  {
    file: "AscendApp/Features/Profile/Views/PrestigeSection.swift",
    strings: ["be first up when the next climb drops."],
  },
  {
    file: "AscendApp/Features/Account/Views/EmailPreferencesContentView.swift",
    strings: ["Ascend emails you when a climb drops"],
  },
  {
    file: "AscendApp/Features/Account/Views/NotificationSettingsView.swift",
    strings: ["New climb drops", "A new landmark opens in the catalog."],
  },
];

/** Phrases that would promise notice before a climb opens. */
const ADVANCE_NOTICE_PHRASES = [
  "24-hour advance notice",
  "24 hour advance notice",
  "24-hour notice",
  "24 hour notice",
  "advance notice of new climb",
  "notice before each climb drop",
];

/** Everywhere the promise is stated, in code or in the docs behind it. */
const PROMISE_BEARING_FILES = [
  ...CLIMB_DROP_COPY_SURFACES.map((surface) => surface.file),
  ".claude/skills/ascend-onboarding/SKILL.md",
  "docs/onboarding-design-guide.md",
  "docs/app-store-brief.md",
  "data/ascend-support-page-and-product-page-package/app-store-copy.md",
];

/**
 * Reads a repository file.
 * @param {string} path Repo-relative path.
 * @return {string} File contents.
 */
function read(path) {
  return readFileSync(resolve(REPO_ROOT, path), "utf8");
}

test("every climb-drop surface still makes the promise the sender keeps",
  () => {
    for (const surface of CLIMB_DROP_COPY_SURFACES) {
      const source = read(surface.file);
      for (const copy of surface.strings) {
        assert.ok(
          source.includes(copy),
          `${surface.file} no longer contains "${copy}" - if the copy moved, ` +
          "move this contract with it rather than deleting the assertion"
        );
      }
    }
  });

test("nothing promises notice before a climb opens", () => {
  for (const path of PROMISE_BEARING_FILES) {
    const source = read(path).toLowerCase();
    for (const phrase of ADVANCE_NOTICE_PHRASES) {
      assert.ok(
        !source.includes(phrase),
        `${path} promises advance notice ("${phrase}"). The hosted catalogue ` +
        "has no unlock timestamp, so no server-side sender can keep that"
      );
    }
  }
});

test("the sender that keeps the promise is deployed", () => {
  const index = read("functions/src/index.ts");

  assert.match(
    index,
    /export \{announceClimbDrops\} from "\.\/climbDropNotifications";/,
    "announceClimbDrops must stay exported or no climb drop is announced"
  );
});

test("the sender sends at the open rather than on a delay", () => {
  const source = read("functions/src/climbDropNotifications.ts");

  assert.match(source, /schedule: "every 5 minutes"/);
  assert.match(source, /releaseState === "available"/);
});
