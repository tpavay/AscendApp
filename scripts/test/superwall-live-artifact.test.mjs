import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";

import {
  activePaywallResponse,
  collectActions,
  compactWindowLayout,
  GATE_PLACEMENTS,
  runtimeStoreFromHTML,
  servedPaywalls,
  validateCompactWindowLayouts,
  validateSuperwallArtifact
} from "../lib/superwall-live-artifact.mjs";

const stagingFixture = new URL(
  "./fixtures/superwall/staging-app-access-gate-v1.json",
  import.meta.url
);
const productionFixture = new URL(
  "./fixtures/superwall/production-app-access-gate-v1.json",
  import.meta.url
);

async function fixture(url) {
  return JSON.parse(await readFile(url, "utf8"));
}

function validate(capture, productIDs) {
  return validateSuperwallArtifact({
    staticConfig: capture.staticConfig,
    runtimeStore: capture.runtimeStore,
    placement: "app_access_gate",
    sellableProductIDs: productIDs,
    expectedEntitlementID: "app_access"
  });
}

test("versioned staging capture detects the published malformed abandon state", async () => {
  const capture = await fixture(stagingFixture);
  assert.equal(capture.schemaVersion, 1);

  const result = validate(capture, ["ascend_staging_yearly", "ascend_staging_monthly"]);

  assert.deepEqual(result.errors, [
    "State action $.node:purchase.properties.prop:click-behavior.value.clickActions[0].action.onAbandon[0].action references missing runtime state state:."
  ]);
  assert.equal(result.evidence.responseID, "249435");
  assert.equal(result.evidence.runtimeDocumentID, "pj6GhBq8K0IxskBJ7ui6z");
});

test("versioned production capture also detects entitlement drift", async () => {
  const capture = await fixture(productionFixture);
  const result = validate(capture, ["ascend_yearly", "ascend_monthly"]);

  assert.deepEqual(result.errors, [
    "ascend_yearly grants [ascend_membership], expected only app_access.",
    "ascend_monthly grants [ascend_membership], expected only app_access.",
    "State action $.node:purchase.properties.prop:click-behavior.value.clickActions[0].action.onAbandon[0].action references missing runtime state state:."
  ]);
  assert.equal(result.evidence.responseID, "232372");
  assert.equal(result.evidence.runtimeDocumentID, "odpvyL4GHznbb1E4cghT4");
});

test("a repaired active artifact satisfies the full purchase contract", async () => {
  const capture = structuredClone(await fixture(productionFixture));
  const response = activePaywallResponse(
    capture.staticConfig,
    "app_access_gate"
  ).response;
  for (const product of response.products_v2) {
    product.entitlements = [{identifier: "app_access"}];
  }
  capture.runtimeStore["state:purchaseAbandoned"] = {};
  capture.runtimeStore["node:purchase"].properties[
    "prop:click-behavior"
  ].value.clickActions[0].action.onAbandon[0].action.stateId = "state:purchaseAbandoned";

  const result = validate(capture, ["ascend_yearly", "ascend_monthly"]);

  assert.deepEqual(result.errors, []);
  assert.equal(result.evidence.purchaseActionCount, 1);
  assert.equal(
    result.evidence.geometryValidation,
    "requires-rendered-device-canary"
  );
});

test("validator ignores an unused broken paywall response", async () => {
  const capture = structuredClone(await fixture(stagingFixture));
  capture.staticConfig.paywall_responses.push({
    id: "249327",
    identifier: "unused-response",
    products_v2: [],
    url: "not a URL"
  });
  capture.runtimeStore["state:"] = {};

  assert.deepEqual(
    validate(capture, ["ascend_staging_yearly", "ascend_staging_monthly"]).errors,
    []
  );
});

test("purchase and close cannot be sibling actions on one control", async () => {
  const capture = structuredClone(await fixture(stagingFixture));
  capture.runtimeStore["state:"] = {};
  capture.runtimeStore["node:purchase"].properties[
    "prop:click-behavior"
  ].value.clickActions.push({action: {type: "close"}});

  const result = validate(capture, [
    "ascend_staging_yearly",
    "ascend_staging_monthly"
  ]);

  assert.deepEqual(result.errors, [
    "Purchase control $.node:purchase.properties.prop:click-behavior.value.clickActions also has a direct close action."
  ]);
});

