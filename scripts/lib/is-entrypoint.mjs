import {realpathSync} from "node:fs";
import {fileURLToPath} from "node:url";

/**
 * Whether `moduleUrl` is the module Node was invoked with.
 *
 * The obvious `import.meta.url === \`file://${process.argv[1]}\`` is wrong twice:
 * the ESM loader percent-encodes the module URL and realpaths it, while
 * `process.argv[1]` does neither. A checkout path containing a space, or any
 * invocation through a symlink, makes the compare false - and the failure mode is
 * a script that exits 0 having done nothing, which every caller reads as success.
 */
export function isEntrypoint(moduleUrl) {
  const invoked = process.argv[1];
  if (!invoked) return false;

  try {
    return realpathSync(invoked) === realpathSync(fileURLToPath(moduleUrl));
  } catch {
    return false;
  }
}
