import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {chmod, mkdir, rm, writeFile} from "node:fs/promises";
import {delimiter, join} from "node:path";

// The IPA verifiers normalise the archived Info.plist through plutil, which
// only exists on macOS. The fixtures below archive JSON already, so a
// passthrough stands in for it on every platform CI runs the suite on.
export async function plutilStubEnvironment(root) {
  const binDir = join(root, "bin");
  await mkdir(binDir, {recursive: true});

  const stub = join(binDir, "plutil");
  await writeFile(stub, "#!/usr/bin/env node\nprocess.stdin.pipe(process.stdout);\n");
  await chmod(stub, 0o755);

  return {...process.env, PATH: `${binDir}${delimiter}${process.env.PATH ?? ""}`};
}

// entries: [[archivePath, infoDictionary], ...]
export async function writeIpa(ipaPath, entries) {
  const contentsRoot = `${ipaPath}.contents`;
  for (const [entryPath, contents] of entries) {
    const path = join(contentsRoot, entryPath);
    await mkdir(join(path, ".."), {recursive: true});
    await writeFile(path, `${JSON.stringify(contents)}\n`);
  }

  await mkdir(join(ipaPath, ".."), {recursive: true});
  const zipped = spawnSync("zip", ["-q", "-r", ipaPath, "Payload"], {
    cwd: contentsRoot,
    encoding: "utf8"
  });
  assert.equal(zipped.status, 0, zipped.stderr);
  await rm(contentsRoot, {recursive: true, force: true});

  return ipaPath;
}
