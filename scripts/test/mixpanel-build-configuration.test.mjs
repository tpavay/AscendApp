import assert from "node:assert/strict";
import {readFile, readdir} from "node:fs/promises";
import {join} from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";

import {
  MIXPANEL_CONFIGURATION_CONTRACTS,
  builtBundleReasons,
  mixpanelConfigurationReasons,
  mixpanelConfigurationsFromProject
} from "../lib/mixpanel-build-settings.mjs";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
const projectPath = join(repositoryRoot, "AscendApp.xcodeproj/project.pbxproj");
const infoPlistPath = join(repositoryRoot, "AscendApp/Info.plist");

test("each app build configuration owns its Mixpanel project and token", async () => {
  const project = await readFile(projectPath, "utf8");
  const configurations = mixpanelConfigurationsFromProject(project);

  assert.deepEqual(mixpanelConfigurationReasons(configurations), []);
});

test("the contract rejects any two configurations that converge on one token", async () => {
  const project = await readFile(projectPath, "utf8");
  const configurations = mixpanelConfigurationsFromProject(project);
  configurations.get("Staging").token = configurations.get("Debug").token;

  const reasons = mixpanelConfigurationReasons(configurations);
  assert.ok(reasons.includes(
    "Mixpanel tokens must be pairwise distinct across Debug, Staging, and Release."
  ));
});

test("the Release bundle contract accepts only the production destination", async () => {
  const project = await readFile(projectPath, "utf8");
  const configurations = mixpanelConfigurationsFromProject(project);
  const release = configurations.get("Release");

  assert.deepEqual(
    builtBundleReasons("Release", {
      AscendMixpanelProjectID: release.projectID,
      AscendMixpanelToken: release.token,
      CFBundleShortVersionString: "1.0",
      CFBundleVersion: "2"
    }),
    []
  );

  assert.notEqual(release.token, configurations.get("Debug").token);
  assert.notEqual(release.token, configurations.get("Staging").token);
  assert.equal(release.projectID, MIXPANEL_CONFIGURATION_CONTRACTS.get("Release").projectID);
});

test("the bundle contract rejects an archive whose telemetry envelope cannot validate", async () => {
  const project = await readFile(projectPath, "utf8");
  const release = mixpanelConfigurationsFromProject(project).get("Release");

  const reasons = builtBundleReasons("Release", {
    AscendMixpanelProjectID: release.projectID,
    AscendMixpanelToken: release.token,
    CFBundleShortVersionString: " ",
    CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
  });

  assert.deepEqual(reasons, [
    "Release bundle has no expanded CFBundleShortVersionString, so its telemetry envelope cannot validate.",
    "Release bundle has no expanded CFBundleVersion, so its telemetry envelope cannot validate."
  ]);
});

test("Info.plist expands both Mixpanel build settings", async () => {
  const infoPlist = await readFile(infoPlistPath, "utf8");

  assert.match(
    infoPlist,
    /<key>AscendMixpanelToken<\/key>\s*<string>\$\(ASCEND_MIXPANEL_TOKEN\)<\/string>/
  );
  assert.match(
    infoPlist,
    /<key>AscendMixpanelProjectID<\/key>\s*<string>\$\(ASCEND_MIXPANEL_PROJECT_ID\)<\/string>/
  );
});

test("Mixpanel SDK imports stay inside the telemetry adapter", async () => {
  const adapterPaths = [
    "AscendApp/Shared/Services/Telemetry/MixpanelClient.swift",
    "AscendApp/Shared/Services/Telemetry/MixpanelSDKClient.swift",
    "AscendApp/Shared/Services/Telemetry/MixpanelTelemetrySink.swift"
  ];
  const swiftPaths = (await readdir(join(repositoryRoot, "AscendApp"), {recursive: true}))
    .filter((path) => path.endsWith(".swift"))
    .map((path) => `AscendApp/${path}`);
  const sources = await Promise.all(
    swiftPaths.map(async (path) => [path, await readFile(join(repositoryRoot, path), "utf8")])
  );
  const importers = sources
    .filter(([, source]) => /import Mixpanel/.test(source))
    .map(([path]) => path)
    .sort();

  assert.deepEqual(importers, adapterPaths.sort());

  const project = await readFile(projectPath, "utf8");
  const appSource = sources.map(([, source]) => source).join("\n");
  assert.doesNotMatch(
    `${project}\n${appSource}`,
    /MixpanelSessionReplay|SessionReplay\.initialize|sessionReplay/i,
    "Mixpanel session replay must stay disabled"
  );
});
