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

test("the previous best is read directly only where the board collapses repeat finishers", () => {
  const repository = read(
    "AscendApp/Shared/Repositories/Firebase/" +
      "FirestoreLiveReplayLeaderboardRepository.swift",
  );

  // One gate, reading the client's single existing allowlist - not a second
  // list of context types, and not an inverted denylist.
  const gate = repository.match(
    /private func collapsingBoardUserId\([\s\S]*?\n    \}/,
  );
  assert.ok(gate, "the direct read is no longer scoped to a board type");
  assert.ok(
    gate[0].includes("context.type.collapsesRepeatFinishers"),
    "the direct read stopped reading collapsesRepeatFinishers, the client's " +
      "one definition of which boards the server writes a per-climb best on. " +
      "The BEST marker is a per-climb concept; a board without that single " +
      "entry per climber has no one row to read it from.",
  );
  // The gate scopes the marker's own read and nothing else. Settled by the
  // captain on 2026-09-02: every board type races one row per climber, so a
  // live-race row belonging to the signed-in climber is drawn as theirs
  // everywhere - `parseRow` takes the plain signed-in uid on every board.
  const gatedCallSites = [
    ...repository.matchAll(/collapsingBoardUserId\(context: context\)/g),
  ];
  assert.equal(
    gatedCallSites.length,
    2,
    "the collapsesRepeatFinishers gate reaches past the previous-best read " +
      "it scopes",
  );
});

test("the rank and the field size drop the previous best at the fetch, not off the page", () => {
  const models = read(
    "AscendApp/Shared/Services/LiveReplayLeaderboard/" +
      "LiveReplayLeaderboardModels.swift",
  );
  const repository = read(
    "AscendApp/Shared/Repositories/Firebase/" +
      "FirestoreLiveReplayLeaderboardRepository.swift",
  );

  // Subtracting rows the window happens to hold made the rank a function of
  // pagination, and made it disagree with the rank the drift check compares it
  // against - which refetched the whole window on every tick.
  assert.ok(
    !models.includes("ownRowsCountedAhead"),
    "the rank is adjusted again by counting the climber's own rows inside " +
      "the fetched window",
  );
  assert.ok(
    repository.includes("ownGhostAhead") &&
      repository.includes("joiningClimber"),
    "the fetch no longer withdraws the climber's own completion from the " +
      "server's own ahead count and live-race count",
  );

  // Read by owner, so a previous best further away than the page still has a
  // position for the marker.
  assert.ok(
    repository.includes("func fetchOwnPreviousCompletionRow"),
    "the climber's own entry is no longer read directly, so the BEST marker " +
      "blinks out whenever the window scrolls past it",
  );
  assert.ok(
    models.includes("let ownPreviousCompletionRow: LiveReplayLeaderboardRow?"),
    "the window no longer carries the directly-read previous best",
  );
});

