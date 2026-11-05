/**
 * The hosted unlock catalogue always has an event for the next 45 days.
 *
 * Onboarding's screen 11 and the Home event card read the monthly event from
 * `web/public/unlocks/catalog.json`. A month with no event in the file shows
 * the neutral version, so nothing goes stale - but somebody still has to add
 * each month's event, and gear art for a new shape has to ship in an app build
 * before the event that uses it opens. This test is the reminder: it goes red
 * while the file has a gap in the next 45 days, which is more than a release
 * cycle ahead, so an empty month is caught long before it opens.
 *
 * It also holds the file honest about itself: dates in order, no overlaps, and
 * every item earned in a real event.
 */

import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const CATALOG_PATH = "web/public/unlocks/catalog.json";
const BUNDLED_PATH = "AscendApp/Features/Athlete/Resources/unlock-catalog.json";

/** How many days ahead the schedule has to be covered. */
export const SCHEDULE_HORIZON_DAYS = 45;
const DAY_MS = 24 * 60 * 60 * 1000;

function readText(path) {
  return readFileSync(resolve(REPO_ROOT, path), "utf8");
}

/** A `YYYY-MM-DD` day as the UTC midnight it names. */
export function dayToMillis(day) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/u.exec(day);
  assert.ok(match, `Not a YYYY-MM-DD day: ${day}`);
  return Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
}

/**
 * The first day from `today` through the horizon that no event covers, or
 * null when the whole stretch is covered. An event covers `startsOn` up to,
 * and not including, `endsBefore`.
 */
export function firstUncoveredDay(events, todayMillis, horizonDays = SCHEDULE_HORIZON_DAYS) {
  const windows = events.map((event) => [dayToMillis(event.startsOn), dayToMillis(event.endsBefore)]);
  for (let offset = 0; offset <= horizonDays; offset += 1) {
    const day = todayMillis + offset * DAY_MS;
    if (!windows.some(([start, end]) => day >= start && day < end)) {
      return new Date(day).toISOString().slice(0, 10);
    }
  }
  return null;
}

function utcToday(now = new Date()) {
  return Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
}

const catalog = JSON.parse(readText(CATALOG_PATH));

test("the hosted catalogue has an event covering the next 45 days", () => {
  const gap = firstUncoveredDay(catalog.events, utcToday());
  assert.equal(
    gap,
    null,
    `No event in ${CATALOG_PATH} covers ${gap}. Add the next month's event ` +
      "(and ship its gear art in an app build first) so onboarding and Home " +
      "never fall back to the neutral screen by accident."
  );
});

test("the gap finder reports the first uncovered day and nothing else", () => {
  const events = [
    {startsOn: "2026-11-01", endsBefore: "2026-12-01"},
    {startsOn: "2026-12-01", endsBefore: "2027-01-01"},
  ];
  const nov4 = dayToMillis("2026-11-04");

  assert.equal(firstUncoveredDay(events, nov4, 45), null);
  assert.equal(firstUncoveredDay(events, nov4, 60), "2027-01-01");
  assert.equal(firstUncoveredDay(events, dayToMillis("2027-01-05"), 45), "2027-01-05");
  assert.equal(firstUncoveredDay([], nov4, 45), "2026-11-04");
});

test("events run in order, never overlap and never end before they start", () => {
  const ordered = [...catalog.events].sort((a, b) => dayToMillis(a.startsOn) - dayToMillis(b.startsOn));
  ordered.forEach((event, index) => {
    assert.ok(dayToMillis(event.startsOn) < dayToMillis(event.endsBefore), `${event.id} ends before it starts`);
    const next = ordered[index + 1];
    if (next) {
      assert.ok(
        dayToMillis(event.endsBefore) <= dayToMillis(next.startsOn),
        `${event.id} overlaps ${next.id}`
      );
    }
  });
  assert.equal(new Set(catalog.events.map((event) => event.id)).size, catalog.events.length, "duplicate event id");
});

test("every item is earned in a real event and every showcase id is one of its items", () => {
  const eventIds = new Set(catalog.events.map((event) => event.id));
  for (const item of catalog.items) {
    assert.ok(eventIds.has(item.earn.event), `${item.id} is earned in unknown event ${item.earn.event}`);
  }
  for (const event of catalog.events) {
    const own = new Set(catalog.items.filter((item) => item.earn.event === event.id).map((item) => item.id));
    assert.ok(own.size >= 3, `${event.id} has fewer than three items to show`);
    for (const id of event.showcase ?? []) {
      assert.ok(own.has(id), `${event.id} shows ${id}, which it does not award`);
    }
  }
});

test("the bundled catalogue is the hosted one, byte for byte", () => {
  assert.equal(readText(BUNDLED_PATH), readText(CATALOG_PATH));
});
