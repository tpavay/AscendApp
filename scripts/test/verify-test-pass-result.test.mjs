/**
 * The zero-test guard of `scripts/ci/verify-test-pass-result.mjs`.
 *
 * `xcodebuild test-without-building` exits 0 for a pass that selected no
 * tests, so a misspelled suite in an `-only-testing:` list is a green pass
 * that ran nothing. The verdict below is what stands between that and a green
 * check. The fixtures mirror the shape `xcrun xcresulttool get test-results
 * summary` and `... tests` print for Xcode 26.3: a test plan node holding a
 * unit test bundle holding top-level suites holding test cases.
 */

import assert from "node:assert/strict";
import {test} from "node:test";

import {testPassVerdict} from "../ci/verify-test-pass-result.mjs";

function bundle(suites) {
  return {
    testNodes: [
      {
        nodeType: "Test Plan",
        name: "AscendApp-Staging",
        children: [
          {
            nodeType: "Unit test bundle",
            name: "AscendAppTests",
            children: suites.map(({name, cases, nested = []}) => ({
              nodeType: "Test Suite",
              name,
              children: [
                ...cases.map((result, index) => ({
                  nodeType: "Test Case",
                  name: `case${index}()`,
                  result,
                })),
                ...nested.map((inner) => ({
                  nodeType: "Test Suite",
                  name: inner.name,
                  children: inner.cases.map((result, index) => ({
                    nodeType: "Test Case",
                    name: `inner${index}()`,
                    result,
                  })),
                })),
              ],
            })),
          },
        ],
      },
    ],
  };
}

function summary({total, skipped = 0}) {
  return {totalTestCount: total, skippedTests: skipped, passedTests: total - skipped, failedTests: 0};
}

test("a pass that executed its named suites is clean and reports its executed count", () => {
  const verdict = testPassVerdict({
    summary: summary({total: 5, skipped: 1}),
    tests: bundle([
      {name: "AlphaTests", cases: ["Passed", "Passed"]},
      {name: "BetaTests", cases: ["Failed", "Skipped", "Passed"]},
    ]),
    expectedSuites: ["AscendAppTests/AlphaTests", "AscendAppTests/BetaTests"],
  });

  assert.deepEqual(verdict, {executed: 4, reasons: []});
});

test("a pass that executed nothing is a failure whatever xcodebuild exited with", () => {
  const verdict = testPassVerdict({
    summary: summary({total: 0}),
    tests: bundle([]),
    expectedSuites: [],
  });

  assert.equal(verdict.executed, 0);
  assert.equal(verdict.reasons.length, 1);
  assert.match(verdict.reasons[0], /executed no tests/);
  assert.match(verdict.reasons[0], /misspelled or renamed suite/);
});

test("a named suite that executed nothing names itself in the failure", () => {
  const verdict = testPassVerdict({
    summary: summary({total: 2}),
    tests: bundle([{name: "AlphaTests", cases: ["Passed", "Passed"]}]),
    expectedSuites: ["AscendAppTests/AlphaTests", "AscendAppTests/BetaTest"],
  });

  assert.equal(verdict.executed, 2);
  assert.deepEqual(
    verdict.reasons.map((reason) => reason.split(" was named")[0]),
    ["Suite AscendAppTests/BetaTest"]
  );
});

test("a named suite whose every case was skipped counts as not executed", () => {
  const verdict = testPassVerdict({
    summary: summary({total: 3, skipped: 2}),
    tests: bundle([
      {name: "AlphaTests", cases: ["Passed"]},
      {name: "SkippedTests", cases: ["Skipped", "Skipped"]},
    ]),
    expectedSuites: ["AscendAppTests/SkippedTests"],
  });

  assert.equal(verdict.executed, 1);
  assert.equal(verdict.reasons.length, 1);
  assert.match(verdict.reasons[0], /AscendAppTests\/SkippedTests/);
});

test("cases in a nested suite count toward their top-level suite", () => {
  const verdict = testPassVerdict({
    summary: summary({total: 2}),
    tests: bundle([
      {name: "OuterTests", cases: [], nested: [{name: "Inner", cases: ["Passed", "Passed"]}]},
    ]),
    expectedSuites: ["AscendAppTests/OuterTests"],
  });

  assert.deepEqual(verdict, {executed: 2, reasons: []});
});

test("a suite in another bundle does not satisfy a name in this one", () => {
  const tests = bundle([{name: "AlphaTests", cases: ["Passed"]}]);
  tests.testNodes[0].children[0].name = "OtherTests";

  const verdict = testPassVerdict({
    summary: summary({total: 1}),
    tests,
    expectedSuites: ["AscendAppTests/AlphaTests"],
  });

  assert.equal(verdict.reasons.length, 1);
});
