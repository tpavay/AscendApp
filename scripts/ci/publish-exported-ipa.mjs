#!/usr/bin/env node
import {readdirSync, renameSync, rmSync} from "node:fs";
import {join} from "node:path";
import process from "node:process";

import {selectExportedIpa} from "../lib/exported-ipa.mjs";

const [exportDir, targetPath] = process.argv.slice(2);
if (!exportDir || !targetPath) {
  fail("Usage: publish-exported-ipa.mjs <exportDirectory> <targetIpaPath>");
}

let entries;
try {
  entries = readdirSync(exportDir);
} catch {
  fail(`Could not read the export directory ${exportDir}.`);
}

let exported;
try {
  exported = selectExportedIpa(entries);
} catch (error) {
  fail(`The export directory ${exportDir} ${error.message}`);
}

try {
  rmSync(targetPath, {force: true});
  renameSync(join(exportDir, exported), targetPath);
} catch (error) {
  fail(`Could not publish ${exported} as ${targetPath}: ${error.message}`);
}

console.log(`Published ${exported} as ${targetPath}.`);

function fail(message) {
  console.error(`::error::${message}`);
  process.exit(1);
}
