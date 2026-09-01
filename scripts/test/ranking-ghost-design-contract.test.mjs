/**
 * The ranking-and-ghost design, held against the source.
 *
 * The captain locked this across nine review rounds on 2026-09-01; the decision
 * records live in `data/ascend-climb-ranking-ghost-design/decisions/` in the
 * firstmate home, which is outside this repo, so the shipped source is the only
 * authority CI can read.
 *
 * Three of the locked items are *absences*, and an absence has no unit test to
 * fail. They are pinned here instead:
 *
 * 1. **No comparison numbers around the previous best.** Round 6 deleted the
 *    "67 steps to catch yourself" sub-line, the "steps ahead of your best" line,
 *    and the step count and time on the marker itself. His words: "if we just
 *    have the best, I don't think we need to compare. I think not showing the
 *    number is fine for now."
 * 2. **No `of 1 climber` hero.** The finish card may never state a leaderboard
 *    placing over a field of one - that ordinal could not fall, which is how a
 *    slower repeat came to be congratulated.
 * 3. **The Climb Detail board keeps every attempt.** His ruling: "The point of
 *    the Climb Detail Board is to show all the attempts, so I think we still
 *    want the 8/12, 8/19, 8/24." The unique-climbers rule stops at that board,
 *    which counts completions on purpose.
 */

import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

const read = (relativePath) =>
  readFileSync(resolve(REPO_ROOT, relativePath), "utf8");

/**
 * The same source with its Swift comments removed.
 *
 * The deleted copy is named in the doc comments on purpose - that is where the
 * reasoning for its absence lives - so the scan reads what the app renders, not
 * what it explains.
 */
const readRenderedSource = (relativePath) =>
  read(relativePath)
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .filter((line) => !line.trimStart().startsWith("//"))
    .join("\n");

/** Every surface that draws or feeds the previous-best marker. */
const MARKER_SURFACES = [
  "AscendApp/Shared/Components/ReplayLeaderboard/LiveReplayPreviousBestMarker.swift",
  "AscendApp/Shared/Components/ReplayLeaderboard/LiveReplayLeaderboardPanel.swift",
  "AscendApp/Features/Climbs/Views/LiveClimbJustMeView.swift",
  "AscendApp/Features/Climbs/ViewModels/LiveClimbSessionViewModel.swift",
];

/**
 * Copy that would put a comparison number back beside the marker. Matched
 * case-insensitively against the rendered strings in those files.
 */
const DELETED_COMPARISON_COPY = [
  "steps to catch",
  "catch yourself",
  "steps ahead of",
  "ahead of your best",
  "steps behind you",
  "behind your best",
  "off your best",
  "your best of",
];

test("the previous-best marker carries no comparison number", () => {
  for (const file of MARKER_SURFACES) {
    const source = readRenderedSource(file).toLowerCase();
    for (const phrase of DELETED_COMPARISON_COPY) {
      assert.ok(
        !source.includes(phrase),
        `${file} re-introduces the deleted comparison copy "${phrase}". ` +
          "The row shows the climber's steps, the marker shows where their " +
          "best was, and the visible gap is the whole message.",
      );
    }
  }
});

test("the marker states a position and never a step count or a time", () => {
  const marker = read(MARKER_SURFACES[0]);

  // The only text the marker renders is the word itself.
  const renderedText = [...marker.matchAll(/Text\(([^\n]*)\)$/gm)].map(
    (match) => match[1].trim(),
  );
  assert.deepEqual(
    renderedText,
    ["String(letter.element)"],
    "the marker renders text other than its own vertical BEST label",
  );
  assert.ok(
    marker.includes('"BEST"'),
    "the marker no longer labels itself BEST",
  );
});

test("the marker is a single line, not a two-sided box", () => {
  const marker = read(MARKER_SURFACES[0]);
  const rectangles = [...marker.matchAll(/Rectangle\(\)/g)].length;

  assert.equal(
    rectangles,
    1,
    "the marker draws more than one rule. It is one vertical line to the " +
      "LEFT of the word, so the progress fill passes one edge cleanly " +
      "instead of straddling a box through a half-passed state.",
  );
});

