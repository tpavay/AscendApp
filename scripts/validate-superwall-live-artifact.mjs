#!/usr/bin/env node

import {readFile} from "node:fs/promises";

import {
  appBuildConfigurations,
  settingValue
} from "./lib/monetization-build-settings.mjs";
import {
  activePaywallResponse,
  runtimeStoreFromHTML,
  validateSuperwallArtifact
} from "./lib/superwall-live-artifact.mjs";

const projectPath = new URL("../AscendApp.xcodeproj/project.pbxproj", import.meta.url);
const placement = "app_access_gate";
const requestTimeoutMilliseconds = 10_000;
const requestAttempts = 3;
const environments = new Map([
  ["staging", "Staging"],
  ["production", "Release"]
]);

const requested = process.argv[2] ?? "all";
const selected = requested === "all" ? [...environments] : [[requested, environments.get(requested)]];
if (selected.some(([, configuration]) => !configuration)) {
  console.error("Usage: validate-superwall-live-artifact.mjs [staging|production|all]");
  process.exit(2);
}

const project = await readFile(projectPath, "utf8");
const configurations = appBuildConfigurations(project);
let failed = false;

for (const [environment, configurationName] of selected) {
  const configuration = configurations.get(configurationName);
  if (!configuration) {
    console.error(`${environment}: missing ${configurationName} app build configuration.`);
    failed = true;
    continue;
  }

  const apiKey = settingValue(configuration.buildSettings, "ASCEND_SUPERWALL_API_KEY")?.trim();
  const yearlyProductID = settingValue(
    configuration.buildSettings,
    "ASCEND_REVENUECAT_YEARLY_PRODUCT_ID"
  );
  const monthlyProductID = settingValue(
    configuration.buildSettings,
    "ASCEND_REVENUECAT_MONTHLY_PRODUCT_ID"
  );
  if (!apiKey || !yearlyProductID || !monthlyProductID) {
    console.error(`${environment}: missing embedded monetization build settings.`);
    failed = true;
    continue;
  }

  const staticURL = new URL("https://api.superwall.me/api/v1/static_config");
  staticURL.searchParams.set("pk", apiKey);

  try {
    const staticResponse = await fetchWithRetry(staticURL, "static config");
    const staticConfig = await staticResponse.json();
    const {response} = activePaywallResponse(staticConfig, placement);

    // Use the complete provider URL unchanged. Its sw_cache_key selects the exact published
    // Editor artifact and must not be reconstructed from response IDs or document IDs.
    const runtimeResponse = await fetchWithRetry(response.url, "runtime");
    const runtimeStore = runtimeStoreFromHTML(await runtimeResponse.text());
    const result = validateSuperwallArtifact({
      staticConfig,
      runtimeStore,
      placement,
      expectedProductIDs: [yearlyProductID, monthlyProductID],
      expectedEntitlementID: "app_access"
    });

    console.log(JSON.stringify({environment, ...result.evidence}, null, 2));
    for (const error of result.errors) {
      console.error(`${environment}: ${error}`);
    }
    failed ||= result.errors.length > 0;
  } catch (error) {
    console.error(`${environment}: ${error.message}`);
    failed = true;
  }
}

if (failed) process.exit(1);

async function fetchWithRetry(url, label) {
  let lastStatus = null;

  for (let attempt = 1; attempt <= requestAttempts; attempt += 1) {
    try {
      const response = await fetch(url, {
        signal: AbortSignal.timeout(requestTimeoutMilliseconds)
      });
      if (response.ok) return response;
      lastStatus = response.status;
    } catch {
      // Provider and network errors can include the complete request URL.
      // Replace them with a bounded label so the public SDK key never reaches CI logs.
    }
  }

  const status = lastStatus === null ? "network failure or timeout" : `HTTP ${lastStatus}`;
  throw new Error(
    `${label} failed after ${requestAttempts} bounded attempts (${status}).`
  );
}
