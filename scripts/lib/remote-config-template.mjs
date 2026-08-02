/**
 * Pure helpers for reasoning about a Remote Config template, split out from
 * `scripts/deploy-remote-config.mjs` so the "do not clobber a live kill switch" rule is
 * testable without a Firebase project.
 */

/**
 * Firebase stores parameter values as strings, so a flipped switch comes back off the wire
 * as the string "false", not the boolean. Anything that is not recognisably false - a
 * missing parameter, an empty value, a typo - is treated as "not off", because the caller
 * uses this to decide whether publishing would *undo* something, and guessing "off" there
 * would block routine deploys on a malformed entry.
 */
export function isParameterOff(parameter) {
  return String(parameter?.defaultValue?.value ?? "").trim().toLowerCase() === "false";
}

/**
 * `firebase remoteconfig:get --json` has shipped both a bare template and one wrapped in a
 * `result` envelope. Accept either rather than depending on which the pinned CLI emits.
 */
export function templateParameters(template) {
  return template?.parameters ?? template?.result?.parameters ?? {};
}

/**
 * The managed flags that are currently switched off in the live project - the ones
 * republishing the checked-in template would silently switch back on.
 */
export function findActiveKillSwitches(liveTemplate, localTemplate) {
  const liveParameters = templateParameters(liveTemplate);
  return Object.keys(templateParameters(localTemplate))
    .filter((key) => isParameterOff(liveParameters[key]))
    .sort();
}

/**
 * The Remote Config parameter keys the app actually reads, parsed out of
 * `RemoteFeatureFlag.swift`. The enum's raw values ARE the keys, so the Swift source is the
 * one authority on what the app looks for; deriving them keeps every check honest when a
 * flag is added.
 */
export function appFlagKeys(swiftSource) {
  return [...swiftSource.matchAll(/^\s*case\s+\w+\s*=\s*"([a-z0-9_]+)"/gm)]
    .map((match) => match[1])
    .sort();
}

/**
 * Why a live Remote Config template cannot serve the flags this build reads.
 *
 * A flag whose parameter does not exist on the backend is not "off" and is not "on" - it is
 * *unreachable*. The client falls through to `shippedDefault`, the app behaves completely
 * normally, and nobody discovers it until an operator opens the console mid-incident and
 * finds nothing to flip. That silence is the whole failure mode, so this reports on the
 * template's *shape*, never on its values: a switch an operator has deliberately turned off
 * is the mechanism working, and must never be mistaken for a problem.
 *
 * "Unreachable" is wider than "absent". The condition the client actually cares about is
 * `RemoteConfigValue.source == .remote`, which is the single thing
 * `FirebaseRemoteFeatureFlagSource.remoteSourcedValues()` requires before a value counts. A
 * parameter published with "use in-app default", or one carrying only conditional values with
 * no default at all, leaves that source `.static` for a client matching no condition - the
 * key is in the console, looks configured, and still resolves to `shippedDefault`.
 *
 * Parameters the app does not know about are ignored - the backend is allowed to carry keys
 * for other app versions.
 */
export function unpublishedFlagProblems(liveTemplate, appKeys) {
  const liveParameters = templateParameters(liveTemplate);

  return appKeys.flatMap((key) => {
    const parameter = liveParameters[key];

    if (parameter === undefined) {
      return [
        `${key} is missing from the live template - this build's kill switch is decorative.`,
      ];
    }

    if (parameter.defaultValue?.useInAppDefault === true) {
      return [
        `${key} is published with "use in-app default" - the backend deliberately supplies no ` +
          "value, so the client resolves it from the shipped default and the switch is decorative.",
      ];
    }

    if (parameter.defaultValue?.value === undefined) {
      const only = parameter.conditionalValues ? " only conditional values and" : "";
      return [
        `${key} is published with${only} no default value - a client matching no condition ` +
          "receives nothing from the backend and falls back to the shipped default.",
      ];
    }

    // Not a claim that the current value is inert: the client reads `stringValue` and never
    // inspects `valueType`, so a STRING "false" would in fact be honoured. The template
    // declares BOOLEAN, and that declaration is what keeps a value the client's strict parser
    // would drop from ever reaching the parameter in the first place.
    if (parameter.valueType !== "BOOLEAN") {
      return [
        `${key} is published as ${parameter.valueType ?? "an untyped parameter"}, not the ` +
          "BOOLEAN the template declares - the console type is what stops a value the client's " +
          "strict parser would drop from being saved against this switch.",
      ];
    }

    return [];
  });
}
