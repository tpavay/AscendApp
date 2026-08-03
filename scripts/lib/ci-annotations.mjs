/**
 * GitHub Actions workflow-command output, in one place.
 *
 * The escaping rule below is the reason this is shared rather than copied: four scripts in this
 * area emit annotations, and a copy that forgot the newline handling would silently truncate the
 * diagnosis an operator reads mid-release down to its first line.
 */

import {appendFileSync} from "node:fs";
import process from "node:process";

// A workflow command terminates at its first raw newline, so a multi-line annotation has to
// carry `%0A` to survive into the rendered error rather than only the raw log.
export function annotate(level, message) {
  const stream = level === "error" ? console.error : console.log;
  stream(`::${level}::${String(message).replaceAll("\n", "%0A")}`);
}

/**
 * Appends to the job summary, or - when `fallbackToConsole` is set - prints the same lines when
 * there is no summary file, which is what a local run of a reporting script has instead.
 */
export function summarize(lines, {fallbackToConsole = false} = {}) {
  const path = process.env.GITHUB_STEP_SUMMARY;

  if (!path) {
    if (fallbackToConsole) {
      console.log(lines.join("\n"));
    }
    return;
  }

  appendFileSync(path, `${lines.join("\n")}\n`);
}
