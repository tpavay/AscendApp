#!/usr/bin/env node
/**
 * Splits an `xcodebuild -enumerate-tests` result into `-only-testing` argument
 * lists, one file per pass: a pass of its own for each suite that is too heavy
 * to share a host, then the remainder balanced across the ordinary passes.
 *
 * The split is by suite, never by individual test: a suite is the unit
 * `-only-testing` addresses cheaply, and `.serialized` suites assume their own
 * cases run together. Balancing is by test count rather than suite count,
 * because suite sizes range from one case to several dozen and an even count of
 * suites is not an even amount of work.
 *
 * The *partition* is derived from the enumeration rather than checked in, on
 * purpose: a hand-maintained partition goes stale the first time somebody adds
 * a suite, and the failure mode is silent - the new suite simply never runs, on
 * a check that stays green. `ISOLATED_SUITES` is the one exception, and it is
 * deliberately fail-loud: a name that no longer matches any enumerated suite
 * stops the split rather than quietly returning to a two-way partition that
 * exhausts the runner again.
 */

import {readFileSync, writeFileSync} from "node:fs";

const [enumerationPath, outputPrefix, passCountArgument] = process.argv.slice(2);

if (!enumerationPath || !outputPrefix) {
    console.error(
        "usage: split-enumerated-tests.mjs <enumeration.json> <output-prefix> [passes]"
    );
    process.exit(2);
}

/**
 * Suites given a host process to themselves because their peak memory does not
 * fit beside anything else.
 *
 * Measured 2026-09-01 on `iOS Verify (Staging)`, which was failing with
 * `EXC_BREAKPOINT` / "mach_vm_allocate_kernel failed within call to
 * vm_map_enter" - an allocation failure, not a logic defect.
 * `ShareComposerBackgroundFillEvidenceTests` peaks at 2,205 MB across 5 tests,
 * against 1,199 MB for the next heaviest suite in flight and 612 MB for a
 * three-test control. Three of its tests each cost ~1.1 GB above baseline
 * (1,760 / 1,736 / 1,696 MB) because each exports a real movie through the
 * app's AVFoundation pipeline at the 1080x2340 story frame.
 *
 * That cost is the assertion, so it is not reducible: each test proves an
 * exported movie fills the story frame, the fixture is already 12 frames at
 * 12fps, and a smaller export would delete what is being checked. Isolating the
 * suite costs one extra host launch on a pass of five tests - roughly 90
 * seconds - where a general three-way split would slow every run by ~4 minutes.
 *
 * Add to this list only with a measurement, and remove from it the moment a
 * suite stops needing it.
 */
const ISOLATED_SUITES = ["AscendAppTests/ShareComposerBackgroundFillEvidenceTests"];

const passCount = Number.parseInt(passCountArgument ?? "2", 10);

if (!Number.isInteger(passCount) || passCount < 1) {
    console.error(`Pass count must be a positive integer, got ${passCountArgument}`);
    process.exit(2);
}

const enumeration = JSON.parse(readFileSync(enumerationPath, "utf8"));

if (Array.isArray(enumeration.errors) && enumeration.errors.length > 0) {
    console.error("Test enumeration reported errors:");
    for (const error of enumeration.errors) {
        console.error(`  ${JSON.stringify(error)}`);
    }
    process.exit(1);
}

// An identifier is `<target>/<suite>/<case>`. A suite with no cases cannot be
// enumerated, so anything shorter is a shape this script does not understand and
// must not silently drop.
const testCountsBySuite = new Map();

for (const value of enumeration.values ?? []) {
    for (const {identifier} of value.enabledTests ?? []) {
        const segments = identifier.split("/");

        if (segments.length < 3) {
            console.error(`Unrecognised test identifier: ${identifier}`);
            process.exit(1);
        }

        const suite = `${segments[0]}/${segments[1]}`;
        testCountsBySuite.set(suite, (testCountsBySuite.get(suite) ?? 0) + 1);
    }
}

if (testCountsBySuite.size === 0) {
    console.error(
        "Test enumeration listed no tests. That is a broken build or a bad " +
            "destination, never an empty suite, so it fails rather than writing " +
            "passes that would run nothing and report success."
    );
    process.exit(1);
}

if (testCountsBySuite.size < passCount + ISOLATED_SUITES.length) {
    console.error(
        `Cannot split ${testCountsBySuite.size} suites across ${passCount} balanced ` +
            `passes plus ${ISOLATED_SUITES.length} isolated.`
    );
    process.exit(1);
}

// A suite that must not share a host is lifted out before anything is balanced.
// An unmatched name is fatal: silently falling back to the balanced-only split
// is exactly how this job started exhausting its runner.
const isolated = [];

for (const suite of ISOLATED_SUITES) {
    const count = testCountsBySuite.get(suite);

    if (count === undefined) {
        console.error(
            `Isolated suite ${suite} matched nothing in the enumeration. Rename it ` +
                `in ISOLATED_SUITES or drop it, but do not leave it unmatched: it is ` +
                `listed because it does not fit in a shared host process.`
        );
        process.exit(1);
    }

    isolated.push({suites: [suite], tests: count});
    testCountsBySuite.delete(suite);
}

// Longest-processing-time first: heaviest suites placed first, each onto the
// lightest pass so far. Greedy, deterministic, and within 4/3 of optimal, which
// is far more balance than this needs.
const balanced = Array.from({length: passCount}, () => ({suites: [], tests: 0}));
const heaviestFirst = [...testCountsBySuite.entries()].sort(
    ([leftSuite, leftCount], [rightSuite, rightCount]) =>
        rightCount - leftCount || leftSuite.localeCompare(rightSuite)
);

for (const [suite, count] of heaviestFirst) {
    const lightest = balanced.reduce((a, b) => (b.tests < a.tests ? b : a));
    lightest.suites.push(suite);
    lightest.tests += count;
}

// Isolated passes run first so their memory is released before the long passes
// start, and so a failure in one is reported against a five-test pass rather
// than buried in a nine-hundred-test one.
const passes = [...isolated, ...balanced];

passes.forEach((pass, index) => {
    const path = `${outputPrefix}${index + 1}.txt`;
    writeFileSync(
        path,
        pass.suites
            .sort()
            .map((suite) => `-only-testing:${suite}`)
            .join("\n") + "\n"
    );
    console.log(
        `pass ${index + 1}: ${pass.suites.length} suites, ${pass.tests} tests` +
            `${index < isolated.length ? " (isolated)" : ""} -> ${path}`
    );
});
