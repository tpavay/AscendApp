/**
 * Pure helpers for reasoning about a Remote Config template, split out from
 * `scripts/deploy-remote-config.mjs` so the "do not clobber a live kill switch" rule is
 * testable without a Firebase project.
 */

import {isDeepStrictEqual} from "node:util";

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
 *
 * Unwrapping once, here, is what lets every other reader below reach `conditions`,
 * `parameterGroups` and `version` as safely as it reaches `parameters` - a template whose
 * envelope was only stripped for one of those fields would publish an empty condition list
 * over a live one.
 */
export function unwrapTemplate(template) {
  if (template?.parameters !== undefined) {
    return template;
  }
  if (template?.result !== undefined) {
    return template.result;
  }
  return template ?? {};
}

export function templateParameters(template) {
  return unwrapTemplate(template)?.parameters ?? {};
}

export function templateConditions(template) {
  return unwrapTemplate(template)?.conditions ?? [];
}

export function templateParameterGroups(template) {
  return unwrapTemplate(template)?.parameterGroups ?? {};
}

/**
 * The live template's version number, which the backend increments on every publish.
 *
 * This is the only evidence an outside caller has that nothing was published between reading
 * a template and replacing it. Remote Config's publish API is a full replace, and the pinned
 * CLI re-fetches the ETag immediately before its own PUT, so `If-Match` cannot carry a
 * caller's read across that gap - see `publish-new-kill-switches.mjs`. A project that has
 * never been published carries no version at all, which is `null` rather than 0.
 */
