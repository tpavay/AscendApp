import test from "node:test";
import assert from "node:assert/strict";
import {execFileSync} from "node:child_process";
import {mkdtempSync, rmSync, symlinkSync} from "node:fs";
import {tmpdir} from "node:os";
import {dirname, join} from "node:path";
import {fileURLToPath} from "node:url";

import {
  OWNERSHIP_INCLUDING_CLOSED,
  OWNERSHIP_OPEN_ONLY,
  ownershipFor,
  parseArgs,
} from "../backfill-leaderboard-stats.mjs";

const SCRIPT_PATH = join(
  dirname(fileURLToPath(import.meta.url)),
  "../backfill-leaderboard-stats.mjs"
);

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

// Deleting a row a minted achievement points at as its provenance is a harsher
// act than repairing one, and it is not reversible. Consent to the wider reach
// is not consent to that.
test("removing a finalized period's row needs its own consent", () => {
  assert.equal(
    parseArgs(argv("--project", "dev")).allowFinalizedProvenanceLoss,
    false
  );
  assert.equal(
    parseArgs(argv("--project", "dev", "--include-closed-periods"))
      .allowFinalizedProvenanceLoss,
    false,
    "the broader flag must not carry this one along"
  );
  assert.equal(
    parseArgs(argv(
      "--project",
      "dev",
      "--include-closed-periods",
      "--allow-finalized-provenance-loss"
    )).allowFinalizedProvenanceLoss,
    true
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

// An operator tool that exits 0 having done nothing is the worst failure it can
// have. Node leaves argv[1] unresolved through symlinks while the ESM loader
// realpaths the module URL, so a naive entry guard turns any linked invocation
// into a silent no-op.
test("running through a symlinked path still executes and still prints", () => {
  const directory = mkdtempSync(join(tmpdir(), "ascend-backfill-link-"));
  const linked = join(directory, "backfill-link.mjs");
  try {
    symlinkSync(SCRIPT_PATH, linked);
    const output = execFileSync("node", [linked, "--help"], {
      encoding: "utf8",
    });
    assert.match(output, /Usage:/);
    assert.match(output, /--include-closed-periods/);
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
});

// The help is where an operator learns what they cannot undo, so these two
// facts have to be in it rather than only in the report they see afterwards.
test("the help states what a removal cannot be taken back from", () => {
  const output = execFileSync("node", [SCRIPT_PATH, "--help"], {
    encoding: "utf8",
  });

  assert.match(output, /CAN NEVER BE RE-DERIVED/);
  assert.match(output, /--allow-finalized-provenance-loss/);
  assert.match(output, /provenance/);
});
