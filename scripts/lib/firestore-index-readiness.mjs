const READY_STATE = "READY";
const CREATING_STATE = "CREATING";
const MISSING_STATE = "MISSING";
const UNSPECIFIED_STATE = "STATE_UNSPECIFIED";
const UNEXPECTED_STATE = "UNEXPECTED";

export function evaluateFirestoreIndexReadiness(config, deployedState) {
  validateConfig(config);
  validateDeployedState(deployedState);

  const issues = [];

  for (const required of config.indexes) {
    const deployed = deployedState.indexes.find((candidate) =>
      compositeMatches(candidate, required)
    );
    const state = deployed === undefined ? MISSING_STATE :
      deployed.state ?? UNSPECIFIED_STATE;

    if (state !== READY_STATE) {
      issues.push({
        kind: "composite",
        signature: compositeSignature(required),
        state,
        pending: state === CREATING_STATE,
      });
    }
  }

  for (const required of config.fieldOverrides) {
    const deployed = deployedState.fieldOverrides.find((candidate) =>
      candidate.collectionGroup === required.collectionGroup &&
      candidate.fieldPath === required.fieldPath
    );

    // An override that declares no indexes disables single-field indexing, so
    // its per-index loops below iterate nothing. Without this the whole
    // override could be absent from Firestore and still report READY.
    if (deployed === undefined) {
      issues.push({
        kind: "fieldOverride",
        signature: fieldOverrideResourceSignature(required),
        state: MISSING_STATE,
        pending: false,
      });
    }

    for (const requiredIndex of required.indexes) {
      const deployedIndex = deployed?.indexes.find((candidate) =>
        fieldIndexMatches(candidate, requiredIndex)
      );
      const state = deployedIndex === undefined ? MISSING_STATE :
        deployedIndex.state ?? UNSPECIFIED_STATE;

      if (state !== READY_STATE) {
        issues.push({
          kind: "fieldOverride",
          signature: fieldOverrideIndexSignature(required, requiredIndex),
          state,
          pending: state === CREATING_STATE,
        });
      }
    }

    for (const deployedIndex of deployed?.indexes ?? []) {
      const isDeclared = required.indexes.some((candidate) =>
        fieldIndexMatches(deployedIndex, candidate)
      );
      if (!isDeclared) {
        issues.push({
          kind: "fieldOverride",
          signature: fieldOverrideIndexSignature(required, deployedIndex),
          state: `${UNEXPECTED_STATE} (` +
            `${deployedIndex.state ?? UNSPECIFIED_STATE})`,
          pending: false,
        });
      }
    }
  }

  return {
    ready: issues.length === 0,
    issues,
    compositeCount: config.indexes.length,
    fieldOverrideCount: config.fieldOverrides.length,
  };
}

export function formatFirestoreIndexIssues(issues) {
  return issues.map((issue) => `- ${issue.signature}: ${issue.state}`).join("\n");
}

// Only CREATING resolves on its own. A missing, unexpected, repair-needed or
// unspecified index is a definition mismatch that outlasts any timeout, so the
// caller must fail it as a verification error instead of burning the window.
export function structuralFirestoreIndexIssues(issues) {
  return issues.filter((issue) => issue.pending !== true);
}

function validateConfig(config) {
  if (!Array.isArray(config?.indexes)) {
    throw new Error("Firestore index config does not contain an indexes array");
  }
  if (!Array.isArray(config?.fieldOverrides)) {
    throw new Error(
      "Firestore index config does not contain a fieldOverrides array"
    );
  }

  for (const index of config.indexes) {
    if (
      typeof index.collectionGroup !== "string" ||
      typeof index.queryScope !== "string" ||
      !Array.isArray(index.fields)
    ) {
      throw new Error(`Unsupported Firestore index: ${JSON.stringify(index)}`);
    }
  }

  for (const fieldOverride of config.fieldOverrides) {
    if (
      typeof fieldOverride.collectionGroup !== "string" ||
      typeof fieldOverride.fieldPath !== "string" ||
      !Array.isArray(fieldOverride.indexes)
    ) {
      throw new Error(
        `Unsupported Firestore field override: ${JSON.stringify(fieldOverride)}`
      );
    }
  }
}

function validateDeployedState(deployedState) {
  if (!Array.isArray(deployedState?.indexes)) {
    throw new Error("Deployed Firestore state does not contain an indexes array");
  }
  if (!Array.isArray(deployedState?.fieldOverrides)) {
    throw new Error(
      "Deployed Firestore state does not contain a fieldOverrides array"
    );
  }
}

function compositeMatches(deployed, required) {
  return deployed.collectionGroup === required.collectionGroup &&
    deployed.queryScope === required.queryScope &&
    JSON.stringify(normalizedCompositeFields(deployed.fields)) ===
      JSON.stringify(normalizedCompositeFields(required.fields));
}

function normalizedCompositeFields(fields) {
  if (!Array.isArray(fields)) {
    return [];
  }

  const normalized = fields.map((field) => ({
    fieldPath: field.fieldPath,
    ...fieldMode(field),
  }));
  const last = normalized.at(-1);

  if (last?.fieldPath !== "__name__") {
    const lastDirectional = [...normalized]
      .reverse()
      .find((field) => typeof field.order === "string");
    normalized.push({
      fieldPath: "__name__",
      order: lastDirectional?.order ?? "ASCENDING",
    });
  }

  return normalized;
}

function fieldMode(field) {
  for (const key of ["order", "arrayConfig", "vectorConfig", "searchConfig"]) {
    if (field?.[key] !== undefined) {
      return {[key]: field[key]};
    }
  }
  throw new Error(`Unsupported Firestore index field: ${JSON.stringify(field)}`);
}

function fieldIndexMatches(deployed, required) {
  return deployed.queryScope === required.queryScope &&
    deployed.order === required.order &&
    deployed.arrayConfig === required.arrayConfig;
}

function compositeSignature(index) {
  return `composite (${index.collectionGroup}) -- ${index.fields
    .map(fieldToken)
    .join(" ")}`;
}

function fieldOverrideResourceSignature(fieldOverride) {
  return `field override [${fieldOverride.collectionGroup}.` +
    `${fieldOverride.fieldPath}] -- resource`;
}

function fieldOverrideIndexSignature(fieldOverride, index) {
  return `field override [${fieldOverride.collectionGroup}.` +
    `${fieldOverride.fieldPath}] -- (${fieldOverrideMode(index)},` +
    `${index.queryScope})`;
}

function fieldToken(field) {
  const mode = field.order ?? field.arrayConfig;
  if (typeof field.fieldPath !== "string" || typeof mode !== "string") {
    throw new Error(`Unsupported Firestore index field: ${JSON.stringify(field)}`);
  }
  return `(${field.fieldPath},${mode})`;
}

function fieldOverrideMode(index) {
  const mode = index.order ?? index.arrayConfig;
  if (typeof mode !== "string") {
    throw new Error(
      `Unsupported Firestore field override index: ${JSON.stringify(index)}`
    );
  }
  return mode;
}
