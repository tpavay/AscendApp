import {createHash} from "node:crypto";

import {
  appBuildConfigurations,
  settingValue
} from "./monetization-build-settings.mjs";

export const MIXPANEL_CONFIGURATION_CONTRACTS = new Map([
  [
    "Debug",
    {
      scheme: "AscendApp",
      projectID: "4032860",
      tokenSHA256: "03352184b0f05fd24e805da4d142ac13cbfd2ccf914e91ee7ef3f2f67b1db71c"
    }
  ],
  [
    "Staging",
    {
      scheme: "AscendApp-Staging",
      projectID: "4051102",
      tokenSHA256: "aed6243214f89cf85988064990198273b258940e6c03ae1cb4a8d62e08db3c31"
    }
  ],
  [
    "Release",
    {
      scheme: "AscendApp",
      projectID: "4051100",
      tokenSHA256: "dd403ffc2d776ac923b4cdafbc480cf02f9a7703f2877bd61de3ba86911b58df"
    }
  ]
]);

export function tokenDigest(token) {
  return createHash("sha256").update(token).digest("hex");
}

export function mixpanelConfigurationsFromProject(project) {
  const configurations = new Map();

  for (const [name, {buildSettings}] of appBuildConfigurations(project)) {
    configurations.set(name, {
      projectID: settingValue(buildSettings, "ASCEND_MIXPANEL_PROJECT_ID"),
      token: settingValue(buildSettings, "ASCEND_MIXPANEL_TOKEN")
    });
  }

  return configurations;
}

export function mixpanelConfigurationReasons(configurations) {
  const reasons = [];
  const expectedNames = [...MIXPANEL_CONFIGURATION_CONTRACTS.keys()].sort();
  const actualNames = [...configurations.keys()].sort();

  if (JSON.stringify(actualNames) !== JSON.stringify(expectedNames)) {
    reasons.push("The app target must define Debug, Staging, and Release Mixpanel destinations.");
  }

  const tokens = [];
  const projectIDs = [];

  for (const [name, contract] of MIXPANEL_CONFIGURATION_CONTRACTS) {
    const configuration = configurations.get(name);
    if (!configuration) continue;

    if (!isExpandedValue(configuration.projectID)) {
      reasons.push(`${name} has no expanded Mixpanel project ID.`);
    } else {
      projectIDs.push(configuration.projectID);
      if (configuration.projectID !== contract.projectID) {
        reasons.push(`${name} targets the wrong Mixpanel project ID.`);
      }
    }

    if (!isExpandedValue(configuration.token)) {
      reasons.push(`${name} has no expanded Mixpanel token.`);
    } else {
      tokens.push(configuration.token);
      if (tokenDigest(configuration.token) !== contract.tokenSHA256) {
        reasons.push(`${name} carries a token that does not belong to its configured project.`);
      }
    }
  }

  if (tokens.length === expectedNames.length && new Set(tokens).size !== tokens.length) {
    reasons.push("Mixpanel tokens must be pairwise distinct across Debug, Staging, and Release.");
  }
  if (projectIDs.length === expectedNames.length && new Set(projectIDs).size !== projectIDs.length) {
    reasons.push("Mixpanel project IDs must be pairwise distinct across Debug, Staging, and Release.");
  }

  return reasons;
}

export function builtBundleReasons(configurationName, infoDictionary) {
  const contract = MIXPANEL_CONFIGURATION_CONTRACTS.get(configurationName);
  if (!contract) {
    return ["The built bundle check requires Debug, Staging, or Release."];
  }

  const projectID = infoDictionary.AscendMixpanelProjectID;
  const token = infoDictionary.AscendMixpanelToken;
  const reasons = [];

  if (!isExpandedValue(projectID) || projectID !== contract.projectID) {
    reasons.push(`${configurationName} bundle resolved the wrong Mixpanel project ID.`);
  }
  if (!isExpandedValue(token) || tokenDigest(token) !== contract.tokenSHA256) {
    reasons.push(`${configurationName} bundle resolved a token that does not belong to its project.`);
  }

  return reasons;
}

function isExpandedValue(value) {
  return typeof value === "string" && value.trim() !== "" && !value.trim().startsWith("$(");
}
