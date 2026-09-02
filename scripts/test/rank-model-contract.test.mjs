/**
 * The rank model is stated once, and only once.
 *
 * Ascend counts different populations on different screens on purpose. That is
 * correct. What kept producing questions was the rules being recorded as a list
 * of past incidents spread across two skills, so a worker touching one surface
 * read the incidents nearest to it and never saw the neighbouring surface's
 * rule - and every question landed on a seam between two surfaces.
 *
 * The fix is one plain statement in `ascend-leaderboards`, with pointers from
 * everywhere else. This test holds that shape: the five statements are present,
 * the seams are stated, nobody keeps a second copy, the superseded
 * attempt-counting form stays deleted, and each statement's named anchor still
 * exists so deleting the test behind a statement fails here rather than
 * shipping.
 */

import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

const MODEL_SKILL = ".claude/skills/ascend-leaderboards/SKILL.md";
const MODEL_HEADING = "## The rank model";

/** Skills and guides that reference the model instead of restating it. */
const POINTER_FILES = [
  ".claude/skills/ascend-live-climbs/SKILL.md",
  ".claude/skills/ascend-share-composer/SKILL.md",
  "CLAUDE.md",
];

/**
 * A file this contract names has moved or gone. That is a failure, never a
 * skip - but it fails with the contract's own sentence rather than an ENOENT
 * stack, so whoever renamed it reads what the path was holding up.
 *
 * @param {string} relativePath Repo-relative path.
 * @param {string} [protecting] What the contract reads this file for.
 * @return {string} File contents.
 */
function read(relativePath, protecting) {
  try {
    return readFileSync(resolve(REPO_ROOT, relativePath), "utf8");
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
    assert.fail(
      `${relativePath} no longer exists, and the rank model names it` +
        `${protecting ? ` for ${protecting}` : ""}. ` +
        "Repoint this contract at the file that replaced it rather than dropping the check."
    );
  }
}

/** The `## The rank model` section, up to the next `## ` heading. */
function modelSection() {
  const skill = read(MODEL_SKILL, "the one statement of the rank model");
  const start = skill.indexOf(MODEL_HEADING);
  assert.notEqual(start, -1, `${MODEL_SKILL} must carry a "${MODEL_HEADING}" section`);
  const rest = skill.slice(start + MODEL_HEADING.length);
  const end = rest.indexOf("\n## ");
  return end === -1 ? rest : rest.slice(0, end);
}

/**
 * The five statements, each with the phrases that carry it. A statement whose
 * heading survives while its substance is edited away is the failure mode this
 * guards, so the phrases are the load-bearing half.
 */
const STATEMENTS = [
  {
    heading: "### 1. During a climb",
    phrases: [
      "one row per unique climber",
      "Your row shows your current run",
      "Your previous best is not a row",
      "never counted in the rank or in the field size",
      "never your most recent",
    ],
  },
  {
    heading: "### 2. The summary right after you finish",
    phrases: [
      "where you stood at that moment",
      "that climb's own time",
      "never on your all-time best",
    ],
  },
  {
    heading: "### 3. That same summary, reopened later",
    phrases: [
      "It never re-computes.",
      "the same time and the same number",
    ],
  },
  {
    heading: "### 4. Climb detail",
    phrases: [
      "all of your attempts and everybody else's",
      "`ALL TIMES`, not `LEADERBOARD`",
    ],
  },
  {
    heading: "### 5. Every surface names the population it counted",
    phrases: [
      "the words match the number",
      "`CLIMBERS`",
      "`COMPLETIONS`",
    ],
  },
];

/**
 * The seams are the whole point of writing this down - every question the
 * captain fielded came from one, so none of them may be left to inference.
 */
const SEAMS = [
  "Your row versus your marker.",
  "A rank sentence versus the rows a board draws.",
  "The live number versus the frozen number.",
  "The summary versus climb detail.",
  "Solo versus a real field.",
];