async function repairedStagingCapture() {
  const capture = structuredClone(await fixture(stagingFixture));
  capture.runtimeStore["state:"] = {};
  return capture;
}

const stagingCatalog = [
  "ascend_staging_yearly",
  "ascend_staging_lifetime",
  "ascend_staging_monthly"
];

test("a paywall offering part of the build's catalog passes", async () => {
  // Lifetime cannot be on a live paywall before Apple approves it, and Monthly can leave one
  // without a release, so the archive that ships Lifetime has to pass against a paywall that
  // offers less than the build can sell.
  const capture = await repairedStagingCapture();
  assert.deepEqual(validate(capture, stagingCatalog).errors, []);

  const {response} = activePaywallResponse(capture.staticConfig, "app_access_gate");
  response.products_v2 = response.products_v2.filter(
    (product) => product.store_product.product_identifier === "ascend_staging_yearly"
  );
  const yearlyOnly = validate(capture, stagingCatalog);
  assert.deepEqual(yearlyOnly.errors, []);
  assert.deepEqual(yearlyOnly.evidence.productIDs, ["ascend_staging_yearly"]);
});

test("a paywall selling a product outside the build's catalog fails", async () => {
  const capture = await repairedStagingCapture();

  assert.deepEqual(validate(capture, ["ascend_staging_yearly"]).errors, [
    "Active paywall offers [ascend_staging_monthly], which this build's catalog " +
      "[ascend_staging_yearly] does not contain."
  ]);
});

test("a paywall offering nothing fails", async () => {
  const capture = await repairedStagingCapture();
  activePaywallResponse(capture.staticConfig, "app_access_gate").response.products_v2 = [];

  assert.deepEqual(validate(capture, stagingCatalog).errors, [
    "Active paywall offers no products."
  ]);
});

test("runtime parser reads the exact Editor store and rejects missing context", () => {
  const store = {"state:selected": {value: "yearly"}};
  const html = `<script id="vike_pageContext" type="application/json">${JSON.stringify({
    pageProps: {file: {store}}
  })}</script>`;

  assert.deepEqual(runtimeStoreFromHTML(html), store);
  assert.throws(
    () => runtimeStoreFromHTML("<html></html>"),
    /no vike_pageContext JSON script/
  );
});

// A paywall's layout, reduced to the properties the compact-window rule reads. The shapes are the
// ones the live artifact serialises: literal property wrappers, `css-length` and `css-string` values.
const literal = (value) => ({type: "literal", value});
const length = ({value, unit}) => literal({type: "css-length", value, unit});
const overflow = (value) => literal({type: "css-string", value});
const purchaseBehavior = literal({
  type: "click-behavior",
  clickActions: [{action: {type: "purchase", reference: {type: "by-selected"}, onPurchase: [{action: {type: "close"}}]}}]
});
const closeBehavior = literal({type: "click-behavior", clickActions: [{action: {type: "close"}}]});

function layoutStore({
  rootHeight,
  rootOverflowY,
  rootScroll = "none",
  childHeight = {value: "100", unit: "%"},
  childOverflowY,
  targetOverflowY,
  targetBehavior = purchaseBehavior
}) {
  return {
    "node:main": {
      id: "node:main",
      name: "Main",
      parentId: "page:page",
      type: "stack",
      defaultProperties: {
        "prop:stack": literal({type: "property-stack", axis: "y", scroll: rootScroll}),
        "css:height": length(rootHeight),
        "css:overflowY": overflow(rootOverflowY)
      },
      properties: {}
    },
    "node:overlay": {
      id: "node:overlay",
      name: "Overlay",
      parentId: "node:main",
      type: "stack",
      defaultProperties: {
        "css:height": length(childHeight),
        ...(childOverflowY ? {"css:overflowY": overflow(childOverflowY)} : {})
      },
      properties: {}
    },
    "node:target": {
      id: "node:target",
      name: "CTA",
      parentId: "node:overlay",
      type: "stack",
      defaultProperties: targetOverflowY ? {"css:overflowY": overflow(targetOverflowY)} : {},
      properties: {"prop:click-behavior": targetBehavior}
    }
  };
}

const clippingRoot = {rootHeight: {value: "100", unit: "dvh"}, rootOverflowY: "hidden"};
const docsRecipe = {
  rootHeight: {value: "100", unit: "dvh"},
  rootOverflowY: "auto",
  rootScroll: "normal",
  childHeight: {value: "auto", unit: "none"}
};

