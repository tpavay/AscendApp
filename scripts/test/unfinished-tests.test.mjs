/**
 * The in-flight test extraction the silence watchdog prints when it kills a
 * wedged pass. The lines are the exact shapes Swift Testing writes through
 * `xcodebuild` on Xcode 26.3, including the ones simulator logging corrupts by
 * interleaving mid-line, which the extraction must survive rather than parse.
 */

import assert from "node:assert/strict";
import {test} from "node:test";

import {unfinishedTests} from "../ci/unfinished-tests.mjs";

test("tests started with no pass or fail line are listed, in start order", () => {
  const lines = [
    "◇ Test run started.",
    "◇ Suite RankingTests started.",
    "◇ Test aFinishedOne() started.",
    '◇ Test "A display-named test" started.',
    "◇ Test stillRunning() started.",
    '◇ Test "Parameterised over two cases" started.',
    '◇ Test case passing 1 argument rawValue → "x" to "Parameterised over two cases" started.',
    "✔ Test aFinishedOne() passed after 1.204 seconds.",
    '✘ Test "A display-named test" failed after 3.010 seconds with 1 issue.',
    '✔ Test "Parameterised over two cases" with 2 test cases passed after 0.5 seconds.',
    "◇ Test alsoRunning() started.",
  ];

  assert.deepEqual(unfinishedTests(lines), ["stillRunning()", "alsoRunning()"]);
});

test("a log with nothing in flight lists nothing, and the test run line is never a test", () => {
  assert.deepEqual(unfinishedTests(["◇ Test run started.", "✔ Test run with 5 tests in 1 suite passed after 50.077 seconds."]), []);
  assert.deepEqual(unfinishedTests([]), []);
});

test("a line the simulator corrupted mid-way neither starts nor finishes a test", () => {
  const lines = [
    "◇ Test cleanStart() started.",
    "✔ Test cleanStart() passed after 5.674 sec2026-09-02 19:08:21.409714+0000 AscendApp[64835:175283] [Diagnostics] rem",
    "◇ Test corruptedStart() star2026-09-02 19:08:21.409714+0000 AscendApp[64835:175283] noise",
  ];

  // The corrupted finish line still carries `passed after`, so it counts; the
  // corrupted start line does not end in `started.` and is ignored.
  assert.deepEqual(unfinishedTests(lines), []);
});