/**
 * Phrases asserting the superseded form, in which a Just Climb or plain routine
 * board ranked a climber against attempts. The captain settled unique climbers
 * on both halves on 2026-09-02: 41 finishes from 16 climbers with 5 climbers
 * ahead is 6th of 16, never 13th of anything.
 */
const SUPERSEDED_ATTEMPT_COUNTING = [
  "both halves count attempts",
  "cannot claim to be counting climbers",
  "the denominator is the published attempt count",
];

/** Statement, and the test that already holds it. */
const STATEMENT_ANCHORS = [
  {
    statement: 1,
    file: "AscendAppTests/LiveReplayFieldPopulationTests.swift",
    symbol: "onlyPerClimbAndPerTemplateContextsCollapseRepeats",
  },
  {
    statement: 2,
    file: "functions/test/liveReplayLeaderboard.test.ts",
    symbol: "counts a repeat rival once on a board that races climbers",
  },
  {
    statement: 2,
    file: "functions/test/liveReplayLeaderboard.test.ts",
    symbol: "never seats a climber behind their own earlier best",
  },
  {
    statement: 3,
    file: "AscendAppTests/CompletedClimbRankFreezeTests.swift",
    symbol: "aLaterServerReadNeverMovesAnAlreadyFrozenRank",
  },
  {
    statement: 3,
    file: "AscendAppTests/SavedClimbShareRankTests.swift",
    symbol: "aStoredFrozenStandingReachesTheSavedClimbShareCardWithoutARequest",
  },
  {
    statement: 4,
    file: "AscendAppTests/LiveReplayFieldPopulationRenderEvidenceTests.swift",
    symbol: "climbDetailsThirdTabReadsAllTimesAndCountsCompletions",
  },
  {
    statement: 5,
    file: "AscendAppTests/LiveReplayFieldPopulationTests.swift",
    symbol: "fieldSizeLabelNamesThePopulationAndGroupsTheNumber",
  },
];

test("the model states all five lines", () => {
  const section = modelSection();

  for (const {heading, phrases} of STATEMENTS) {
    assert.ok(
      section.includes(heading),
      `${MODEL_SKILL} lost the statement "${heading}"`
    );
    for (const phrase of phrases) {
      assert.ok(
        section.includes(phrase),
        `${heading} no longer says "${phrase}"`
      );
    }
  }
});

test("the model states every seam directly", () => {
  const section = modelSection();

  for (const seam of SEAMS) {
    assert.ok(
      section.includes(seam),
      `${MODEL_SKILL} lost the seam "${seam}" - a seam left to inference is where every question came from`
    );
  }
});

test("the rank sentence counts unique climbers on both halves", () => {
  const section = modelSection();

  assert.ok(
    section.includes("unique climbers on both halves"),
    "the row-versus-rank seam must state that both halves count unique climbers"
  );
  assert.ok(
    section.includes("`6TH OF 16`"),
    "the worked example the captain gave (6TH OF 16) must stay - it is what makes the rule unambiguous"
  );
  for (const wrong of ["`13TH OF 16`", "`13TH OF 41`"]) {
    assert.ok(
      section.includes(wrong),
      `the model must name ${wrong} as the answer it is not`
    );
  }
});

test("a statement the code does not yet keep says so", () => {
  const section = modelSection();

  assert.ok(
    section.includes("Decided and being built, not yet shipping."),
    "the row-versus-rank seam must mark itself as decided rather than shipping, or a reader takes 6TH OF 16 for current behaviour"
  );
  assert.ok(
    section.includes("functions/src/liveReplayLeaderboard.ts:1562"),
    "the seam must name the call site that still counts attempts"
  );
  assert.ok(
    section.includes("`ascend-live-leaderboard-second-attempt`"),
    "the seam must name the lane implementing the settled rule"
  );
  assert.ok(
    section.includes("The unfiltered all-attempts read itself has no anchor"),
    "statement 4's untested half must stay disclosed, the way the BEST marker's is"
  );
});

