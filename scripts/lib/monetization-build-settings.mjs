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

export function appBuildConfigurations(project) {
  const configurations = new Map();

  for (const [, name, buildSettings] of project.matchAll(CONFIGURATION_PATTERN)) {
    const bundleID = settingValue(buildSettings, "PRODUCT_BUNDLE_IDENTIFIER");
    if (bundleID === null || !APP_BUNDLE_IDENTIFIERS.has(bundleID)) {
      continue;
    }

    configurations.set(name, {name, bundleID, buildSettings});
  }

  return configurations;
}

export function isPlaceholderAPIKey(value) {
  return value.trim().toUpperCase().startsWith(PLACEHOLDER_API_KEY_PREFIX);
}

// Every reason the configuration's monetization keys cannot reach real users.
export function unshippableMonetizationKeyReasons(buildSettings, configurationName) {
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

  return reasons;
}