test("the First Ascent claim is resolved from a permanent fact", () => {
  const hero = read("AscendApp/Features/Climbs/Models/LiveClimbSummaryRankHero.swift");
  const history = read(
    "AscendApp/Features/Climbs/Models/PersonalClimbCompletionHistory.swift",
  );

  // "This is my only climb here" may withhold a placing, and may never grant a
  // claim: it stops being true the day the climber returns to the tower, and
  // the gold flag is permanent.
  for (const use of hero.match(/[^\s(]*isFirstCompletionHere/g) ?? []) {
    assert.ok(
      use.startsWith("!"),
      "the hero reads isFirstCompletionHere as a positive test again. It may " +
        "only ever withhold.",
    );
  }
  assert.equal(
    [...hero.matchAll(/return \.firstAscent/g)].length,
    1,
    "the First Ascent state is produced from more than one branch",
  );
  assert.ok(
    /if claimsFirstAscent \{\s*\n\s*return \.firstAscent/.test(hero),
    "the First Ascent state is no longer taken from the caller's claim",
  );
  assert.ok(
    /isEarliestCompletionHere && globalCompletionOrder == 1/.test(history),
    "the claim is no longer built from both permanent signals demanding " +
      "positive evidence. A finisher order this device was never told must " +
      "withhold the claim, never default into granting it.",
  );
  assert.ok(
    !/globalCompletionOrder \?\?/.test(history),
    "the finisher order defaults to a value again, which grants the claim on " +
      "a device that was never told one",
  );
  assert.ok(
    history.includes("enum DurationEvidence"),
    "the history no longer distinguishes a complete record of the climber's " +
      "runs on a tower from a collapsed stand-in for it, which is what let " +
      "both the gold card and a flattering ordinal assert on evidence that " +
      "could not carry them.",
  );
});

test("a field of one never renders leaderboard wording", () => {
  const hero = read("AscendApp/Features/Climbs/Models/LiveClimbSummaryRankHero.swift");

  // CHECK LEADERBOARD LATER is what the sync-phase fallback returns once a
  // lookup has settled, and it sent a climber alone on a tower to a leaderboard
  // holding only them. The settled field-of-one case returns before it.
  assert.ok(
    /if let standing, isClimbContext, countsAFieldOfOne\(standing\),\s*\n\s*!sync\.rankResolution\.isPending \{\s*\n\s*return soloUnverifiedDetail/.test(
      hero,
    ),
    "a settled field of one can reach the sync-phase copy again",
  );

  // A lookup still running is the same wait every other card names, so it
  // reaches the one existing line rather than a second string invented for it.
  assert.ok(
    !hero.includes("soloResolvingDetail"),
    "a second loading string for the solo card is back. The phase fallback " +
      "already says LOOKING FOR YOUR RANK for exactly this moment.",
  );
  assert.equal(
    [...hero.matchAll(/"LOOKING FOR YOUR RANK"/g)].length,
    1,
    "the loading copy is stated in more than one place",
  );

  const copy = hero.match(/static let soloUnverifiedDetail = "([^"]+)"/);
  assert.ok(copy, "soloUnverifiedDetail is gone");
  assert.equal(copy[1], "NOBODY ELSE HAD FINISHED");
  assert.ok(
    !/rank|leaderboard/i.test(copy[1]),
    "soloUnverifiedDetail names a rank or a leaderboard, and a field of one " +
      "has neither",
  );
});

test("a placing is only ever made from evidence that can support it", () => {
  const placing = read("AscendApp/Features/Climbs/Models/PersonalClimbPlacing.swift");

  // Zero comparative evidence decides neither end, so asserting last there is
  // the flattering claim's mirror image - a genuine personal best announced as
  // last of N. It withholds instead, the way the First Ascent claim does.
  assert.ok(
    /case \.partial:\s*\n\s*guard let fastestOnHand = others\.min\(\) else \{ return nil \}/.test(
      placing,
    ),
    "a partial history with no duration on hand emits an ordinal again",
  );
});

test("the climber's own cached row is scoped to them and dropped with the session", () => {
  const repository = read(
    "AscendApp/Shared/Repositories/Firebase/" +
      "FirestoreLiveReplayLeaderboardRepository.swift",
  );
  const auth = read(
    "AscendApp/Features/Authentication/AuthenticationViewModel.swift",
  );

  // Per-user data on a process-wide singleton needs both: the uid in the key so
  // the next account cannot read it, and a teardown because a store wipe never
  // reaches a singleton.
  assert.ok(
    /let key = "\\\(currentUserId\)\|\\\(context\.contextKey\)\|/.test(repository),
    "the own-row cache key no longer names the climber it belongs to",
  );
  assert.ok(
    repository.includes("func clearAccountScopedCaches()"),
    "the repository lost its account-scoped teardown",
  );
  assert.ok(
    auth.includes(
      "FirestoreLiveReplayLeaderboardRepository.shared.clearAccountScopedCaches()",
    ),
    "nothing clears the climber's cached row when their session ends",
  );
});
