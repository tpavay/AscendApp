import test from "node:test";
import assert from "node:assert/strict";

import {
  OWNERSHIP_INCLUDING_CLOSED,
  OWNERSHIP_OPEN_ONLY,
  ownershipFor,
  parseArgs,
} from "../backfill-leaderboard-stats.mjs";

function argv(...flags) {
  return ["node", "backfill-leaderboard-stats.mjs", ...flags];
}

// Widening ownership to closed periods puts the rows finalizeLeaderboardAchievements
// reads in reach of a rewrite. It has to be something an operator asked for, never
// something they inherited by running the usual command.
test("closed periods are out of scope unless the operator asks for them", () => {
  assert.equal(
    parseArgs(argv("--project", "dev")).includeClosedPeriods,
    false
  );
  assert.equal(
    parseArgs(argv("--project", "dev", "--dry-run", "--verbose"))
      .includeClosedPeriods,
    false
  );
  assert.equal(
    parseArgs(argv("--project", "dev", "--include-closed-periods"))
      .includeClosedPeriods,
    true
  );
});

test("the flag is what selects the wider ownership the derivation honours",
  () => {
    assert.equal(
      ownershipFor(parseArgs(argv("--project", "dev"))),
      OWNERSHIP_OPEN_ONLY
    );
    assert.equal(
      ownershipFor(parseArgs(argv("--project", "dev", "--include-closed-periods"))),
      OWNERSHIP_INCLUDING_CLOSED
    );
  });

test("an unrecognised flag stops the run rather than being ignored", () => {
  assert.throws(
    () => parseArgs(argv("--project", "dev", "--include-closed-period")),
    /Unknown argument/
  );
});

test("a project is required, and --help does not need one", () => {
  assert.throws(() => parseArgs(argv("--dry-run")), /--project is required/);
  assert.equal(parseArgs(argv("--help")).help, true);
});
