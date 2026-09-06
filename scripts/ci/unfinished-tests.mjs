#!/usr/bin/env node
/**
 * Lists the tests a pass started and never finished, from its `xcodebuild`
 * log: every `◇ Test <name> started.` line with no matching
 * `✔ Test <name> passed` or `✘ Test <name> failed` line after it.
 *
 * A wedged host names nothing on its own - it just stops - and once the
 * watchdog kills it the result bundle is whatever `xcodebuild` managed to
 * finalise. The log is the record that survives, and this is the extraction
 * that turned the 2026-09-02 cancellations from "the job timed out" into "13
 * render suites were in flight with 67 MB free".
 *
 * Only the pass's own slice of the log is read, from the line number the
 * caller recorded when the pass began, because every pass appends to the same
 * file and an earlier pass's finished tests are not this pass's.
 *
 * Usage: unfinished-tests.mjs <log-path> [first-line-number]
 */

import {readFileSync, realpathSync} from "node:fs";
import {fileURLToPath} from "node:url";

const STARTED = /◇ Test (?!case )(.+) started\.$/;
const FINISHED = /[✔✘] Test (.+?)(?: with \d+ test cases)? (?:passed|failed) after /;

/** Test names started in `lines` with no later pass or fail line. */
export function unfinishedTests(lines) {
    const started = [];
    const finished = new Set();

    for (const line of lines) {
        // Simulator app logging interleaves mid-line with Swift Testing's
        // output, so a test's start and finish are matched on the name alone.
        const startedMatch = line.match(STARTED);
        if (startedMatch && startedMatch[1] !== "run") {
            started.push(startedMatch[1]);
            continue;
        }

        const finishedMatch = line.match(FINISHED);
        if (finishedMatch) {
            finished.add(finishedMatch[1]);
        }
    }

    return started.filter((name) => !finished.has(name));
}

function main() {
    const [logPath, firstLineArgument] = process.argv.slice(2);

    if (!logPath) {
        console.error("usage: unfinished-tests.mjs <log-path> [first-line-number]");
        process.exit(2);
    }

    const firstLine = Math.max(1, Number.parseInt(firstLineArgument ?? "1", 10) || 1);
    const lines = readFileSync(logPath, "utf8").split("\n").slice(firstLine - 1);
    const unfinished = unfinishedTests(lines);

    console.log(`Tests started and not finished: ${unfinished.length}`);
    for (const name of unfinished) {
        console.log(`    ${name}`);
    }
}

// `realpathSync` because a caller may name this file through a symlinked path
// (macOS puts `mkdtemp` under /var, which is /private/var), and the module URL
// is always the resolved one.
if (process.argv[1] && fileURLToPath(import.meta.url) === realpathSync(process.argv[1])) {
    main();
}