test("no skill or guide asserts the superseded attempt-counting form", () => {
  for (const file of [MODEL_SKILL, ...POINTER_FILES]) {
    const contents = read(file, "a pointer at the rank model");
    for (const phrase of SUPERSEDED_ATTEMPT_COUNTING) {
      assert.ok(
        !contents.includes(phrase),
        `${file} still asserts the superseded attempt-counting rank: "${phrase}"`
      );
    }
  }
});

test("every other surface points at the model instead of restating it", () => {
  for (const file of POINTER_FILES) {
    const contents = read(file, "a pointer at the rank model");
    assert.ok(
      contents.includes("The rank model"),
      `${file} must point at The rank model`
    );
    assert.ok(
      contents.includes("ascend-leaderboards"),
      `${file} must name the skill that owns The rank model`
    );
    for (const {heading} of STATEMENTS) {
      assert.ok(
        !contents.includes(heading),
        `${file} carries a second copy of "${heading}" - the pointed-to text is the only statement`
      );
    }
  }
});

test("the model is loadable from every context its tripwire fires in", () => {
  // A skill with `paths:` globs stays out of the skill listing until a matching
  // file is touched. The tripwire fires while editing a Cloud Function, a share
  // card and a climb view, so the skill that answers it may not be conditional.
  const frontMatter = read(MODEL_SKILL, "the tripwire's unconditional skill").split("---")[1] ?? "";
  assert.ok(
    !/^paths:/m.test(frontMatter),
    `${MODEL_SKILL} is named by a tripwire, so it must not declare \`paths:\``
  );

  const guide = read("CLAUDE.md", "the rank-model tripwire");
  const tripwire = guide
    .split("\n")
    .find((line) => line.includes("A rank counts people"));
  assert.ok(tripwire, "CLAUDE.md must carry the rank-model tripwire");
  assert.ok(
    tripwire.includes("`ascend-leaderboards`"),
    "the tripwire must route to the skill that owns the model"
  );
  assert.ok(
    tripwire.includes("Fires while"),
    "the tripwire must name the contexts it fires from"
  );
});

test("climb detail is titled ALL TIMES in the shipping view", () => {
  const view = read(
    "AscendApp/Features/Climbs/Views/ClimbDetailView.swift",
    "statement 4's ALL TIMES title"
  );

  assert.ok(
    view.includes('"ALL TIMES"'),
    "Climb Detail's third page must be titled ALL TIMES"
  );
  assert.ok(
    !/detailPageTitles[\s\S]{0,200}"LEADERBOARD"/.test(view),
    "Climb Detail's page titles must not reuse LEADERBOARD, which the live race panel keeps"
  );
});

test("a field size is never carried without the population it counted", () => {
  const context = read(
    "AscendApp/Shared/Services/LiveReplayLeaderboard/LiveReplayLeaderboardContext.swift",
    "statement 5's field size carrying its population"
  );

  assert.ok(
    /struct LiveReplayFieldSize[\s\S]{0,400}let population: LiveReplayFieldPopulation/.test(context),
    "LiveReplayFieldSize must carry its population beside the count"
  );
  assert.ok(
    /enum LiveReplayFieldPopulation[\s\S]{0,600}"CLIMBER[\s\S]{0,200}"COMPLETION/.test(context),
    "the field-size noun must be derived from the population, never written at a call site"
  );
});

test("each statement's anchor test still exists", () => {
  const section = modelSection();

  for (const {statement, file, symbol} of STATEMENT_ANCHORS) {
    assert.ok(
      read(file, `statement ${statement}'s anchor`).includes(symbol),
      `statement ${statement} names ${file} "${symbol}", which no longer exists`
    );
    assert.ok(
      section.includes(symbol),
      `${MODEL_SKILL} must name its anchor "${symbol}" for statement ${statement}`
    );
  }
});
