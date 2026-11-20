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
 * The app version as Superwall's `device.appVersionPadded` writes it: each of up to three numeric
 * components zero-padded to three digits, so a plain string comparison orders versions. Null when the
 * input is not a one to three component numeric version.
 */
export function paddedAppVersion(version) {
  const parts = String(version ?? "").trim().split(".");
  if (parts.length < 1 || parts.length > 3 || parts.some((part) => !/^\d{1,3}$/.test(part))) {
    return null;
  }
  while (parts.length < 3) parts.push("0");
  return parts.map((part) => part.padStart(3, "0")).join(".");
}

const ENTITLEMENT_CONJUNCT = /^size\(device\.activeEntitlements\) == 0$/;
const VERSION_CONJUNCT = /^device\.appVersionPadded (>=|>|<=|<|==|!=) "(\d{3}\.\d{3}\.\d{3})"$/;

function stripOuterParens(text) {
  let result = text.trim();
  while (result.startsWith("(") && result.endsWith(")")) {
    let depth = 0;
    let wraps = true;
    for (let index = 0; index < result.length - 1; index += 1) {
      if (result[index] === "(") depth += 1;
      if (result[index] === ")") depth -= 1;
      if (depth === 0) {
        wraps = false;
        break;
      }
    }
    if (!wraps) break;
    result = result.slice(1, -1).trim();
  }
  return result;
}

function splitTopLevelConjuncts(text) {
  const conjuncts = [];
  let depth = 0;
  let inString = false;
  let start = 0;
  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (character === '"') inString = !inString;
    if (inString) continue;
    if (character === "(") depth += 1;
    if (character === ")") depth -= 1;
    if (depth === 0 && text.startsWith("&&", index)) {
      conjuncts.push(text.slice(start, index));
      start = index + 2;
      index += 1;
    }
  }
  conjuncts.push(text.slice(start));
  return conjuncts.map(stripOuterParens);
}

function compareVersions(actual, operator, expected) {
  switch (operator) {
    case ">=": return actual >= expected;
    case ">": return actual > expected;
    case "<=": return actual <= expected;
    case "<": return actual < expected;
    case "==": return actual === expected;
    default: return actual !== expected;
  }
}

/**
 * What a campaign rule's audience does to an unentitled climber on `paddedVersion`: `matches` when
 * every condition is known and true, `excludes` when any app-version condition is known and false,
 * and `unknown` for anything else (a parameter, a country, a condition this parser has never seen).
 * Unknown is never read as safe: the rule stays reachable and does not shadow the rules after it.
 *
 * Only the entitlement condition every Ascend campaign carries and `device.appVersionPadded`
 * comparisons are understood, and the conjunction is read from `expression_cel` (Superwall's complete
 * condition), falling back to `expression` where a rule has no CEL form.
 */
export function ruleAudienceAtVersion(rule, paddedVersion) {
  const source = rule.expression_cel ?? rule.expression;
  if (source === null || source === undefined || String(source).trim() === "") return "matches";

  let state = "matches";
  for (const conjunct of splitTopLevelConjuncts(stripOuterParens(String(source)))) {
    if (ENTITLEMENT_CONJUNCT.test(conjunct)) continue;
    const version = VERSION_CONJUNCT.exec(conjunct);
    if (!version) {
      state = "unknown";
      continue;
    }
    if (!compareVersions(paddedVersion, version[1], version[2])) return "excludes";
  }
  return state;
}

/**
 * Splits a placement's rules, in the order Superwall evaluates them (first match wins), into the
 * ones an unentitled app at `paddedVersion` can reach and the ones it never can: a rule is shadowed
 * once an earlier rule certainly matches that version, and excluded when its own version condition
 * fails. Returns each rule's `audience` so callers can name the audience that still serves a paywall.
 */
export function reachableRules(rules, paddedVersion) {
  let shadowed = false;
  return (rules ?? []).map((rule) => {
    const audience = ruleAudienceAtVersion(rule, paddedVersion);
    const reachable = !shadowed && audience !== "excludes";
    if (reachable && audience === "matches") shadowed = true;
    return {rule, reachable};
  });
}

function describeAudience(rule) {
  const source = String(rule.expression_cel ?? rule.expression ?? "every climber");
  return source
    .replace(/\(?size\(device\.activeEntitlements\) == 0\)?( && )?/, "")
    .replaceAll("device.appVersionPadded", "app version")
    .trim() || "every unentitled climber";
}

/**
 * Every paywall a placement can open: any treatment with a share of its audience in any rule, because
 * which rule a climber matches, App Review's device included, decides which paywall opens. Paywalls
 * two placements share are returned once, naming both.
 *
 * With `appVersion` the rules are read the way Superwall reads them for an app at that version, and
 * each paywall carries `reachable`: true when some rule that version can reach serves it. A paywall
 * only older-version rules serve is returned with `reachable: false` and `servedBy` naming those
 * audiences, so a caller can hold the build under release to the rule without failing on what it never
 * shows. Without `appVersion` every paywall is reachable, as before.
 */
