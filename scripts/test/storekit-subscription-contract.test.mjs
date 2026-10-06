import assert from "node:assert/strict";
import {readdir, readFile} from "node:fs/promises";
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
const billingAccessTestsURL = new URL(
  "../../AscendAppTests/RevenueCatEntitlementServiceTests.swift",
  import.meta.url
);

test("StoreKit catalog keeps the annual trial, the monthly plan and Lifetime truthful", async () => {
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
  // The catalog mirrors the offer production sells, so the fallback paywall is tested against
  // the trial length and prices a climber actually sees.
  assert.equal(annual.recurringSubscriptionPeriod, "P1Y");
  assert.equal(annual.displayPrice, "29.99");
  assert.deepEqual(annual.introductoryOffer, {
    internalID: "0F6EC9A8-A75E-43EF-9C9E-554000000001",
    numberOfPeriods: 1,
    paymentMode: "free",
    subscriptionPeriod: "P1M"
  });
  assert.equal(monthly.recurringSubscriptionPeriod, "P1M");
  assert.equal(monthly.introductoryOffer, undefined);

  // Lifetime is bought once: a non-consumable outside every subscription group, with no period
  // and no introductory offer for anything to read a trial or a renewal from.
  assert.deepEqual(
    catalog.products.map((product) => [product.productID, product.type, product.displayPrice]),
    [["ascend_staging_lifetime", "NonConsumable", "49.99"]]
  );
  const [lifetime] = catalog.products;
  assert.equal(lifetime.introductoryOffer, undefined);
  assert.equal(lifetime.recurringSubscriptionPeriod, undefined);
  assert.deepEqual(catalog.nonRenewingSubscriptions, []);
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

test("every suite that opens a StoreKit test session is serialized against the others", async () => {
  // The session is process-wide, so one suite resetting it erases the purchase another suite is
  // asserting on. Suites run concurrently, and only the shared trait orders them.
  const testsDirectory = new URL("../../AscendAppTests/", import.meta.url);
  const sessionSuites = [];
  for (const name of await readdir(testsDirectory)) {
    if (!name.endsWith(".swift")) continue;
    const source = await readFile(new URL(name, testsDirectory), "utf8");
    if (!/SKTestSession\(/.test(source)) continue;
    sessionSuites.push(name);
    assert.match(
      source,
      /@Suite\([^)]*\.usesStoreKitTestSession[^)]*\)/,
      `${name} opens an SKTestSession without .usesStoreKitTestSession`
    );
  }
  assert.ok(sessionSuites.includes("StoreKitSubscriptionLifecycleTests.swift"));
  assert.ok(sessionSuites.includes("LifetimeFallbackPaywallEvidenceTests.swift"));
});

test("StoreKitTest suite uses direct session mutations instead of timed renewals", async () => {
  const source = await readFile(lifecycleTestsURL, "utf8");
  for (const testName of [
    "annualAndMonthlyProductsCanCompleteTransactions",
    "lifetimeIsBoughtOnceBesideASubscriptionAndNeverExpires",
    "cancellationDisablesRenewalWithoutRevokingCurrentTransaction",
    "renewalExpirationAndRefundProduceDistinctLifecycleEvidence"
  ]) {
    assert.match(source, new RegExp(`func ${testName}\\(`));
  }
  assert.doesNotMatch(source, /timeRate|Task\.sleep|hasPurchaseIssue|SubscriptionInfo\.Status/);
});

test("RevenueCat billing fixtures own deterministic grace access behavior", async () => {
  const source = await readFile(billingAccessTestsURL, "utf8");
  for (const testName of [
    "activeBillingGracePayloadRoutesToTheMainAppWithoutRefetching",
    "inactiveBillingRetryPayloadRoutesToThePaywallWithoutRefetching"
  ]) {
    assert.match(source, new RegExp(`func ${testName}\\(`));
  }
  assert.match(source, /billingIssueDetectedAt:/);
  assert.match(source, /isActive: isActive/);
  assert.match(source, /customerInfoCallCount == 0/);
});
