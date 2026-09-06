#!/usr/bin/env node
/**
 * Writes the `xcodebuild` argument list for every test pass `iOS Verify
 * (Staging)` runs, one file per pass, without enumerating the suite first.
 *
 * The passes are named, never balanced: each isolated group is an
 * `-only-testing:` list, and the last pass is `-skip-testing:` of exactly the
 * same names, so `xcodebuild` computes the complement itself and a suite that
 * did not exist when this file was written lands in the last pass by
 * construction. That is the property the old `-enumerate-tests` run existed to
 * protect, and it held it at the price of a whole host launch that executed
 * zero tests and absorbed the runner's cold simulator boot - 4.5 minutes of a
 * 40-minute job, measured 2026-09-02 on job 100376172708.
 *
 * What enumeration also caught - a name in this file that no longer matches a
 * real suite - is now caught after the pass instead: `run-ios-test-passes.sh`
 * reads every pass's `.xcresult` and fails when a named suite executed nothing,
 * and again when the job's executed total falls under `EXECUTED_TEST_FLOOR`.
 * A misspelled name here is therefore still a red check, never a suite that
 * quietly stops running.
 *
 * The split is by suite, never by individual test: a suite is the unit
 * `-only-testing` addresses cheaply, and `.serialized` suites assume their own
 * cases run together.
 */

import {realpathSync, writeFileSync} from "node:fs";
import {fileURLToPath} from "node:url";

const TEST_TARGET = "AscendAppTests";

/**
 * Suites that do not fit in a shared host process, as passes: every inner
 * array is one host process, every name in it is one suite.
 *
 * WHY, measured 2026-09-01 and again 2026-09-03 on `iOS Verify (Staging)`:
 * memory, never minutes. The first killed runs died with `EXC_BREAKPOINT` /
 * "mach_vm_allocate_kernel failed within call to vm_map_enter" - an allocation
 * failure, not a logic defect. The 2026-09-03 runs died quieter: pass 2 of
 * the two-way split completed 928 of 997 tests in four minutes, then produced
 * nothing for 27 minutes with the host alive, 13 screen-render suites still
 * in flight and 67 MB free on the runner, until the job hit its cap - which
 * GitHub reports as cancelled, not failed. Raising the cap changed nothing.
 *
 * What put the render suites there was how they read a screen, not what they
 * asserted: each hosted a full screen in its own `UIWindow`, photographed it
 * at 3x (12 MB a bitmap) and OCR'd the bitmap, and the host never gave that
 * memory back, so twenty suites held 896-1,434 MB each and a shared host
 * accumulated every one of them. Since 2026-09-03 every render suite reads
 * its screen through `AscendAppTests/RenderedScreen.swift` - copy off the
 * accessibility tree, pixels at 1x inside a closure that releases them, the
 * 3x photograph only when `ASCEND_EVIDENCE_DIR` is set - and the isolated
 * group of twenty is gone: measured with the same 10 Hz RSS sampler, the
 * heaviest of them now peaks at ~1,100 MB alone (the Sentry mask proof, which
 * still photographs by design) and the median at ~640, and the WHOLE
 * remainder runs in one serial host (the numbers are in
 * `run-ios-test-passes.sh`'s header).
 *
 * One suite stays out. `ShareComposerBackgroundFillEvidenceTests` peaks at
 * 2,200-2,350 MB across five tests because three of them each export a real
 * movie through the AVFoundation pipeline at the 1080x2340 story frame - the
 * cost is the assertion, so it keeps a host entirely to itself.
 *
 * Add a suite only with a measurement, and remove it the moment it stops
 * needing a host of its own. A name that no longer matches a real suite is
 * fatal on purpose, through the post-pass `.xcresult` check: a silently
 * dropped entry sends the suite back into the shared host, which is exactly
 * how this job started exhausting its runner.
 */
export const ISOLATED_PASSES = [["ShareComposerBackgroundFillEvidenceTests"]];

