import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";

import {
  activePaywallResponse,
  collectActions,
  compactWindowLayout,
  paddedAppVersion,
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

// The production campaign shape on 2026-11-20: three first-match rules, newest audience first, each
// requiring no active entitlement.
const entitled = "size(device.activeEntitlements) == 0";
const versionedRule = (floor, paywall, extra = {}) => ({
  expression_cel: `(${entitled}) && (device.appVersionPadded >= "${floor}")`,
  variants: [
    {variant_type: "HOLDOUT", percentage: 0},
    {variant_type: "TREATMENT", percentage: 100, paywall_identifier: paywall}
  ],
  ...extra
});
const catchAllRule = (paywall) => ({
  expression: null,
  expression_cel: entitled,
  variants: [{variant_type: "TREATMENT", percentage: 100, paywall_identifier: paywall}]
});

function versionedGate(rules) {
  const identifiers = new Set(
    rules.flatMap(({variants}) => variants.map(({paywall_identifier: id}) => id).filter(Boolean))
  );
  return {
    trigger_options: [{event_name: "app_access_gate", rules}],
    paywall_responses: [...identifiers].map((identifier) => ({id: identifier, identifier}))
  };
}

const productionGate = versionedGate([
  versionedRule("001.003.000", "current"),
  versionedRule("001.002.003", "october"),
  catchAllRule("june")
]);

function checkGate(staticConfig, stores, options = {}) {
  return validateCompactWindowLayouts({
    staticConfig,
    placements: ["app_access_gate"],
    loadRuntimeStore: storesByPaywall(stores),
    enforce: true,
    ...options
  });
}

const allClipping = {
  current: layoutStore(clippingRoot),
  october: layoutStore(clippingRoot),
  june: layoutStore(clippingRoot)
};

test("an app version reads the rules as Superwall does, so only the paywalls it can reach are errors", async () => {
  const result = await checkGate(productionGate, allClipping, {appVersion: "1.3.0"});

  assert.equal(result.errors.length, 1);
  assert.match(result.errors[0], /^app_access_gate paywall current \(current\): /);
  assert.equal(result.warnings.length, 2);
  assert.match(result.warnings[0], /^app_access_gate paywall october \(october\): .*Not reachable from app 1\.3\.0: only older-version rules still serve it \(\(app version >= "001\.002\.003"\)\)/);
  assert.match(result.warnings[1], /^app_access_gate paywall june \(june\): .*still serve it \(every unentitled climber\)/);
  assert.deepEqual(
    result.evidence.map(({paywallIdentifier, reachableFromAppVersion}) => [paywallIdentifier, reachableFromAppVersion]),
    [["current", true], ["october", false], ["june", false]]
  );
});

test("the same campaign without an app version holds every paywall to the rule", async () => {
  const result = await checkGate(productionGate, allClipping);

  assert.equal(result.errors.length, 3);
  assert.deepEqual(result.warnings, []);
});

test("a scrolling current paywall passes while older shadowed ones clip, with warnings naming them", async () => {
  const result = await checkGate(
    productionGate,
    {...allClipping, current: layoutStore(docsRecipe)},
    {appVersion: "1.3.0"}
  );

  assert.deepEqual(result.errors, []);
  assert.equal(result.warnings.length, 2);
});

test("a version the newest rule does not reach is held to the rule the version does reach", async () => {
  const result = await checkGate(productionGate, allClipping, {appVersion: "1.2.4"});

  assert.equal(result.errors.length, 1);
  assert.match(result.errors[0], /paywall october \(october\)/);
  assert.equal(result.warnings.length, 2);
  assert.match(result.warnings[0], /paywall current \(current\): .*Not reachable from app 1\.2\.4/);
});

test("loosening the newest rule's audience makes the older paywall reachable and fails again", async () => {
  const loosened = versionedGate([
    versionedRule("001.004.000", "current"),
    versionedRule("001.002.003", "october"),
    catchAllRule("june")
  ]);
  const result = await checkGate(loosened, allClipping, {appVersion: "1.3.0"});

  assert.equal(result.errors.length, 1);
  assert.match(result.errors[0], /paywall october \(october\)/);
});

test("reordering so an older rule comes first makes that paywall the reachable one", async () => {
  const reordered = versionedGate([
    versionedRule("001.002.003", "october"),
    versionedRule("001.003.000", "current"),
    catchAllRule("june")
  ]);
  const result = await checkGate(reordered, allClipping, {appVersion: "1.3.0"});

  assert.equal(result.errors.length, 1);
  assert.match(result.errors[0], /paywall october \(october\)/);
  assert.equal(result.warnings.length, 2);
});

test("a rule condition the reader cannot parse stays reachable and does not shadow what follows", async () => {
  const unparseable = versionedGate([
    {
      expression_cel: `(${entitled}) && (device.appVersionPadded >= "001.003.000" && params.presented_by_event_name == "app_access_gate")`,
      variants: [{variant_type: "TREATMENT", percentage: 100, paywall_identifier: "current"}]
    },
    versionedRule("001.002.003", "october"),
    catchAllRule("june")
  ]);
  const result = await checkGate(unparseable, allClipping, {appVersion: "1.3.0"});

  assert.equal(result.errors.length, 2);
  assert.match(result.errors[0], /paywall current/);
  assert.match(result.errors[1], /paywall october/);
  assert.equal(result.warnings.length, 1);
  assert.match(result.warnings[0], /paywall june/);
});

test("a rule with no condition at all matches every version and shadows the rules after it", async () => {
  const everyone = versionedGate([
    {variants: [{variant_type: "TREATMENT", percentage: 100, paywall_identifier: "current"}]},
    catchAllRule("june")
  ]);
  const result = await checkGate(everyone, {current: layoutStore(docsRecipe), june: layoutStore(clippingRoot)}, {appVersion: "1.3.0"});

  assert.deepEqual(result.errors, []);
  assert.equal(result.warnings.length, 1);
});

test("a shadowed paywall whose runtime cannot be read is a warning naming its audience, never silence", async () => {
  const result = await checkGate(
    productionGate,
    {current: layoutStore(docsRecipe), october: layoutStore(docsRecipe)},
    {appVersion: "1.3.0"}
  );

  assert.deepEqual(result.errors, []);
  assert.equal(result.warnings.length, 1);
  assert.match(result.warnings[0], /paywall june \(june\): no runtime for june\. Not reachable/);
});

test("an app version that is not a numeric version is refused", async () => {
  const result = await checkGate(productionGate, allClipping, {appVersion: "next"});

  assert.deepEqual(result.errors, ['App version "next" is not a one to three component numeric version.']);
});

test("a placement whose every rule excludes the app version is an error, never an empty pass", async () => {
  const future = versionedGate([versionedRule("002.000.000", "current")]);
  const result = await checkGate(future, {current: layoutStore(clippingRoot)}, {appVersion: "1.3.0"});

  assert.equal(result.errors.length, 1);
  assert.match(result.errors[0], /^app_access_gate serves no paywall to an app at version 1\.3\.0\.$/);
});

test("paddedAppVersion pads each component so strings order as versions", () => {
  assert.equal(paddedAppVersion("1.3.0"), "001.003.000");
  assert.equal(paddedAppVersion("1.3"), "001.003.000");
  assert.equal(paddedAppVersion("1.2.10"), "001.002.010");
  assert.ok(paddedAppVersion("1.2.10") > paddedAppVersion("1.2.9"));
  assert.equal(paddedAppVersion("1.3.0.1"), null);
  assert.equal(paddedAppVersion("one"), null);
});
