/**
 * How many climbers each city has, for the signed-out onboarding.
 *
 * Onboarding's "Claim your city" screen runs before sign-in, so it cannot read
 * the leaderboard (`hasPaidAppAccess()`) and must not be given the boards'
 * rows. It reads one small document per city instead:
 * `public_city_climber_counts/{key}` holding a count and the city's own name,
 * nothing about any climber.
 *
 * The count is derived here from the server-owned `leaderboard_stats` rows -
 * the all-time row of every real climber who has a city - never from anything
 * a client wrote, for the same reason `leaderboard_stats` itself is
 * server-write-only (issue #307): a number a screen advertises is a number the
 * server must derive. A climber with no climb has no stats row, so the count
 * is climbers who have climbed, which is what "n climbers in Chicago so far"
 * says. Synthetic (seeded) rows never count.
 *
 * There is no Remote Config switch in front of this write on purpose: a Cloud
 * Function is redeployable, so the premise a kill switch exists for - an iOS
 * binary that cannot be rolled back - does not hold here
 * (docs/remote-config-kill-switches.md).
 */

import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

export const PUBLIC_CITY_CLIMBER_COUNTS_COLLECTION =
  "public_city_climber_counts";
export const PUBLIC_CITY_CLIMBER_COUNTS_SCHEMA_VERSION = 1;
/**
 * The document that says a run has happened. A city with no climber has no
 * document, so "no document" alone cannot tell "nobody here" from "this has
 * never run"; the app reads this one beside the city's and treats a missing
 * summary as an answer it does not have, never as zero.
 */
export const PUBLIC_CITY_CLIMBER_COUNTS_SUMMARY_ID = "_summary";

const LEADERBOARD_STATS_COLLECTION = "leaderboard_stats";
const ALL_TIME_FRAME = "all_time";
/** Writes per commit, under Firestore's 500-operation batch limit. */
const BATCH_SIZE = 400;

/** The fields of one climber's all-time stats row that name a city. */
export interface CityStatsRow {
  userId: string;
  city: unknown;
  region: unknown;
  countryCode: unknown;
}

/** One city's tally. */
export interface CityTally {
  key: string;
  city: string;
  region: string | null;
  countryCode: string;
  climbers: number;
}

/**
 * The text a key is made of: trimmed, accents folded, lower case, every run of
 * other characters one hyphen.
 * @param {string} value Raw text.
 * @return {string} The normalized text.
 */