test("the marker's line never fades and never restyles once passed", () => {
  const marker = read(MARKER_SURFACES[0]);

  assert.ok(
    /verticalLabel\s*\n\s*\.opacity\(/.test(marker),
    "the fade is no longer applied to the label",
  );
  assert.ok(
    !/Rectangle\(\)\s*\n\s*\.fill\(lineColor\)\s*\n\s*\.opacity\(/.test(marker),
    "the line itself fades. It is the thing being raced: only the word fades.",
  );
});

test("the Just Me rail draws the same marker turned on its side", () => {
  const rail = read("AscendApp/Features/Climbs/Views/LiveClimbJustMeView.swift");

  const marker = rail.match(
    /private func previousBestMarker\(centerX: CGFloat, height: CGFloat\) -> some View \{[\s\S]*?\n    \}/,
  );
  assert.ok(marker, "the rail no longer draws a previous-best marker");
  const body = marker[0];

  // One horizontal line, no step count, no delta.
  assert.equal(
    [...body.matchAll(/Rectangle\(\)/g)].length,
    1,
    "the rail marker is more than a single line",
  );
  assert.equal(
    [...body.matchAll(/Text\(/g)].length,
    1,
    "the rail marker renders a second string. It carries the word BEST and " +
      "nothing else - no step count, no delta, no comparison sentence.",
  );
  assert.ok(body.includes('Text("BEST")'), "the rail marker lost its label");

  // The word sits ABOVE and the line BELOW it, because the climber rises and
  // the fill comes up to meet the line from underneath.
  assert.ok(
    /Text\("BEST"\)[\s\S]*?\.position\(x: centerX, y: markerY - 10\)[\s\S]*?Rectangle\(\)[\s\S]*?\.position\(x: centerX, y: markerY\)/.test(
      body,
    ),
    "the rail's line is no longer on the bottom side of the word",
  );

  // Narrowed to the track, matching the HALF marker the rail already ships.
  assert.ok(
    body.includes(".frame(width: 14, height: 2)"),
    "the rail marker no longer matches the existing HALF marker's width",
  );
  assert.ok(
    rail.includes('Text("HALF")') && rail.includes(".frame(width: 14, height: 2)"),
    "the HALF marker this width is matched against has changed",
  );

  // The rank card stays: it now reads 1st rather than #2, because the
  // climber's own best is no longer counted as a rival (JM-G, JM-H not taken).
  assert.ok(
    rail.includes('label: "CURRENT RANK"'),
    "the Just Me tab dropped CURRENT RANK. JM-H was not taken.",
  );
});

test("the finish-card hero never states a placing over a field of one", () => {
  const hero = read("AscendApp/Features/Climbs/Models/LiveClimbSummaryRankHero.swift");

  assert.ok(
    hero.includes("countsAFieldOfOne"),
    "the hero no longer recognises a field of one as its own case",
  );
  assert.ok(
    /guard isClimbContext, countsAFieldOfOne\(standing\) else \{\s*\n\s*return \.rank\(standing\.rank\)/.test(
      hero,
    ),
    "a climb standing over a field of one can reach the rank branch again",
  );
  assert.ok(
    hero.includes("case personalPlacing(PersonalClimbPlacing)"),
    "the hero has lost the personal-placing state that replaced the rank",
  );
});

test("the finish-card ordinal is the accent and the label beneath it is not", () => {
  const view = read("AscendApp/Features/Climbs/Views/LiveClimbSummaryRankHeroView.swift");

  // One ordinal builder, one accent, used by both the leaderboard rank and the
  // personal placing - so no colour split can creep back between them.
  assert.ok(
    /private func ordinal\(_ value: Int\) -> some View \{[\s\S]*?\.foregroundStyle\(\.accent\)/.test(
      view,
    ),
    "the ordinal is no longer drawn in the accent",
  );
  assert.ok(
    view.includes("case .neutral:\n            return .white.opacity(0.66)"),
    "the label beneath the ordinal is no longer the neutral secondary white",
  );
  assert.ok(
    view.includes(".ascendMedalGold"),
    "the First Ascent claim is no longer gold",
  );
});

test("the First Ascent card is the flag and the claim, and nothing else", () => {
  const hero = read("AscendApp/Features/Climbs/Models/LiveClimbSummaryRankHero.swift");
  const view = read("AscendApp/Features/Climbs/Views/LiveClimbSummaryRankHeroView.swift");

  assert.ok(
    hero.includes('static let firstAscentDetail = "FIRST ASCENT CLAIMED"'),
    "the First Ascent claim copy changed",
  );
  assert.ok(
    view.includes('Image("FirstAscentBadgeDetailed")'),
    "the First Ascent hero no longer draws the gold flag",
  );

  // No sentence, no date, no dare, no rank: the claim is the only string the
  // First Ascent state produces.
  const firstAscentDetail = hero.match(
    /case \.firstAscent:\s*\n\s*return ([^\n]+)/,
  );
  assert.ok(firstAscentDetail, "the First Ascent detail branch is gone");
  assert.equal(firstAscentDetail[1].trim(), "firstAscentDetail");
});

test("the Climb Detail board still counts every completion", () => {
  const climbDetail = read("AscendApp/Features/Climbs/Views/ClimbDetailView.swift");

  assert.ok(
    /population: \.completions/.test(climbDetail),
    "the Climb Detail board stopped counting completions. The captain ruled " +
      "that board shows all the attempts; the unique-climbers rule governs " +
      "the live race panel and the finish-card denominator and stops there.",
  );
});