export function templateVersionNumber(template) {
  const raw = unwrapTemplate(template)?.version?.versionNumber;
  if (raw === undefined || raw === null || raw === "") {
    return null;
  }
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : null;
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

/**
 * Where the checked-in template and `RemoteFeatureFlag.swift` disagree.
 *
 * Both directions are defects and neither is visible at runtime: a flag the app reads with no
 * parameter behind it is a switch nobody can flip, and a parameter no code reads is a switch
 * that does nothing when someone flips it mid-incident. This is the one thing about a new kill
 * switch that can be checked with no backend at all, which is what makes it the useful
 * assertion on a pull request - the flag is, by definition, not published yet there.
 */
export function flagParityProblems(localTemplate, swiftSource) {
  const appKeys = appFlagKeys(swiftSource);

  if (appKeys.length === 0) {
    return [
      "Parsed no flag keys out of RemoteFeatureFlag.swift. Passing here would mean asserting " +
        "nothing, which is how this class of gap opens in the first place.",
    ];
  }

  const templateKeys = Object.keys(templateParameters(localTemplate)).sort();

  return [
    ...appKeys
      .filter((key) => !templateKeys.includes(key))
      .map(
        (key) =>
          `${key} is read by the app but carries no parameter in remoteconfig.template.json - ` +
          "nothing would ever be published, so the switch could never be flipped.",
      ),
    ...templateKeys
      .filter((key) => !appKeys.includes(key))
      .map(
        (key) =>
          `${key} is in remoteconfig.template.json but no case in RemoteFeatureFlag.swift ` +
          "reads it - flipping it mid-incident would change nothing.",
      ),
  ];
}

/**
 * Where the checked-in template departs from the shape every kill switch must have.
 *
 * The template is the *healthy* state, so every parameter ships on: a checked-in `false` would
 * publish a project into the disabled state the switch exists to reach deliberately.
 */
export function templateShapeProblems(localTemplate) {
  const parameters = templateParameters(localTemplate);

  if (Object.keys(parameters).length === 0) {
    return ["remoteconfig.template.json declares no parameters."];
  }

  return Object.entries(parameters).flatMap(([key, parameter]) => {
    const problems = [];

    if (parameter?.valueType !== "BOOLEAN") {
      problems.push(`${key} must be declared BOOLEAN, not ${parameter?.valueType ?? "untyped"}.`);
    }
    if (parameter?.defaultValue?.value !== "true") {
      problems.push(
        `${key} must ship on - the checked-in template is the healthy state, and publishing a ` +
          "checked-in false would disable a path nobody chose to disable.",
      );
    }
    if (!(parameter?.description?.length > 0)) {
      problems.push(`${key} needs a description saying what turning it off stops.`);
    }

    return problems;
  });
}

/**
 * The switches a change adds to, and removes from, the checked-in template.
 *
 * Removals are worth naming on their own: nothing deletes a parameter from a live project, so a
 * switch dropped from this file stays in three consoles until somebody removes it by hand.
 */
export function killSwitchChanges(baseTemplate, currentTemplate) {
  const baseKeys = Object.keys(templateParameters(baseTemplate)).sort();
  const currentKeys = Object.keys(templateParameters(currentTemplate)).sort();

  return {
    added: currentKeys.filter((key) => !baseKeys.includes(key)),
    removed: baseKeys.filter((key) => !currentKeys.includes(key)),
  };
}

/** The fields that make a live parameter differ from the checked-in one in a way worth saying. */
function parameterDrift(key, liveParameter, localParameter) {
  const describe = (value) => (value === undefined ? "nothing" : JSON.stringify(value));
  const drift = [];

  if (liveParameter?.defaultValue?.value !== localParameter?.defaultValue?.value) {
    drift.push(
      `${key}: the live default is ${describe(liveParameter?.defaultValue?.value)}, the ` +
        `checked-in default is ${describe(localParameter?.defaultValue?.value)}.`,
    );
  }
  if (liveParameter?.valueType !== localParameter?.valueType) {
    drift.push(
      `${key}: the live type is ${describe(liveParameter?.valueType)}, the checked-in type is ` +
        `${describe(localParameter?.valueType)}.`,
    );
  }
  if (liveParameter?.description !== localParameter?.description) {
    drift.push(`${key}: the live description differs from the checked-in one.`);
  }

  return drift;
}

/**
 * Every managed key the live template holds inside a parameter group rather than at the top
 * level. `templateParameters` only reads the top level, so such a key looks absent to every
 * check here - and an additive publish would "add" a second copy of a parameter that already
 * exists. Nobody has ever created a group in any Ascend project; if one appears, a human
 * decides what it means rather than an automated publish guessing.
 */
function managedKeysInsideParameterGroups(liveTemplate, managedKeys) {
  return Object.entries(templateParameterGroups(liveTemplate))
    .flatMap(([groupName, group]) =>
      Object.keys(group?.parameters ?? {})
        .filter((key) => managedKeys.includes(key))
        .map((key) => `${key} lives inside the live parameter group "${groupName}"`),
    )
    .sort();
}

/**
 * The live template with the checked-in parameters it has never held added to it.
 *
 * This is the first of the two layers that make an automated publish additive, and it is the
 * one that holds unconditionally: the payload is built from the LIVE template, so an existing
 * parameter - value, type, description and all - is carried across verbatim and a checked-in
 * value is never written over a live one. Conditions and parameter groups come from the live
 * project for the same reason.
 *
 * Kept separate from `additivePublishPlan` so this property can be asserted on its own, in the
 * situation the plan refuses outright: a managed switch that is currently off.
 */
export function additiveMerge(liveTemplate, localTemplate) {
  const liveParameters = templateParameters(liveTemplate);
  const localParameters = templateParameters(localTemplate);
  const missingKeys = Object.keys(localParameters)
    .filter((key) => liveParameters[key] === undefined)
    .sort();

  return {
    missingKeys,
    mergedTemplate: {
      conditions: structuredClone(templateConditions(liveTemplate)),
      parameterGroups: structuredClone(templateParameterGroups(liveTemplate)),
      parameters: {
        ...structuredClone(liveParameters),
        ...Object.fromEntries(
          missingKeys.map((key) => [key, structuredClone(localParameters[key])]),
        ),
      },
    },
  };
}

/**
 * What an automated, strictly additive publish would do to one project - and every reason it
 * must not run.
 *
 * The first layer is `additiveMerge` above: the payload is built from the live template, so
 * there is no code path that writes a checked-in value over a live one.
 *
 * `refusals` is the second, and it exists because the publish API is a full replace: the
 * payload necessarily restates every live parameter, so a flip that lands between the read and
 * the write would be undone by a payload that was correct when it was built. Rather than race
 * that, an automated run refuses to write anything at all while any managed switch is off. A
 * human with the full picture can still publish by hand.
 */
export function additivePublishPlan(liveTemplate, localTemplate) {
  const liveParameters = templateParameters(liveTemplate);
  const localParameters = templateParameters(localTemplate);
  const managedKeys = Object.keys(localParameters).sort();

  const {missingKeys, mergedTemplate} = additiveMerge(liveTemplate, localTemplate);
  const activeKillSwitches = findActiveKillSwitches(liveTemplate, localTemplate);
  const groupedKeys = managedKeysInsideParameterGroups(liveTemplate, managedKeys);
  const driftReports = managedKeys
    .filter((key) => liveParameters[key] !== undefined)
    .flatMap((key) => parameterDrift(key, liveParameters[key], localParameters[key]));

  const refusals = [];

  if (groupedKeys.length > 0) {
    refusals.push(
      `The live template nests managed switches in parameter groups (${groupedKeys.join("; ")}). ` +
        "An additive publish cannot tell an existing switch from a missing one there, so it " +
        "reports rather than guesses.",
    );
  }

  if (missingKeys.length > 0 && activeKillSwitches.length > 0) {
    refusals.push(
      `${activeKillSwitches.join(", ")} ${activeKillSwitches.length === 1 ? "is" : "are"} ` +
        "currently OFF. Publishing restates every live parameter, so an automated run will not " +
        "write while a switch is in use - the incident it is stopping outranks a new flag.",
    );
  }

  return {
    managedKeys,
    missingKeys,
    activeKillSwitches,
    driftReports,
    refusals,
    // Withheld rather than merely flagged, so a caller that skips the refusals has nothing to
    // publish instead of something plausible.
    mergedTemplate: refusals.length > 0 ? null : mergedTemplate,
  };
}

/**
 * The managed parameter keys the backend did not store exactly as they were published.
 *
 * Compared structurally, never textually. The REST API serialises a parameter in proto field
 * order - `defaultValue`, `conditionalValues`, `description`, `valueType` - which is not the
 * order the checked-in template writes it, so a key-order-sensitive comparison would report a
 * newly added switch as a failed publish every time and fail the deploy that had just succeeded.
 */
export function publishedParameterMismatches(liveTemplate, publishedTemplate) {
  const liveParameters = templateParameters(liveTemplate);

  return Object.entries(templateParameters(publishedTemplate))
    .filter(([key, parameter]) => !isDeepStrictEqual(liveParameters[key], parameter))
    .map(([key]) => key);
}

/**
 * Why a merged template is not the live template plus exactly the named additions.
 *
 * `additivePublishPlan` is already written to be additive; this proves it of the object that
 * is about to be sent, immediately before sending it. A publisher that trusts its own merge is
 * one refactor away from being a publisher that silently reconciles, and the thing it would
 * overwrite is the only undo a shipped binary has.
 */
export function additiveMergeViolations(liveTemplate, mergedTemplate, addedKeys) {
  if (mergedTemplate === null || mergedTemplate === undefined) {
    return ["There is no merged template to publish."];
  }

  const liveParameters = templateParameters(liveTemplate);
  const mergedParameters = templateParameters(mergedTemplate);
  const violations = [];

  for (const [key, parameter] of Object.entries(liveParameters)) {
    if (!isDeepStrictEqual(mergedParameters[key], parameter)) {
      violations.push(
        `${key} already exists in the project and the merged template would change it. ` +
          "An automated publish may only add.",
      );
    }
  }

  const expectedKeys = [...new Set([...Object.keys(liveParameters), ...addedKeys])].sort();
  const actualKeys = Object.keys(mergedParameters).sort();

  if (!isDeepStrictEqual(actualKeys, expectedKeys)) {
    violations.push(
      `The merged template would publish ${actualKeys.join(", ") || "nothing"} where only ` +
        `${expectedKeys.join(", ") || "nothing"} is accounted for.`,
    );
  }

  for (const key of addedKeys) {
    if (liveParameters[key] !== undefined) {
      violations.push(`${key} was counted as an addition but already exists in the project.`);
    }
  }

  if (!isDeepStrictEqual(mergedTemplate.conditions ?? [], templateConditions(liveTemplate))) {
    violations.push("The merged template would change the project's conditions.");
  }

  if (
    !isDeepStrictEqual(mergedTemplate.parameterGroups ?? {}, templateParameterGroups(liveTemplate))
  ) {
    violations.push("The merged template would change the project's parameter groups.");
  }

  return violations;
}
