const ACTIVE_VARIANT_TYPE = "TREATMENT";

export function activePaywallResponse(staticConfig, placement) {
  const trigger = staticConfig.trigger_options?.find(
    (option) => option.event_name === placement
  );
  if (!trigger) {
    throw new Error(`Superwall has no trigger_options entry for ${placement}.`);
  }

  const variants = trigger.rules?.flatMap((rule) => rule.variants ?? []) ?? [];
  const treatment = variants.find(
    (variant) =>
      variant.variant_type === ACTIVE_VARIANT_TYPE && variant.percentage === 100
  );
  if (!treatment?.paywall_identifier) {
    throw new Error(
      `${placement} has no 100% ${ACTIVE_VARIANT_TYPE} paywall variant.`
    );
  }

  const response = staticConfig.paywall_responses?.find(
    (candidate) =>
      String(candidate.identifier) === String(treatment.paywall_identifier)
  );
  if (!response) {
    throw new Error(
      `${placement} points to missing paywall response ${treatment.paywall_identifier}.`
    );
  }

  return {trigger, treatment, response};
}

export function runtimeStoreFromHTML(html) {
  const pageContext = html.match(
    /<script[^>]*id=["']vike_pageContext["'][^>]*>([\s\S]*?)<\/script>/i
  )?.[1];
  if (!pageContext) {
    throw new Error("Superwall runtime has no vike_pageContext JSON script.");
  }

  let parsed;
  try {
    parsed = JSON.parse(pageContext);
  } catch {
    throw new Error("Superwall runtime vike_pageContext is not valid JSON.");
  }

  const store = parsed?.pageProps?.file?.store;
  if (!store || typeof store !== "object" || Array.isArray(store)) {
    throw new Error("Superwall runtime has no pageProps.file.store object.");
  }
  return store;
}

export function validateSuperwallArtifact({
  staticConfig,
  runtimeStore,
  placement,
  expectedProductIDs,
  expectedEntitlementID
}) {
  const errors = [];
  let selected;

  try {
    selected = activePaywallResponse(staticConfig, placement);
  } catch (error) {
    return {errors: [error.message], evidence: null};
  }

  const {treatment, response} = selected;
  const products = response.products_v2 ?? [];
  const actualProductIDs = products
    .map((product) => product.store_product?.product_identifier)
    .filter(Boolean)
    .sort();
  const configuredProductIDs = [...expectedProductIDs].sort();

  if (!sameValues(actualProductIDs, configuredProductIDs)) {
    errors.push(
      `Active paywall products are [${actualProductIDs.join(", ")}], expected ` +
        `[${configuredProductIDs.join(", ")}].`
    );
  }

  for (const product of products) {
    const productID = product.store_product?.product_identifier ?? "<missing product>";
    const entitlementIDs = (product.entitlements ?? [])
      .map((entitlement) => entitlement.identifier)
      .filter(Boolean)
      .sort();
    if (!sameValues(entitlementIDs, [expectedEntitlementID])) {
      errors.push(
        `${productID} grants [${entitlementIDs.join(", ")}], expected only ` +
          `${expectedEntitlementID}.`
      );
    }
  }

  let runtimeURL;
  try {
    runtimeURL = new URL(response.url);
    if (runtimeURL.protocol !== "https:") {
      errors.push("Active paywall runtime URL is not HTTPS.");
    }
    if (runtimeURL.hostname !== "user-content.superwalleditor.com") {
      errors.push(`Unexpected Superwall runtime host ${runtimeURL.hostname}.`);
    }
    if (!runtimeURL.searchParams.has("sw_cache_key")) {
      errors.push("Active paywall runtime URL is missing sw_cache_key.");
    }
  } catch {
    errors.push("Active paywall response has no valid runtime URL.");
  }

  const actions = collectActions(runtimeStore);
  const purchases = actions.filter(({action}) => action.type === "purchase");
  if (purchases.length !== 1) {
    errors.push(`Runtime has ${purchases.length} purchase actions, expected exactly one.`);
  }

  for (const {action, path} of purchases) {
    if (action.reference?.type !== "by-selected") {
      errors.push(`Purchase action ${path} does not purchase the selected product.`);
    }
    const completionActions = collectActions(action.onPurchase ?? []);
    if (!completionActions.some((candidate) => candidate.action.type === "close")) {
      errors.push(`Purchase action ${path} does not close after purchase completion.`);
    }
  }

  const stateKeys = new Set(
    Object.keys(runtimeStore).filter((key) => key.startsWith("state:"))
  );
  for (const {action, path} of actions) {
    if (action.type !== "set-state") continue;
    if (!stateKeys.has(action.stateId)) {
      errors.push(
        `State action ${path} references missing runtime state ${String(action.stateId)}.`
      );
    }
  }

  for (const {path, clickActions} of collectClickActionGroups(runtimeStore)) {
    const directTypes = clickActions.map((entry) => entry?.action?.type).filter(Boolean);
    if (directTypes.includes("purchase") && directTypes.includes("close")) {
      errors.push(`Purchase control ${path} also has a direct close action.`);
    }
  }

  return {
    errors,
    evidence: {
      buildID: staticConfig.build_id ?? null,
      placement,
      variantID: treatment.variant_id ?? null,
      paywallIdentifier: response.identifier,
      responseID: response.id ?? null,
      runtimeDocumentID: runtimeDocumentID(runtimeURL),
      productIDs: actualProductIDs,
      purchaseActionCount: purchases.length,
      stateReferenceCount: actions.filter(({action}) => action.type === "set-state").length,
      geometryValidation: "requires-rendered-device-canary"
    }
  };
}

export function collectActions(value) {
  const actions = [];
  walk(value, "$", (candidate, path) => {
    if (
      candidate &&
      typeof candidate === "object" &&
      typeof candidate.type === "string" &&
      ["purchase", "close", "set-state"].includes(candidate.type)
    ) {
      actions.push({action: candidate, path});
    }
  });
  return actions;
}

function collectClickActionGroups(value) {
  const groups = [];
  walk(value, "$", (candidate, path, key) => {
    if (key === "clickActions" && Array.isArray(candidate)) {
      groups.push({clickActions: candidate, path});
    }
  });
  return groups;
}

function walk(value, path, visit, key = null) {
  visit(value, path, key);
  if (!value || typeof value !== "object") return;

  if (Array.isArray(value)) {
    value.forEach((candidate, index) =>
      walk(candidate, `${path}[${index}]`, visit, String(index))
    );
    return;
  }

  for (const [childKey, candidate] of Object.entries(value)) {
    walk(candidate, `${path}.${childKey}`, visit, childKey);
  }
}

function sameValues(left, right) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

function runtimeDocumentID(url) {
  if (!url) return null;
  const segments = url.pathname.split("/").filter(Boolean);
  const documentIndex = segments.indexOf("document");
  return documentIndex >= 0 ? segments[documentIndex + 1] ?? null : null;
}
