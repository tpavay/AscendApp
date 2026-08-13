import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {mkdir, mkdtemp, readFile, readdir} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";

import {plutilStubEnvironment, writeIpa} from "./support/ipa-fixtures.mjs";
import {selectExportedIpa} from "../lib/exported-ipa.mjs";
import {mixpanelConfigurationsFromProject} from "../lib/mixpanel-build-settings.mjs";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
const projectPath = join(repositoryRoot, "AscendApp.xcodeproj/project.pbxproj");
const publisherPath = join(repositoryRoot, "scripts/ci/publish-exported-ipa.mjs");
const bundleVerifierPath = join(repositoryRoot, "scripts/ci/assert-mixpanel-bundle.mjs");
const fastfilePath = join(repositoryRoot, "fastlane/Fastfile");

test("the export selector accepts one IPA and refuses any other count", () => {
  assert.equal(
    selectExportedIpa(["AscendApp.ipa", "Packaging.log", "DistributionSummary.plist"]),
    "AscendApp.ipa"
  );

  assert.throws(
    () => selectExportedIpa(["AscendApp-Production.ipa", "AscendApp.ipa"]),
    /holds 2 exported \.ipa files \(AscendApp-Production\.ipa, AscendApp\.ipa\); expected exactly one/
  );
  assert.throws(
    () => selectExportedIpa(["Packaging.log"]),
    /holds no exported \.ipa/
  );
});

test("a leftover IPA cannot be published as this run's artifact", async () => {
  const root = await mkdtemp(join(tmpdir(), "ascend exported ipa "));
  const outputDir = join(root, "build");
  const exportDir = join(outputDir, "export");
  await mkdir(exportDir, {recursive: true});

  const project = await readFile(projectPath, "utf8");
  const staging = mixpanelConfigurationsFromProject(project).get("Staging");
  const watchInfo = {CFBundleIdentifier: "com.TylerPavay.AscendApp.staging.watch"};
  const freshPhoneInfo = {
    AscendMixpanelProjectID: staging.projectID,
    AscendMixpanelToken: staging.token,
    CFBundleShortVersionString: "1.0",
    CFBundleVersion: "2026081103"
  };
  const stalePhoneInfo = {...freshPhoneInfo, AscendMixpanelProjectID: "stale-project"};

  // The previous run's artifact, sorting ahead of this run's scheme-named
  // export, sitting exactly where the deploy workflow reads the IPA from.
  const targetPath = join(outputDir, "AscendApp-Staging.ipa");
  await writeIpa(targetPath, [
    ["Payload/AscendApp.app/Watch/AscendWatch.app/Info.plist", watchInfo],
    ["Payload/AscendApp.app/Info.plist", stalePhoneInfo]
  ]);
  await writeIpa(join(exportDir, "AscendApp.ipa"), [
    ["Payload/AscendApp.app/Watch/AscendWatch.app/Info.plist", watchInfo],
    ["Payload/AscendApp.app/Info.plist", freshPhoneInfo]
  ]);

  const published = spawnSync(
    process.execPath,
    [publisherPath, exportDir, targetPath],
    {encoding: "utf8"}
  );
  assert.equal(published.status, 0, published.stderr);
  assert.deepEqual(await readdir(exportDir), []);

  const verifierEnvironment = await plutilStubEnvironment(root);
  const verified = spawnSync(
    process.execPath,
    [bundleVerifierPath, "Staging", targetPath],
    {encoding: "utf8", env: verifierEnvironment}
  );
  assert.equal(verified.status, 0, verified.stderr);
  assert.match(verified.stdout, /Verified the Staging bundle/);
});

test("an ambiguous export refuses to publish and names every candidate", async () => {
  const root = await mkdtemp(join(tmpdir(), "ascend exported ipa "));
  const outputDir = join(root, "build");
  const exportDir = join(outputDir, "export");
  const targetPath = join(outputDir, "AscendApp-Production.ipa");

  const info = {CFBundleVersion: "2026081103"};
  await writeIpa(join(exportDir, "AscendApp.ipa"), [
    ["Payload/AscendApp.app/Info.plist", info]
  ]);
  await writeIpa(join(exportDir, "AscendApp-Production.ipa"), [
    ["Payload/AscendApp.app/Info.plist", info]
  ]);

  const published = spawnSync(
    process.execPath,
    [publisherPath, exportDir, targetPath],
    {encoding: "utf8"}
  );
  assert.equal(published.status, 1);
  assert.match(
    published.stderr,
    /holds 2 exported \.ipa files \(AscendApp-Production\.ipa, AscendApp\.ipa\); expected exactly one/
  );
  assert.deepEqual(await readdir(outputDir), ["export"]);
});

test("an empty export refuses to publish rather than leaving the previous artifact in place", async () => {
  const root = await mkdtemp(join(tmpdir(), "ascend exported ipa "));
  const outputDir = join(root, "build");
  const exportDir = join(outputDir, "export");
  await mkdir(exportDir, {recursive: true});
  const targetPath = join(outputDir, "AscendApp-Staging.ipa");
  await writeIpa(targetPath, [["Payload/AscendApp.app/Info.plist", {CFBundleVersion: "1"}]]);

  const published = spawnSync(
    process.execPath,
    [publisherPath, exportDir, targetPath],
    {encoding: "utf8"}
  );
  assert.equal(published.status, 1);
  assert.match(published.stderr, /holds no exported \.ipa/);
});

test("both signed lanes export into a cleaned directory and publish by exact name", async () => {
  const fastfile = await readFile(fastfilePath, "utf8");

  assert.doesNotMatch(
    fastfile,
    /Dir\.glob\([^)]*\*\.ipa/,
    "a wildcard export match can rename a stale IPA onto the published name"
  );
  assert.equal((fastfile.match(/^\s+export_dir = prepared_export_dir\(output_dir\)$/gm) ?? []).length, 2);
  assert.equal((fastfile.match(/-exportPath #\{export_dir\.shellescape\}/g) ?? []).length, 2);
  assert.deepEqual(
    [...fastfile.matchAll(/target_ipa: File\.join\(output_dir, "([^"]+)"\)/g)].map(([, name]) => name),
    ["AscendApp-Staging.ipa", "AscendApp-Production.ipa"]
  );
});
