// Mirrored by MonetizationConfiguration.placeholderAPIKeyPrefix, which nils out
// any key carrying this prefix so the app degrades to its unconfigured path.
export const PLACEHOLDER_API_KEY_PREFIX = "REPLACE_ME_";

export const MONETIZATION_API_KEY_SETTINGS = [
  "ASCEND_REVENUECAT_API_KEY",
  "ASCEND_SUPERWALL_API_KEY"
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

  for (const setting of MONETIZATION_API_KEY_SETTINGS) {
    const value = settingValue(buildSettings, setting);

    if (value === null) {
      reasons.push(`${setting} is not defined for the ${configurationName} configuration.`);
      continue;
    }

    const trimmed = value.trim();

    if (trimmed === "") {
      reasons.push(`${setting} is empty for the ${configurationName} configuration.`);
    } else if (isPlaceholderAPIKey(trimmed)) {
      reasons.push(
        `${setting} is still the ${PLACEHOLDER_API_KEY_PREFIX} placeholder "${trimmed}" ` +
          `for the ${configurationName} configuration.`
      );
    } else if (trimmed.startsWith("$(")) {
      reasons.push(
        `${setting} is the unexpanded reference "${trimmed}" for the ${configurationName} configuration.`
      );
    }
  }

  return reasons;
}
