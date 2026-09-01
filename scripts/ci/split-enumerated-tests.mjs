#!/usr/bin/env node
/**
 * Splits an `xcodebuild -enumerate-tests` result into balanced `-only-testing`
 * argument lists, one file per pass.
 *
 * The split is by suite, never by individual test: a suite is the unit
 * `-only-testing` addresses cheaply, and `.serialized` suites assume their own
 * cases run together. Balancing is by test count rather than suite count,
 * because suite sizes range from one case to several dozen and an even count of
 * suites is not an even amount of work.
 *
 * Derived from the enumeration rather than from a checked-in list on purpose. A
 * hand-maintained partition goes stale the first time somebody adds a suite,
 * and the failure mode is silent - the new suite simply never runs, on a check
 * that stays green.
 */

import {readFileSync, writeFileSync} from "node:fs";

const [enumerationPath, outputPrefix, passCountArgument] = process.argv.slice(2);

if (!enumerationPath || !outputPrefix) {
    console.error(
        "usage: split-enumerated-tests.mjs <enumeration.json> <output-prefix> [passes]"
    );
    process.exit(2);
}

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

if (testCountsBySuite.size < passCount) {
    console.error(
        `Cannot split ${testCountsBySuite.size} suites across ${passCount} passes.`
    );
    process.exit(1);
}

// Longest-processing-time first: heaviest suites placed first, each onto the
// lightest pass so far. Greedy, deterministic, and within 4/3 of optimal, which
// is far more balance than this needs.
const passes = Array.from({length: passCount}, () => ({suites: [], tests: 0}));
const heaviestFirst = [...testCountsBySuite.entries()].sort(
    ([leftSuite, leftCount], [rightSuite, rightCount]) =>
        rightCount - leftCount || leftSuite.localeCompare(rightSuite)
);

for (const [suite, count] of heaviestFirst) {
    const lightest = passes.reduce((a, b) => (b.tests < a.tests ? b : a));
    lightest.suites.push(suite);
    lightest.tests += count;
}

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
        `pass ${index + 1}: ${pass.suites.length} suites, ${pass.tests} tests -> ${path}`
    );
});
