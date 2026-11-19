import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";

import {
  activePaywallResponse,
  collectActions,
  compactWindowLayout,
  runtimeStoreFromHTML,
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
function layoutStore({rootHeight, rootOverflowY, rootScroll = "none", childHeight = {value: "100", unit: "%"}}) {
  const literal = (value) => ({type: "literal", value});
  const length = ({value, unit}) => literal({type: "css-length", value, unit});
  return {
    "node:main": {
      id: "node:main",
      name: "Main",
      parentId: "page:page",
      type: "stack",
      defaultProperties: {
        "prop:stack": literal({type: "property-stack", axis: "y", scroll: rootScroll}),
        "css:height": length(rootHeight),
        "css:overflowY": literal({type: "css-string", value: rootOverflowY})
      },
      properties: {}
    },
    "node:overlay": {
      id: "node:overlay",
      name: "Overlay",
      parentId: "node:main",
      type: "stack",
      defaultProperties: {"css:height": length(childHeight)},
      properties: {}
    },
    "node:purchase": {
      id: "node:purchase",
      name: "CTA - purchase selected product",
      parentId: "node:overlay",
      type: "stack",
      defaultProperties: {},
      properties: {
        "prop:click-behavior": literal({
          type: "click-behavior",
          clickActions: [{action: {type: "purchase", reference: {type: "by-selected"}, onPurchase: [{action: {type: "close"}}]}}]
        })
      }
    }
  };
}

function layoutVerdict(store) {
  const purchases = collectActions(store).filter(({action}) => action.type === "purchase");
  return compactWindowLayout(store, purchases);
}

// App Review, 2026-11-19, iPad Air 11-inch (M3): the iPhone app gets a 375 by 667 pt window there,
// and the paywall's content needs 834 pt. The root was 100dvh, overflow hidden, scroll none.
test("a paywall fixed to the viewport with overflow hidden and no scroll clips the purchase button", () => {
  const verdict = layoutVerdict(
    layoutStore({rootHeight: {value: "100", unit: "dvh"}, rootOverflowY: "hidden"})
  );

  assert.equal(verdict.verdict, "clips");
  assert.match(verdict.message, /Paywall root "Main"/);
});

test("scroll normal does not help while the node's own Overflow Y is still hidden", () => {
  const verdict = layoutVerdict(
    layoutStore({rootHeight: {value: "100", unit: "dvh"}, rootOverflowY: "hidden", rootScroll: "normal"})
  );

  assert.equal(verdict.verdict, "clips");
});

test("a root that scrolls vertically reaches the purchase button on any window", () => {
  const verdict = layoutVerdict(
    layoutStore({rootHeight: {value: "100", unit: "dvh"}, rootOverflowY: "auto", rootScroll: "normal"})
  );

  assert.equal(verdict.verdict, "scrolls");
  assert.equal(verdict.message, null);
});

test("a root that grows with its content never clips", () => {
  const verdict = layoutVerdict(
    layoutStore({rootHeight: {value: "auto", unit: "none"}, rootOverflowY: "hidden"})
  );

  assert.equal(verdict.verdict, "fits");
});

test("a capture with no node tree is unknown, never an error", async () => {
  const capture = await fixture(productionFixture);
  const purchases = collectActions(capture.runtimeStore).filter(({action}) => action.type === "purchase");

  assert.equal(compactWindowLayout(capture.runtimeStore, purchases).verdict, "unknown");
});

test("the layout finding is an error only where it is enforced, and a warning elsewhere", async () => {
  const capture = structuredClone(await fixture(productionFixture));
  const response = activePaywallResponse(capture.staticConfig, "app_access_gate").response;
  for (const product of response.products_v2) product.entitlements = [{identifier: "app_access"}];
  capture.runtimeStore["state:purchaseAbandoned"] = {};
  capture.runtimeStore["node:purchase"].properties["prop:click-behavior"].value.clickActions[0].action
    .onAbandon[0].action.stateId = "state:purchaseAbandoned";
  Object.assign(
    capture.runtimeStore,
    layoutStore({rootHeight: {value: "100", unit: "dvh"}, rootOverflowY: "hidden"}),
    {"node:purchase": {...layoutStore({rootHeight: {value: "100", unit: "dvh"}, rootOverflowY: "hidden"})["node:purchase"]}}
  );
  const validate = (enforce) =>
    validateSuperwallArtifact({
      staticConfig: capture.staticConfig,
      runtimeStore: capture.runtimeStore,
      placement: "app_access_gate",
      sellableProductIDs: ["ascend_yearly", "ascend_monthly"],
      expectedEntitlementID: "app_access",
      enforceCompactWindowLayout: enforce
    });

  const strict = validate(true);
  assert.equal(strict.errors.length, 1);
  assert.match(strict.errors[0], /667 pt tall/);
  assert.equal(strict.evidence.compactWindowLayout, "clips");

  const lenient = validate(false);
  assert.deepEqual(lenient.errors, []);
  assert.equal(lenient.warnings.length, 1);
});