// App Review, 2026-11-19, iPad Air 11-inch (M3): the iPhone app gets a 375 by 667 pt window there,
// and the paywall's content needs 834 pt. The root was 100dvh, overflow hidden, scroll none.
test("a paywall fixed to the viewport with overflow hidden and no scroll clips the purchase button", () => {
  const verdict = compactWindowLayout(layoutStore(clippingRoot));

  assert.equal(verdict.verdict, "clips");
  assert.match(verdict.message, /root "Main" \(node:main\)/);
  assert.match(verdict.message, /purchase button/);
  assert.match(verdict.message, /child "Overlay" \(node:overlay\)/);
});

test("scroll normal does not help while the node's own Overflow Y is still hidden", () => {
  const verdict = compactWindowLayout(layoutStore({...clippingRoot, rootScroll: "normal"}));

  assert.equal(verdict.verdict, "clips");
});

test("the recipe the docs prescribe scrolls on any window", () => {
  const verdict = compactWindowLayout(layoutStore(docsRecipe));

  assert.equal(verdict.verdict, "scrolls");
  assert.equal(verdict.message, null);
});

test("a root that grows with its content never clips", () => {
  const verdict = compactWindowLayout(
    layoutStore({rootHeight: {value: "auto", unit: "none"}, rootOverflowY: "hidden"})
  );

  assert.equal(verdict.verdict, "fits");
});

test("the purchase button scrolling itself does not reach it under a clipping root", () => {
  const verdict = compactWindowLayout(layoutStore({...clippingRoot, targetOverflowY: "auto"}));

  assert.equal(verdict.verdict, "clips");
});

test("a node between the root and the purchase button that grows with its content never scrolls", () => {
  const verdict = compactWindowLayout(
    layoutStore({...clippingRoot, childHeight: {value: "auto", unit: "none"}, childOverflowY: "auto"})
  );

  assert.equal(verdict.verdict, "clips");
});

test("a node between the root and the purchase button with a bounded height scrolls", () => {
  const verdict = compactWindowLayout(layoutStore({...clippingRoot, childOverflowY: "auto"}));

  assert.equal(verdict.verdict, "scrolls");
});

test("a paywall that sells nothing is judged by the controls that close it", () => {
  const clipping = compactWindowLayout(layoutStore({...clippingRoot, targetBehavior: closeBehavior}));
  assert.equal(clipping.verdict, "clips");
  assert.match(clipping.message, /close control/);

  const fixed = compactWindowLayout(layoutStore({...docsRecipe, targetBehavior: closeBehavior}));
  assert.equal(fixed.verdict, "scrolls");
});

test("a capture with no node tree is unknown, never an error", async () => {
  const capture = await fixture(productionFixture);

  assert.equal(compactWindowLayout(capture.runtimeStore).verdict, "unknown");
});

function gateConfig(triggers) {
  const identifiers = new Set(
    triggers.flatMap(({rules}) => rules.flat().map(({paywall}) => paywall))
  );
  return {
    trigger_options: triggers.map(({placement, rules}) => ({
      event_name: placement,
      rules: rules.map((variants) => ({
        variants: variants.map(({paywall, percentage = 100, type = "TREATMENT"}) => ({
          variant_type: type,
          percentage,
          paywall_identifier: paywall
        }))
      }))
    })),
    paywall_responses: [...identifiers].map((identifier) => ({id: identifier, identifier}))
  };
}

function storesByPaywall(stores) {
  return async (response) => {
    const store = stores[response.identifier];
    if (!store) throw new Error(`no runtime for ${response.identifier}`);
    return store;
  };
}

const everyGatePlacement = gateConfig([
  {placement: "app_access_gate", rules: [[{paywall: "first"}], [{paywall: "second"}]]},
  {placement: "paywall_decline", rules: [[{paywall: "decline"}]]},
  {placement: "decline_offer_replay", rules: [[{paywall: "decline"}]]},
  {placement: "founder_letter", rules: [[{paywall: "letter"}]]}
]);

