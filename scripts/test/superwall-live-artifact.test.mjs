import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";

import {
  activePaywallResponse,
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
