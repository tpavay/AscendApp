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