/**
 * The fewest tests a green job may have executed across all of its passes.
 *
 * The suite executed 1,999 tests on the last enumerated run (job
 * 100376172708, 2026-09-02); that is the coverage baseline. The floor sits
 * under it so that ordinary churn - a deleted suite, a merged pair - does not
 * turn the check red, while a pass shape that silently drops a hundred tests
 * does. Moving it is a deliberate act: raise it when the suite grows, lower it
 * only with the deletion that justifies it named in the same change.
 */
export const EXECUTED_TEST_FLOOR = 1900;

/** Every suite this file names, each exactly once. */
export function namedSuites() {
    return ISOLATED_PASSES.flat();
}

/**
 * The passes in the order they run, each as the `xcodebuild` arguments it adds
 * to the common set and the suites it is expected to execute.
 *
 * Isolated passes run first so their memory is released before the long pass
 * starts, and so a failure in one is reported against a five-test pass rather
 * than buried in a two-thousand-test one.
 *
 * Every pass runs serially (`-parallel-testing-enabled NO`). For the isolated
 * movie host that is because its tests each hold most of the runner and Swift
 * Testing would start them at once. For the remainder it is a measurement,
 * not a guess: the whole remainder in one host on 2026-09-03 took 377 s
 * parallel and 378 s serial and peaked at 2,090 MB against 2,109 MB (measured
 * before nine hosted screens were restored; re-measured serial on 2026-09-04
 * at 9d2cbcb5 it took 291 s and peaked at 2,041 MB over 1,995 tests), because
 * every hosting suite already serialises on the `.hostsAWindow` gate and the
 * logic suites are milliseconds each - so parallelism bought nothing, and
 * what it cost was real: a hosted test's reported duration was mostly its
 * wait in the gate's queue (which is why the per-test allowance had to sit at
 * 600 s), and a hosted read raced every other suite for the main actor, which
 * is where the copy-read flakes came from. Serial, a duration is the test's
 * own and a hang is the test's own.
 */
export function planTestPasses() {
    const suites = namedSuites();
    const duplicates = suites.filter((suite, index) => suites.indexOf(suite) !== index);

    if (duplicates.length > 0) {
        throw new Error(
            `A suite may be named in only one pass: ${[...new Set(duplicates)].join(", ")}`
        );
    }

    const identifier = (suite) => `${TEST_TARGET}/${suite}`;
    const passes = ISOLATED_PASSES.map((group, index) => ({
        label: `isolated group ${index + 1}, serial`,
        arguments: [
            "-parallel-testing-enabled",
            "NO",
            ...[...group].sort().map((suite) => `-only-testing:${identifier(suite)}`),
        ],
        expectedSuites: [...group].sort().map(identifier),
    }));

    passes.push({
        label: "remainder, everything not named, serial",
        arguments: [
            "-parallel-testing-enabled",
            "NO",
            ...[...suites].sort().map((suite) => `-skip-testing:${identifier(suite)}`),
        ],
        expectedSuites: [],
    });

    return passes;
}

function main() {
    const [outputPrefix] = process.argv.slice(2);

    if (!outputPrefix) {
        console.error("usage: plan-test-passes.mjs <output-prefix>");
        process.exit(2);
    }

    const passes = planTestPasses();

    passes.forEach((pass, index) => {
        const path = `${outputPrefix}${index + 1}.txt`;
        writeFileSync(path, pass.arguments.join("\n") + "\n");
        const named =
            pass.expectedSuites.length > 0
                ? `${pass.expectedSuites.length} named suites`
                : `all but ${pass.arguments.length} named suites`;
        console.log(`pass ${index + 1}: ${pass.label} (${named}) -> ${path}`);
    });

    console.log(`executed-test floor: ${EXECUTED_TEST_FLOOR}`);
}

// `realpathSync` because a caller may name this file through a symlinked path
// (macOS puts `mkdtemp` under /var, which is /private/var), and the module URL
// is always the resolved one.
if (process.argv[1] && fileURLToPath(import.meta.url) === realpathSync(process.argv[1])) {
    main();
}
