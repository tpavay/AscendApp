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
  sellableProductIDs,
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
  const sellable = [...sellableProductIDs].sort();

  // The build's catalog is an upper bound, never an exact set. The hosted paywall changes without
  // a release, and a product Apple has not approved yet cannot be on it at all, so demanding
  // equality would refuse the very archive that has to ship before that product can be offered.
  // What must never happen is a paywall selling something this build's backend does not trust.
  if (actualProductIDs.length === 0) {
    errors.push("Active paywall offers no products.");
  }
  const unknownProductIDs = actualProductIDs.filter(
    (productID) => !sellable.includes(productID)
  );
  if (unknownProductIDs.length > 0) {
    errors.push(
      `Active paywall offers [${unknownProductIDs.join(", ")}], which this build's catalog ` +
        `[${sellable.join(", ")}] does not contain.`
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

const VIEWPORT_HEIGHT_UNITS = new Set(["dvh", "vh", "svh", "lvh", "%"]);
const CLIPPING_OVERFLOW = new Set(["hidden", "clip"]);

/**
 * Every hosted Superwall placement the app-access gate can present, so every one App Review can reach.
 * `paywall_decline` is the SDK's own event that chains the decline offer from the first paywall; the
 * app cannot register it, but the offer it opens is on screen at the gate all the same.
 * `app_launch_hard_gate` is an enum case the app never registers and `campaign_trigger` is Superwall's
 * default example trigger, so neither is held to the rule.
 */
export const GATE_PLACEMENTS = [
  "app_access_gate",
  "paywall_decline",
  "decline_offer_replay",
  "founder_letter"
];

/**
 * Every paywall a placement can open: any treatment with a share of its audience in any rule, because
 * which rule a climber matches, App Review's device included, decides which paywall opens. Paywalls
 * two placements share are returned once, naming both.
 */
export function servedPaywalls(staticConfig, placements) {
  const errors = [];
  const paywalls = new Map();

  for (const placement of placements) {
    const trigger = staticConfig.trigger_options?.find(
      (option) => option.event_name === placement
    );
    if (!trigger) {
      errors.push(`Superwall has no trigger_options entry for ${placement}.`);
      continue;
    }

    const identifiers = new Set(
      (trigger.rules ?? [])
        .flatMap((rule) => rule.variants ?? [])
        .filter(
          (variant) =>
            variant.variant_type === ACTIVE_VARIANT_TYPE &&
            Number(variant.percentage) > 0 &&
            variant.paywall_identifier
        )
        .map((variant) => String(variant.paywall_identifier))
    );
    if (identifiers.size === 0) {
      errors.push(`${placement} has no ${ACTIVE_VARIANT_TYPE} paywall variant above 0%.`);
      continue;
    }

    for (const identifier of identifiers) {
      const response = staticConfig.paywall_responses?.find(
        (candidate) => String(candidate.identifier) === identifier
      );
      if (!response) {
        errors.push(`${placement} points to missing paywall response ${identifier}.`);
        continue;
      }
      const served = paywalls.get(identifier) ?? {response, placements: []};
      served.placements.push(placement);
      paywalls.set(identifier, served);
    }
  }

  return {errors, paywalls: [...paywalls.values()]};
}

/**
 * Holds every paywall the gate can present to the compact-window rule. `loadRuntimeStore` reads one
 * paywall response's published runtime store. A finding is an error where `enforce` is set and a
 * warning elsewhere, and every finding names its placements and paywall.
 */
export async function validateCompactWindowLayouts({
  staticConfig,
  placements = GATE_PLACEMENTS,
  loadRuntimeStore,
  enforce
}) {
  const {errors: findings, paywalls} = servedPaywalls(staticConfig, placements);
  const evidence = [];

  for (const {response, placements: servedPlacements} of paywalls) {
    const label =
      `${servedPlacements.join(", ")} paywall ${response.id ?? response.identifier} ` +
      `(${response.identifier})`;
    let layout;
    try {
      layout = compactWindowLayout(await loadRuntimeStore(response));
    } catch (error) {
      findings.push(`${label}: ${error.message}`);
      continue;
    }
    evidence.push({
      placements: servedPlacements,
      paywallIdentifier: response.identifier,
      responseID: response.id ?? null,
      compactWindowLayout: layout.verdict
    });
    if (layout.verdict === "clips" || layout.verdict === "unknown") {
      findings.push(`${label}: ${layout.message}`);
    }
  }

  return enforce
    ? {errors: findings, warnings: [], evidence}
    : {errors: [], warnings: findings, evidence};
}

/**
 * Whether a published paywall can cut off the controls a climber has to reach on a short window.
 *
 * Ascend is an iPhone app, so on an iPad it runs in the iPhone compatibility window, which is 375 by
 * 667 points, the same window an iPhone SE has. A paywall whose root is a fixed viewport height with
 * overflow hidden and nothing between it and those controls that scrolls has no way to show more
 * than that window holds: App Review found the Lifetime card, the purchase button, Restore, Terms
 * and Privacy cut off on an iPad Air 11-inch (M3) on 2026-11-19 (Guideline 4). The paywall needed
 * 834 points; its `Main` node was `100dvh`, `overflowY: hidden`, `scroll: none`.
 *
 * The controls are the purchase buttons, or on a paywall that sells nothing (the founder letter) the
 * controls that close it. This reads the layout, not the rendering, so it can only say the structure
 * clips or scrolls. `unknown` means the reader found no node tree or no control to judge, which a
 * frozen fixture has and a live paywall must not, so it is a finding wherever a clip would be.
 */
export function compactWindowLayout(runtimeStore) {
  const nodes = Object.entries(runtimeStore ?? {}).filter(
    ([key, value]) => key.startsWith("node:") && value && typeof value === "object"
  );
  const roots = nodes.filter(([, node]) => String(node.parentId ?? "").startsWith("page:"));
  if (roots.length === 0) {
    return {
      verdict: "unknown",
      message:
        "the runtime store has no node whose parent is a page, so its layout cannot be read and " +
        "it cannot be shown to scroll on a 667 pt window."
    };
  }

  const byID = new Map(nodes);
  const actions = collectActions(runtimeStore);
  const nodesCarrying = (type) => [
    ...new Set(
      actions
        .filter(({action}) => action.type === type)
        .map(({path}) => /^\$\.(node:[^.]+)/.exec(path)?.[1])
        .filter((id) => id && byID.has(id))
    )
  ];
  const purchaseNodeIDs = nodesCarrying("purchase");
  const targetNodeIDs = purchaseNodeIDs.length > 0 ? purchaseNodeIDs : nodesCarrying("close");
  if (targetNodeIDs.length === 0) {
    return {
      verdict: "unknown",
      message:
        "the runtime store has no node carrying a purchase or close action, so there is no control " +
        "to judge and it cannot be shown to scroll on a 667 pt window."
    };
  }
  const targets = purchaseNodeIDs.length > 0 ? "purchase button" : "close control";

  const ancestors = new Set();
  for (const id of targetNodeIDs) {
    for (let current = byID.get(id).parentId; current && byID.has(current); current = byID.get(current).parentId) {
      ancestors.add(current);
    }
  }

  const scrolls = [...ancestors].some((id) => nodeScrolls(byID.get(id)));
  if (scrolls) return {verdict: "scrolls", message: null};

  const clippingRoot = roots.find(([, node]) => ancestors.has(node.id) && rootClips(node));
  if (!clippingRoot) return {verdict: "fits", message: null};

  const [, root] = clippingRoot;
  const firstChild = nodes.find(([, node]) => node.parentId === root.id && ancestors.has(node.id))?.[1];
  const childStep = firstChild
    ? `, and give its child "${firstChild.name}" (${firstChild.id}) a minimum height of 100% instead of a height`
    : "";
  return {
    verdict: "clips",
    message:
      `root "${root.name}" (${root.id}) is a fixed viewport height with overflow hidden and nothing ` +
      `between it and the ${targets} scrolls, so a window shorter than the content (an iPhone SE or ` +
      `an iPhone app on an iPad is 667 pt tall) cuts the bottom of the page off with no way to reach ` +
      `it. In the Superwall editor set "${root.name}" to Overflow Y auto with stack Scroll normal` +
      `${childStep}. Every hosted placement the gate presents is held to this ` +
      `(docs/superwall-paywall-setup.md, "Short windows").`
  };
}

function nodeProperty(node, name) {
  const candidate = node?.properties?.[name] ?? node?.defaultProperties?.[name];
  return candidate?.type === "literal" ? candidate.value : undefined;
}

function overflowY(node) {
  return nodeProperty(node, "css:overflowY")?.value;
}

function heightIsBounded(node) {
  const height = nodeProperty(node, "css:height");
  return (
    height?.type === "css-length" &&
    height.unit !== "none" &&
    Number.isFinite(Number(height.value))
  );
}

function nodeScrolls(node) {
  if (!heightIsBounded(node)) return false;
  const stack = nodeProperty(node, "prop:stack");
  const own = overflowY(node);
  // `scroll: normal` only scrolls while the node's own Overflow Y is not hidden or clip, because the
  // node's inline overflow wins over the class the scroll setting adds.
  if (stack?.scroll === "normal" && stack?.axis === "y" && !CLIPPING_OVERFLOW.has(own)) return true;
  return own === "auto" || own === "scroll";
}

function rootClips(node) {
  const height = nodeProperty(node, "css:height");
  const fixedToViewport =
    height?.type === "css-length" &&
    VIEWPORT_HEIGHT_UNITS.has(height.unit) &&
    Number(height.value) >= 100;
  return fixedToViewport && CLIPPING_OVERFLOW.has(overflowY(node));
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
