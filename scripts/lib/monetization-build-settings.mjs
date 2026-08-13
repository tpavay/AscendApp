// Mirrored by MonetizationConfiguration.placeholderAPIKeyPrefix, which nils out
// any key carrying this prefix so the app degrades to its unconfigured path.
export const PLACEHOLDER_API_KEY_PREFIX = "REPLACE_ME_";

// One entry per build setting behind MonetizationConfiguration.apiKeyInfoKeys, so
// the archive gate rejects exactly the placeholders that trip the launch backstop.
// The test key is optional: it ships empty, and only a placeholder makes it fatal.
export const MONETIZATION_API_KEY_SETTINGS = [
  {name: "ASCEND_REVENUECAT_API_KEY", isRequired: true},
  {name: "ASCEND_REVENUECAT_TEST_API_KEY", isRequired: false},
  {name: "ASCEND_SUPERWALL_API_KEY", isRequired: true}
];

// Settings that must be explicitly configured everywhere and can only be NO in
// the configurations listed. Nothing in Swift can catch these: access is now
// data-driven rather than compiled out, so an archive is the last place a
// reopened paywall can still be stopped.
//
// Access is pinned for Release alone because setting Staging to YES is the
// documented recovery lever for testers stranded at the staging gate. That
// recovery is deliberately two steps: this gate lets the staging archive
// through, while scripts/test/monetization-build-configuration.test.mjs still
// pins Staging to NO, so relaxing it has to be an explicit reviewable diff
// (docs/superwall-paywall-setup.md). Production has no such escape hatch.
export const MONETIZATION_SAFETY_SETTINGS = [
  {
    name: "ASCEND_ALLOWS_UNENTITLED_APP_ACCESS",
    pinnedConfigurations: ["Release"],
    consequence: "would ship the App Store build with the hard paywall bypassed"
  },
  {
    name: "ASCEND_SUPERWALL_TEST_MODE",
    pinnedConfigurations: ["Staging", "Release"],
    consequence: "would ship against the Superwall test surface"
  },
  {
    name: "ASCEND_USE_REVENUECAT_TEST_STORE",
    pinnedConfigurations: ["Staging", "Release"],
    consequence: "would ship against the RevenueCat test store instead of the App Store"
  }
];

// Only the AscendApp target carries the monetization settings; the widget and
// test targets share the same configuration names, so bundle ID is the filter.
const APP_BUNDLE_IDENTIFIERS = new Set([
  "com.TylerPavay.AscendApp.dev",
  "com.TylerPavay.AscendApp.staging",
  "com.TylerPavay.AscendApp"
]);

const CONFIGURATION_PATTERN =
  /[A-F0-9]{24} \/\* (Debug|Staging|Release) \*\/ = \{\n\s+isa = XCBuildConfiguration;\n\s+buildSettings = \{([\s\S]*?)\n\s+\};\n\s+name = \1;\n\s+\};/g;

export function settingValue(buildSettings, name) {
  const match = buildSettings.match(new RegExp(`^\\s*${name} = (.*);$`, "m"));
  return match ? match[1].replace(/^"(.*)"$/, "$1") : null;
}

// Every XCBuildConfiguration block in the project, across every target. One
// parser for the pbxproj format: a second copy becomes a second format the day
// Xcode changes how it writes these blocks.
export function buildConfigurations(project) {
  return [...project.matchAll(CONFIGURATION_PATTERN)].map(([, name, buildSettings]) => ({
    name,
    bundleID: settingValue(buildSettings, "PRODUCT_BUNDLE_IDENTIFIER"),
    buildSettings
  }));
}

export function appBuildConfigurations(project) {
  const configurations = new Map();

  for (const configuration of buildConfigurations(project)) {
    const {name, bundleID} = configuration;
    if (bundleID === null || !APP_BUNDLE_IDENTIFIERS.has(bundleID)) {
      continue;
    }

    configurations.set(name, configuration);
  }

  return configurations;
}

export function isPlaceholderAPIKey(value) {
  return value.trim().toUpperCase().startsWith(PLACEHOLDER_API_KEY_PREFIX);
}

// Every reason the configuration's monetization settings cannot reach real users.
export function unshippableMonetizationReasons(buildSettings, configurationName) {
  const reasons = [];

  for (const {name, isRequired} of MONETIZATION_API_KEY_SETTINGS) {
    const value = settingValue(buildSettings, name);

    if (value === null) {
      if (isRequired) {
        reasons.push(`${name} is not defined for the ${configurationName} configuration.`);
      }
      continue;
    }

    const trimmed = value.trim();

    if (isPlaceholderAPIKey(trimmed)) {
      reasons.push(
        `${name} is still the ${PLACEHOLDER_API_KEY_PREFIX} placeholder "${trimmed}" ` +
          `for the ${configurationName} configuration.`
      );
    } else if (!isRequired) {
      continue;
    } else if (trimmed === "") {
      reasons.push(`${name} is empty for the ${configurationName} configuration.`);
    } else if (trimmed.startsWith("$(")) {
      reasons.push(
        `${name} is the unexpanded reference "${trimmed}" for the ${configurationName} configuration.`
      );
    }
  }

  for (const {name, pinnedConfigurations, consequence} of MONETIZATION_SAFETY_SETTINGS) {
    const value = settingValue(buildSettings, name);

    if (value === null) {
      reasons.push(
        `${name} is not defined for the ${configurationName} configuration; ` +
          "every configuration must set it explicitly."
      );
      continue;
    }

    if (!pinnedConfigurations.includes(configurationName)) {
      continue;
    }

    const trimmed = value.trim();

    if (trimmed !== "NO") {
      reasons.push(
        `${name} is "${trimmed}" for the ${configurationName} configuration, which ${consequence}. ` +
          "It must be NO."
      );
    }
  }

  return reasons;
}
