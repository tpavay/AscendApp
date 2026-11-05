import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {join} from "node:path";
import {
  CityCountsPort,
  CityCountsSummary,
  CityStatsRow,
  CityTally,
  cityCountKey,
  refreshCityClimberCounts,
  tallyCityClimbers,
} from "../src/publicCityClimberCounts.js";

interface KeyVector {
  cases: {
    city: string;
    region: string | null;
    countryCode: string;
    key: string;
  }[];
}

const vector = JSON.parse(readFileSync(
  join(__dirname, "../../../SharedTestVectors/city-count-key-vector.json"),
  "utf8"
)) as KeyVector;

function row(
  userId: string,
  city: unknown,
  region: unknown = "IL",
  countryCode: unknown = "US"
): CityStatsRow {
  return {userId, city, region, countryCode};
}

test("every shared key vector case produces the key Swift expects", () => {
  for (const entry of vector.cases) {
    assert.equal(
      cityCountKey(entry.city, entry.region, entry.countryCode),
      entry.key,
      `${entry.city}, ${entry.region}, ${entry.countryCode}`
    );
  }
});

test("a city with no letters or a bad country has no key", () => {
  assert.equal(cityCountKey("...", "IL", "US"), null);
  assert.equal(cityCountKey("Chicago", "IL", "USA"), null);
  assert.equal(cityCountKey("Chicago", "IL", ""), null);
});

test("climbers are counted per city, once each, busiest first", () => {
  const tallies = tallyCityClimbers([
    row("a", "Chicago"),
    row("b", "chicago "),
    row("a", "Chicago"),
    row("c", "Springfield", "MO"),
    row("d", "Springfield", "IL"),
    row("e", "Springfield", "IL"),
  ]);

  assert.deepEqual(
    tallies.map((tally) => [tally.key, tally.climbers]),
    [
      ["US__il__chicago", 2],
      ["US__il__springfield", 2],
      ["US__mo__springfield", 1],
    ]
  );
  assert.equal(tallies[0]?.city, "Chicago");
});

test("rows with no usable city are not counted", () => {
  assert.deepEqual(tallyCityClimbers([
    row("a", null),
    row("b", ""),
    row("c", 12),
    row("d", "Chicago", "IL", "usa"),
    row("e", "Chicago", "IL", null),
  ]), []);
});

class FakePort implements CityCountsPort {
  written: CityTally[] = [];
  deleted: string[] = [];
  summary: CityCountsSummary | null = null;
  order: string[] = [];

  constructor(
    private readonly rows: CityStatsRow[],
    private readonly published: string[]
  ) {}

  async readAllTimeRows(): Promise<CityStatsRow[]> {
    return this.rows;
  }

  async readPublishedKeys(): Promise<string[]> {
    return this.published;
  }

  async writeCounts(tallies: CityTally[]): Promise<void> {
    this.written = tallies;
    this.order.push("counts");
  }

  async writeSummary(summary: CityCountsSummary): Promise<void> {
    this.summary = summary;
    this.order.push("summary");
  }

  async deleteCounts(keys: string[]): Promise<void> {
    this.deleted = keys;
  }
}

test("a run writes current counts and removes a city nobody climbs in", async () => {
  const port = new FakePort(
    [row("a", "Chicago"), row("b", "Chicago")],
    ["US__il__chicago", "US__tx__austin"]
  );

  const summary = await refreshCityClimberCounts(port);

  assert.deepEqual(summary, {cities: 1, climbers: 2, deleted: 1});
  assert.deepEqual(port.deleted, ["US__tx__austin"]);
  assert.equal(port.written[0]?.climbers, 2);
  assert.deepEqual(port.summary, summary);
});

test("the summary is written last, after the counts it vouches for", async () => {
  const port = new FakePort([row("a", "Chicago")], []);

  await refreshCityClimberCounts(port);

  assert.deepEqual(port.order, ["counts", "summary"]);
});
