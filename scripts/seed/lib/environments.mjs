import {readFileSync} from "node:fs";
import {resolve} from "node:path";

export const DEV_PROJECT_ID = "ascend-f2e4f";
export const STAGING_PROJECT_ID = "ascend-staging-fa7d5";
export const PRODUCTION_PROJECT_ID = "ascend-prod-9c8f2";

export const SEEDABLE_PROJECT_IDS = new Set([
  DEV_PROJECT_ID,
  STAGING_PROJECT_ID,
]);

export function resolveProjectId(projectOrAlias, repoRoot) {
  if (SEEDABLE_PROJECT_IDS.has(projectOrAlias) || projectOrAlias === PRODUCTION_PROJECT_ID) {
    return projectOrAlias;
  }

  const rc = JSON.parse(readFileSync(resolve(repoRoot, ".firebaserc"), "utf-8"));
  return rc.projects?.[projectOrAlias] ?? projectOrAlias;
}

export function assertSeedableProject(projectId, verb = "write") {
  if (projectId === PRODUCTION_PROJECT_ID || !SEEDABLE_PROJECT_IDS.has(projectId)) {
    throw new Error(
      `Refusing to ${verb} ${projectId}. Only ${DEV_PROJECT_ID} and ${STAGING_PROJECT_ID} are allowed.`
    );
  }
}

export function seedEnvironmentName(projectId) {
  if (projectId === DEV_PROJECT_ID) return "dev";
  if (projectId === STAGING_PROJECT_ID) return "staging";
  if (projectId === PRODUCTION_PROJECT_ID) return "production";
  return "unknown";
}

export function defaultSeedPackId(target, projectId) {
  return `${target}-v1-${seedEnvironmentName(projectId)}`;
}