test("every paywall any rule serves is checked, and a second rule's clipping paywall is named", async () => {
  const result = await validateCompactWindowLayouts({
    staticConfig: everyGatePlacement,
    loadRuntimeStore: storesByPaywall({
      first: layoutStore(docsRecipe),
      second: layoutStore(clippingRoot),
      decline: layoutStore(docsRecipe),
      letter: layoutStore({...docsRecipe, targetBehavior: closeBehavior})
    }),
    enforce: true
  });

  assert.equal(result.errors.length, 1);
  assert.match(result.errors[0], /^app_access_gate paywall second \(second\): root "Main"/);
  assert.deepEqual(
    result.evidence.map(({placements, paywallIdentifier, compactWindowLayout: verdict}) => [
      placements,
      paywallIdentifier,
      verdict
    ]),
    [
      [["app_access_gate"], "first", "scrolls"],
      [["app_access_gate"], "second", "clips"],
      [["paywall_decline", "decline_offer_replay"], "decline", "scrolls"],
      [["founder_letter"], "letter", "scrolls"]
    ]
  );
});

test("the decline offer and the founder letter are held to the rule too", async () => {
  const result = await validateCompactWindowLayouts({
    staticConfig: everyGatePlacement,
    loadRuntimeStore: storesByPaywall({
      first: layoutStore(docsRecipe),
      second: layoutStore(docsRecipe),
      decline: layoutStore(clippingRoot),
      letter: layoutStore({...clippingRoot, targetBehavior: closeBehavior})
    }),
    enforce: true
  });

  assert.equal(result.errors.length, 2);
  assert.match(result.errors[0], /^paywall_decline, decline_offer_replay paywall decline \(decline\): /);
  assert.match(result.errors[1], /^founder_letter paywall letter \(letter\): .*close control/);
});

test("only treatments with a share of the audience are served", () => {
  const {errors, paywalls} = servedPaywalls(
    gateConfig([
      {
        placement: "app_access_gate",
        rules: [[{paywall: "live"}, {paywall: "paused", percentage: 0}, {paywall: "held", type: "HOLDOUT"}]]
      }
    ]),
    ["app_access_gate"]
  );

  assert.deepEqual(errors, []);
  assert.deepEqual(paywalls.map(({response}) => response.identifier), ["live"]);
});

test("a gate placement missing from trigger_options is reported by name", async () => {
  const staticConfig = gateConfig([
    {placement: "app_access_gate", rules: [[{paywall: "first"}]]}
  ]);
  const result = await validateCompactWindowLayouts({
    staticConfig,
    loadRuntimeStore: storesByPaywall({first: layoutStore(docsRecipe)}),
    enforce: true
  });

  assert.deepEqual(result.errors, [
    "Superwall has no trigger_options entry for paywall_decline.",
    "Superwall has no trigger_options entry for decline_offer_replay.",
    "Superwall has no trigger_options entry for founder_letter."
  ]);
});

test("a runtime that cannot be read is a finding that names its placement and paywall", async () => {
  const result = await validateCompactWindowLayouts({
    staticConfig: gateConfig([{placement: "founder_letter", rules: [[{paywall: "letter"}]]}]),
    placements: ["founder_letter"],
    loadRuntimeStore: storesByPaywall({}),
    enforce: true
  });

  assert.deepEqual(result.errors, ["founder_letter paywall letter (letter): no runtime for letter"]);
});

test("the layout findings are errors only where they are enforced, and warnings elsewhere", async () => {
  const check = (enforce) =>
    validateCompactWindowLayouts({
      staticConfig: everyGatePlacement,
      loadRuntimeStore: storesByPaywall({
        first: layoutStore(clippingRoot),
        second: layoutStore(docsRecipe),
        decline: layoutStore(docsRecipe),
        letter: layoutStore({...docsRecipe, targetBehavior: closeBehavior})
      }),
      enforce
    });

  const strict = await check(true);
  assert.equal(strict.errors.length, 1);
  assert.match(strict.errors[0], /667 pt tall/);
  assert.deepEqual(strict.warnings, []);

  const lenient = await check(false);
  assert.deepEqual(lenient.errors, []);
  assert.deepEqual(lenient.warnings, strict.errors);
});

