import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";

const configurationURL = new URL(
  "../../AscendApp/Configuration/AscendSubscriptions.storekit",
  import.meta.url
);
const schemeURL = new URL(
  "../../AscendApp.xcodeproj/xcshareddata/xcschemes/AscendApp-Staging.xcscheme",
  import.meta.url
);
const lifecycleTestsURL = new URL(
  "../../AscendAppTests/StoreKitSubscriptionLifecycleTests.swift",
  import.meta.url
);

test("StoreKit catalog keeps the annual trial and monthly plan truthful", async () => {
  const catalog = JSON.parse(await readFile(configurationURL, "utf8"));
  const subscriptions = catalog.subscriptionGroups.flatMap(
    (group) => group.subscriptions
  );
  assert.deepEqual(
    subscriptions.map((subscription) => subscription.productID).sort(),
    ["ascend_staging_monthly", "ascend_staging_yearly"]
  );

  const annual = subscriptions.find(
    (subscription) => subscription.productID === "ascend_staging_yearly"
  );
  const monthly = subscriptions.find(
    (subscription) => subscription.productID === "ascend_staging_monthly"
  );
  assert.equal(annual.recurringSubscriptionPeriod, "P1Y");
  assert.deepEqual(annual.introductoryOffer, {
    internalID: "0F6EC9A8-A75E-43EF-9C9E-554000000001",
    numberOfPeriods: 1,
    paymentMode: "free",
    subscriptionPeriod: "P1W"
  });
  assert.equal(monthly.recurringSubscriptionPeriod, "P1M");
  assert.equal(monthly.introductoryOffer, undefined);
});

test("shared Staging Test action uses Staging and the committed StoreKit catalog", async () => {
  const scheme = await readFile(schemeURL, "utf8");
  const testAction = scheme.match(/<TestAction[\s\S]*?<\/TestAction>/)?.[0];
  assert.ok(testAction, "Missing TestAction");
  assert.match(testAction, /buildConfiguration = "Staging"/);
  assert.match(
    testAction,
    /identifier = "\.\.\/AscendApp\/Configuration\/AscendSubscriptions\.storekit"/
  );
});

test("StoreKitTest suite names every simulator-owned lifecycle contract", async () => {
  const source = await readFile(lifecycleTestsURL, "utf8");
  for (const testName of [
    "annualAndMonthlyProductsCanCompleteTransactions",
    "cancellationDisablesRenewalWithoutRevokingCurrentTransaction",
    "renewalExpirationAndRefundProduceDistinctLifecycleEvidence",
    "billingRetryWithGraceCanBeResolvedDeterministically"
  ]) {
    assert.match(source, new RegExp(`func ${testName}\\(`));
  }
});