export function servedPaywalls(staticConfig, placements, {appVersion} = {}) {
  const errors = [];
  const paywalls = new Map();
  const paddedVersion = appVersion === undefined ? undefined : paddedAppVersion(appVersion);
  if (appVersion !== undefined && paddedVersion === null) {
    errors.push(`App version "${appVersion}" is not a one to three component numeric version.`);
    return {errors, paywalls: []};
  }

  for (const placement of placements) {
    const trigger = staticConfig.trigger_options?.find(
      (option) => option.event_name === placement
    );
    if (!trigger) {
      errors.push(`Superwall has no trigger_options entry for ${placement}.`);
      continue;
    }

    const rules =
      paddedVersion === undefined
        ? (trigger.rules ?? []).map((rule) => ({rule, reachable: true}))
        : reachableRules(trigger.rules, paddedVersion);
    const identifiers = new Map();
    for (const {rule, reachable} of rules) {
      for (const variant of rule.variants ?? []) {
        if (
          variant.variant_type !== ACTIVE_VARIANT_TYPE ||
          !(Number(variant.percentage) > 0) ||
          !variant.paywall_identifier
        ) {
          continue;
        }
        const identifier = String(variant.paywall_identifier);
        const entry = identifiers.get(identifier) ?? {reachable: false, servedBy: []};
        entry.reachable ||= reachable;
        if (!reachable) entry.servedBy.push(describeAudience(rule));
        identifiers.set(identifier, entry);
      }
    }
    if (identifiers.size === 0) {
      errors.push(`${placement} has no ${ACTIVE_VARIANT_TYPE} paywall variant above 0%.`);
      continue;
    }
    if (![...identifiers.values()].some(({reachable}) => reachable)) {
      errors.push(`${placement} serves no paywall to an app at version ${appVersion}.`);
    }

    for (const [identifier, {reachable, servedBy}] of identifiers) {
      const response = staticConfig.paywall_responses?.find(
        (candidate) => String(candidate.identifier) === identifier
      );
      if (!response) {
        errors.push(`${placement} points to missing paywall response ${identifier}.`);
        continue;
      }
      const served = paywalls.get(identifier) ?? {response, placements: [], reachable: false, servedBy: []};
      served.placements.push(placement);
      served.reachable ||= reachable;
      if (!reachable) served.servedBy.push(...servedBy);
      paywalls.set(identifier, served);
    }
  }

  return {errors, paywalls: [...paywalls.values()]};
}

/**
 * Holds every paywall the gate can present to the compact-window rule. `loadRuntimeStore` reads one
 * paywall response's published runtime store. A finding is an error where `enforce` is set and a
 * warning elsewhere, and every finding names its placements and paywall.
 *
 * `appVersion` is the version under release. A paywall that only rules excluding that version serve
 * is still read, but its finding is always a warning that names the audience still served: App Review
 * and every climber on the new build never see it. A paywall any reachable rule serves, or that no
 * rule can be proven to exclude, is held to the rule in full.
 */
export async function validateCompactWindowLayouts({
  staticConfig,
  placements = GATE_PLACEMENTS,
  loadRuntimeStore,
  enforce,
  appVersion
}) {
  const {errors: findings, paywalls} = servedPaywalls(staticConfig, placements, {appVersion});
  const shadowedFindings = [];
  const evidence = [];

  for (const {response, placements: servedPlacements, reachable, servedBy} of paywalls) {
    const label =
      `${servedPlacements.join(", ")} paywall ${response.id ?? response.identifier} ` +
      `(${response.identifier})`;
    const target = reachable ? findings : shadowedFindings;
    const audience = reachable
      ? ""
      : ` Not reachable from app ${appVersion}: only older-version rules still serve it ` +
        `(${[...new Set(servedBy)].join("; ")}), so it is a warning here and an error for any version that reaches it.`;
    let layout;
    try {
      layout = compactWindowLayout(await loadRuntimeStore(response));
    } catch (error) {
      target.push(`${label}: ${error.message}${audience ? `.${audience}` : ""}`);
      continue;
    }
    evidence.push({
      placements: servedPlacements,
      paywallIdentifier: response.identifier,
      responseID: response.id ?? null,
      compactWindowLayout: layout.verdict,
      ...(appVersion === undefined ? {} : {reachableFromAppVersion: reachable})
    });
    if (layout.verdict === "clips" || layout.verdict === "unknown") {
      target.push(`${label}: ${layout.message}${audience}`);
    }
  }

  return enforce
    ? {errors: findings, warnings: shadowedFindings, evidence}
    : {errors: [], warnings: [...findings, ...shadowedFindings], evidence};
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