test("a paywall whose layout cannot be read is a finding, an error only where enforced", async () => {
  const unreadable = layoutStore(docsRecipe);
  delete unreadable["node:target"];
  const check = (enforce) =>
    validateCompactWindowLayouts({
      staticConfig: gateConfig([{placement: "founder_letter", rules: [[{paywall: "letter"}]]}]),
      placements: ["founder_letter"],
      loadRuntimeStore: storesByPaywall({letter: unreadable}),
      enforce
    });

  const strict = await check(true);
  assert.equal(strict.errors.length, 1);
  assert.match(strict.errors[0], /^founder_letter paywall letter \(letter\): .*no node carrying a purchase or close action/);
  assert.equal(strict.evidence[0].compactWindowLayout, "unknown");

  const lenient = await check(false);
  assert.deepEqual(lenient.errors, []);
  assert.deepEqual(lenient.warnings, strict.errors);
});

test("a root under any page is read, not only the first page", () => {
  const store = layoutStore(clippingRoot);
  store["node:main"].parentId = "page:checkout";

  assert.equal(compactWindowLayout(store).verdict, "clips");
});

test("a store with no node under a page is unknown with a reason", () => {
  const store = layoutStore(clippingRoot);
  store["node:main"].parentId = "node:elsewhere";

  const verdict = compactWindowLayout(store);
  assert.equal(verdict.verdict, "unknown");
  assert.match(verdict.message, /no node whose parent is a page/);
});

test("the clip message reads as clean sentences with a child to change and without one", () => {
  const tail =
    "is a fixed viewport height with overflow hidden and nothing between it and the purchase button " +
    "scrolls, so a window shorter than the content (an iPhone SE or an iPhone app on an iPad is 667 pt " +
    "tall) cuts the bottom of the page off with no way to reach it. In the Superwall editor set " +
    "\"Main\" to Overflow Y auto with stack Scroll normal";
  const rule =
    ". Every hosted placement the gate presents is held to this " +
    "(docs/superwall-paywall-setup.md, \"Short windows\").";

  assert.equal(
    compactWindowLayout(layoutStore(clippingRoot)).message,
    `root "Main" (node:main) ${tail}, and give its child "Overlay" (node:overlay) a minimum ` +
      `height of 100% instead of a height${rule}`
  );

  const noChild = layoutStore(clippingRoot);
  delete noChild["node:overlay"];
  noChild["node:target"].parentId = "node:main";
  assert.equal(compactWindowLayout(noChild).message, `root "Main" (node:main) ${tail}${rule}`);
});

// A placement added to the app is a placement App Review can reach, so a new one has to be held to the
// compact-window rule or named here as deliberately exempt. `paywall_decline` is the SDK's own event
// and so is not a Swift case; `app_launch_hard_gate` is a case the app never registers.
const placementsTheAppNeverPresents = ["app_launch_hard_gate"];
const placementsOnlyTheSDKRaises = ["paywall_decline"];

test("every placement the app registers is held to the compact-window rule or named as exempt", async () => {
  const source = await readFile(
    new URL("../../AscendApp/Features/Monetization/Models/SuperwallPlacement.swift", import.meta.url),
    "utf8"
  );
  const appPlacements = [...source.matchAll(/^\s*case \w+ = "([a-z_]+)"/gm)].map(([, name]) => name);

  assert.ok(appPlacements.includes("app_access_gate"), "the placement enum could not be read");
  const unchecked = appPlacements.filter(
    (name) => !GATE_PLACEMENTS.includes(name) && !placementsTheAppNeverPresents.includes(name)
  );
  assert.deepEqual(
    unchecked,
    [],
    `Add ${unchecked.join(", ")} to GATE_PLACEMENTS in scripts/lib/superwall-live-artifact.mjs, ` +
      "or to placementsTheAppNeverPresents here with the reason it never reaches a climber."
  );
  assert.deepEqual(
    GATE_PLACEMENTS.filter(
      (name) => !appPlacements.includes(name) && !placementsOnlyTheSDKRaises.includes(name)
    ),
    [],
    "GATE_PLACEMENTS names a placement the app no longer has."
  );
});

test("the live validator holds every gate placement and does not narrow the list", async () => {
  const script = await readFile(new URL("../validate-superwall-live-artifact.mjs", import.meta.url), "utf8");
  const call = /validateCompactWindowLayouts\(\{[^}]*\}\)/s.exec(script)?.[0] ?? "";

  assert.ok(call, "the validator no longer calls validateCompactWindowLayouts");
  assert.doesNotMatch(call, /placements\s*:/);
});