function normalizeKeyText(value: string): string {
  return value
    .normalize("NFD")
    .replace(/\p{M}+/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

/**
 * The document id for a city. `CityClimberCountKey.swift` computes the same
 * one; `SharedTestVectors/city-count-key-vector.json` holds the two together.
 * @param {string} city The city's name.
 * @param {string | null} region Its region, if it has one.
 * @param {string} countryCode ISO 3166-1 alpha-2.
 * @return {string | null} The key, or null when the city names nothing.
 */
export function cityCountKey(
  city: string,
  region: string | null,
  countryCode: string
): string | null {
  const country = countryCode.trim().toUpperCase();
  const cityPart = normalizeKeyText(city);
  if (!/^[A-Z]{2}$/u.test(country) || cityPart.length === 0) {
    return null;
  }
  const regionPart = region === null ? "" : normalizeKeyText(region);
  return `${country}__${regionPart.length > 0 ? regionPart : "none"}__${
    cityPart}`;
}

/**
 * Text read off a stats row: a trimmed non-empty string of reasonable length.
 * @param {unknown} value Raw field.
 * @return {string | null} The text.
 */
function profileText(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 && trimmed.length <= 120 ? trimmed : null;
}

/**
 * Tallies climbers per city, counting each climber once.
 * @param {CityStatsRow[]} rows One all-time stats row per climber.
 * @return {CityTally[]} One tally per city, busiest first.
 */
export function tallyCityClimbers(rows: CityStatsRow[]): CityTally[] {
  const seen = new Set<string>();
  const tallies = new Map<string, CityTally>();

  for (const row of rows) {
    const city = profileText(row.city);
    const region = profileText(row.region);
    const countryCode = typeof row.countryCode === "string" ?
      row.countryCode.trim().toUpperCase() :
      "";
    if (city === null || seen.has(row.userId)) {
      continue;
    }
    const key = cityCountKey(city, region, countryCode);
    if (key === null) {
      continue;
    }
    seen.add(row.userId);

    const existing = tallies.get(key);
    if (existing === undefined) {
      tallies.set(key, {key, city, region, countryCode, climbers: 1});
    } else {
      existing.climbers += 1;
    }
  }

  return [...tallies.values()].sort(
    (a, b) => b.climbers - a.climbers || a.key.localeCompare(b.key)
  );
}

/** The storage a run reads and writes, so it is testable offline. */
export interface CityCountsPort {
  readAllTimeRows(): Promise<CityStatsRow[]>;
  readPublishedKeys(): Promise<string[]>;
  writeCounts(tallies: CityTally[]): Promise<void>;
  writeSummary(summary: CityCountsSummary): Promise<void>;
  deleteCounts(keys: string[]): Promise<void>;
}

export interface CityCountsSummary {
  cities: number;
  climbers: number;
  deleted: number;
}

/**
 * Recomputes every city's count and removes the documents of cities that no
 * longer have a climber, so a stale count is never left advertising a city.
 * @param {CityCountsPort} port Storage.
 * @return {Promise<CityCountsSummary>} What the run did.
 */
export async function refreshCityClimberCounts(
  port: CityCountsPort
): Promise<CityCountsSummary> {
  const tallies = tallyCityClimbers(await port.readAllTimeRows());
  const current = new Set(tallies.map((tally) => tally.key));
  const stale = (await port.readPublishedKeys()).filter(
    (key) => !current.has(key)
  );

  await port.writeCounts(tallies);
  await port.deleteCounts(stale);

  const summary = {
    cities: tallies.length,
    climbers: tallies.reduce((sum, tally) => sum + tally.climbers, 0),
    deleted: stale.length,
  };
  // Last, so a summary is only ever there once the counts it vouches for are.
  await port.writeSummary(summary);
  return summary;
}

/**
 * The Admin SDK port.
 * @return {CityCountsPort} Firestore-backed storage.
 */
export function makeAdminCityCountsPort(): CityCountsPort {
  const db = admin.firestore();
  const counts = db.collection(PUBLIC_CITY_CLIMBER_COUNTS_COLLECTION);

  return {
    async readAllTimeRows() {
      const snapshot = await db
        .collection(LEADERBOARD_STATS_COLLECTION)
        .where("timeFrame", "==", ALL_TIME_FRAME)
        .where("isSynthetic", "==", false)
        .select(
          "userId",
          "location_city",
          "location_region",
          "location_country"
        )
        .get();
      return snapshot.docs.map((document) => {
        const data = document.data();
        return {
          userId: typeof data.userId === "string" ? data.userId : document.id,
          city: data.location_city,
          region: data.location_region,
          countryCode: data.location_country,
        };
      });
    },

    async readPublishedKeys() {
      const snapshot = await counts.select().get();
      return snapshot.docs
        .map((document) => document.id)
        .filter((id) => id !== PUBLIC_CITY_CLIMBER_COUNTS_SUMMARY_ID);
    },

    async writeCounts(tallies) {
      for (let start = 0; start < tallies.length; start += BATCH_SIZE) {
        const batch = db.batch();
        for (const tally of tallies.slice(start, start + BATCH_SIZE)) {
          batch.set(counts.doc(tally.key), {
            schemaVersion: PUBLIC_CITY_CLIMBER_COUNTS_SCHEMA_VERSION,
            city: tally.city,
            region: tally.region,
            countryCode: tally.countryCode,
            climbers: tally.climbers,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
    },

    async writeSummary(summary) {
      // Only that a run happened: the totals stay in the run's log, because
      // this document is readable by anyone and no screen needs them.
      logger.info("publicCityClimberCounts.summary", summary);
      await counts.doc(PUBLIC_CITY_CLIMBER_COUNTS_SUMMARY_ID).set({
        schemaVersion: PUBLIC_CITY_CLIMBER_COUNTS_SCHEMA_VERSION,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    },

    async deleteCounts(keys) {
      for (let start = 0; start < keys.length; start += BATCH_SIZE) {
        const batch = db.batch();
        for (const key of keys.slice(start, start + BATCH_SIZE)) {
          batch.delete(counts.doc(key));
        }
        await batch.commit();
      }
    },
  };
}

/** Hourly: a count that is an hour old is honest for "so far". */
export const publishCityClimberCounts = onSchedule(
  {
    schedule: "17 * * * *",
    timeZone: "Etc/UTC",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    const summary = await refreshCityClimberCounts(makeAdminCityCountsPort());
    logger.info("publicCityClimberCounts.run", summary);
  }
);
