#!/usr/bin/env node
/**
 * Reads one test pass's `.xcresult` and refuses to let it count as a pass that
 * ran nothing.
 *
 * `xcodebuild test-without-building` exits 0 when every test it selected
 * passed - including when it selected none. With the passes named in
 * `plan-test-passes.mjs` rather than derived from an enumeration, a misspelled
 * or renamed suite in an `-only-testing:` list produces exactly that: a green
 * pass of zero tests, and a suite that has quietly stopped running (the
 * sibling measurement run of 2026-09-03 hit it twenty times in 84 attempts).
 * The result bundle is the one record of what actually executed, so this is
 * where the check lives.
 *
 * Two questions are answered from it. Did the pass execute any test at all?
 * And did every suite the pass was told to run execute at least one? The
 * executed count is printed as `executed-tests=<n>` for the caller to sum
 * across passes against `EXECUTED_TEST_FLOOR`.
 *
 * Usage: verify-test-pass-result.mjs <pass.xcresult> [<Target>/<Suite> ...]
 */

import {spawnSync} from "node:child_process";
import {realpathSync} from "node:fs";
import {fileURLToPath} from "node:url";

/**
 * The verdict on one pass, from `xcresulttool`'s `summary` and `tests` JSON.
 *
 * `executed` is every test the bundle counts minus the ones it skipped, which
 * is the count `-enumerate-tests` used to report (1,999 on 2026-09-02): a
 * parameterised test is one test however many arguments it takes.
 */
export function testPassVerdict({summary, tests, expectedSuites}) {
    const reasons = [];
    const total = Number(summary.totalTestCount ?? 0);
    const skipped = Number(summary.skippedTests ?? 0);
    const executed = total - skipped;

    if (executed <= 0) {
        reasons.push(
            "The pass executed no tests. An `-only-testing:` list that matches " +
                "nothing exits 0, so this is what a misspelled or renamed suite " +
                "looks like - fix the name in plan-test-passes.mjs."
        );
    }

    const executedBySuite = executedTestsBySuite(tests);

    for (const expected of expectedSuites) {
        const count = executedBySuite.get(expected) ?? 0;

        if (count === 0) {
            reasons.push(
                `Suite ${expected} was named in this pass but executed no tests. ` +
                    "It is named because it does not fit in a shared host, so fix " +
                    "the name in plan-test-passes.mjs rather than dropping it."
            );
        }
    }

    return {executed, reasons};
}

/**
 * `<bundle>/<suite>` -> executed test count, for every top-level suite in
 * every unit test bundle of the result.
 */
function executedTestsBySuite(tests) {
    const counts = new Map();

    for (const plan of tests.testNodes ?? []) {
        for (const bundle of plan.children ?? []) {
            if (bundle.nodeType !== "Unit test bundle") continue;

            for (const suite of bundle.children ?? []) {
                if (suite.nodeType !== "Test Suite") continue;

                counts.set(`${bundle.name}/${suite.name}`, executedTestCases(suite));
            }
        }
    }

    return counts;
}

function executedTestCases(node) {
    let count = 0;

    for (const child of node.children ?? []) {
        if (child.nodeType === "Test Case") {
            if (child.result !== "Skipped") count += 1;
        } else if (child.nodeType === "Test Suite") {
            count += executedTestCases(child);
        }
    }

    return count;
}

function readResult(kind, resultPath) {
    const result = spawnSync(
        "xcrun",
        ["xcresulttool", "get", "test-results", kind, "--path", resultPath],
        {encoding: "utf8", maxBuffer: 256 * 1024 * 1024}
    );

    if (result.status !== 0) {
        console.error(
            `::error::Could not read the ${kind} of ${resultPath}: ${result.stderr.trim()}`
        );
        process.exit(2);
    }

    return JSON.parse(result.stdout);
}

function main() {
    const [resultPath, ...expectedSuites] = process.argv.slice(2);

    if (!resultPath) {
        console.error("usage: verify-test-pass-result.mjs <pass.xcresult> [<Target>/<Suite> ...]");
        process.exit(2);
    }

    const summary = readResult("summary", resultPath);
    const tests = readResult("tests", resultPath);
    const {executed, reasons} = testPassVerdict({summary, tests, expectedSuites});

    console.log(`executed-tests=${executed}`);

    if (reasons.length > 0) {
        for (const reason of reasons) {
            console.error(`::error::${reason}`);
        }
        process.exit(1);
    }
}

// `realpathSync` because a caller may name this file through a symlinked path
// (macOS puts `mkdtemp` under /var, which is /private/var), and the module URL
// is always the resolved one.
if (process.argv[1] && fileURLToPath(import.meta.url) === realpathSync(process.argv[1])) {
    main();
}
