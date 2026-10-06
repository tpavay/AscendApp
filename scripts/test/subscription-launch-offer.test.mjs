import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
const pathFromRoot = (...parts) => join(repositoryRoot, ...parts);

const sourcePaths = {
  configuration: pathFromRoot(
    "AscendApp/Features/Monetization/Models/MonetizationConfiguration.swift"
  ),
  paywall: pathFromRoot("web/public/superwall/onboarding-paywall.html"),
  website: pathFromRoot("web/src/pages/index.astro"),
  terms: pathFromRoot("web/src/pages/terms.astro"),
  setup: pathFromRoot("docs/superwall-paywall-setup.md"),
  onboardingGuide: pathFromRoot("docs/onboarding-design-guide.md"),
  appStoreBrief: pathFromRoot("docs/app-store-brief.md"),
  launchAudit: pathFromRoot("docs/launch-readiness-audit.md"),
  projectMemory: pathFromRoot("CLAUDE.md"),
  workflow: pathFromRoot(".github/workflows/ci.yml")
};

async function source(name) {
  return readFile(sourcePaths[name], "utf8");
}

test("the iOS integration names the final RevenueCat contract", async () => {
  const configuration = await source("configuration");

  assert.match(configuration, /revenueCatEntitlementID: String = "app_access"/);
  assert.match(configuration, /revenueCatOfferingID: String = "default"/);
  assert.match(
    configuration,
    /revenueCatYearlyProductIDInfoKey = "AscendRevenueCatYearlyProductID"/
  );
  assert.match(
    configuration,
    /revenueCatLifetimeProductIDInfoKey = "AscendRevenueCatLifetimeProductID"/
  );
  assert.doesNotMatch(configuration, /revenueCatYearlyProductID: String =/);
  assert.doesNotMatch(configuration, /revenueCatLifetimeProductID: String =/);
});

test("a one-time purchase is described as one payment and never as a trial or a renewal", async () => {
  const strings = await readFile(pathFromRoot("AscendApp/en.lproj/Localizable.strings"), "utf8");

  assert.match(strings, /"subscription\.plan\.lifetime" = "Lifetime";/);
  assert.match(strings, /"subscription\.billing\.one_time" = "Pay once\. No renewal\.";/);
  assert.match(strings, /"subscription\.action\.buy_lifetime" = "Buy Lifetime";/);
  assert.doesNotMatch(strings, /"subscription\.plan\.monthly"/);
});

test("the hosted paywall defaults to the annual trial and binds the final products", async () => {
  const paywall = await source("paywall");

  assert.match(paywall, /<main class="paywall" data-selected-plan="yearly">/);
  assert.match(
    paywall,
    /class="plan selected" type="button" data-plan="yearly" aria-pressed="true"/
  );
  assert.match(paywall, /class="plan" type="button" data-plan="monthly" aria-pressed="false"/);
  assert.match(paywall, /data-plan-copy="yearly" data-pw-var="yearly_headline">Try 7 Days Free/);
  assert.match(
    paywall,
    /data-plan-copy="monthly" data-pw-var="monthly_headline" hidden>Climb With Full Access/
  );
  assert.match(paywall, /data-pw-var="yearly_price">\$49\.99\/year/);
  assert.match(paywall, /data-pw-var="monthly_price">\$9\.99\/month/);
  assert.match(paywall, /data-pw-var="yearly_badge">BEST VALUE/);
  assert.match(paywall, /data-pw-var="benefit_2">Compete on global leaderboards/);
  assert.match(
    paywall,
    /data-plan-copy="yearly" data-pw-purchase="yearly"[\s\S]*?Try 7 Days Free/
  );
  assert.match(
    paywall,
    /data-plan-copy="monthly" data-pw-purchase="monthly"[\s\S]*?Subscribe for \$9\.99\/month/
  );
});

test("switching plans swaps every price, trial, CTA, and legal disclosure surface", async () => {
  const paywall = await source("paywall");
  const markup = paywall.slice(0, paywall.indexOf("<script>"));

  assert.match(
    paywall,
    /data-pw-var="yearly_disclosure">\s*7 days free, then \$49\.99\/year\. Auto-renews until canceled\./
  );
  assert.match(
    paywall,
    /data-pw-var="monthly_disclosure" hidden>\s*\$9\.99 charged now, then monthly\. Auto-renews until canceled\./
  );
  assert.match(
    paywall,
    /const planCopy = Array\.from\(document\.querySelectorAll\("\[data-plan-copy\]"\)\)/
  );
  assert.match(paywall, /element\.hidden = element\.dataset\.planCopy !== plan/);
  assert.doesNotMatch(paywall, /\$12\.99|data-plan-copy="monthly"[^>]*>[^<]*trial/i);

  const trialCopyTags = [...markup.matchAll(/<([^>]+)>[^<]*(?:trial|free)[^<]*<\//gi)];
  assert.ok(trialCopyTags.length > 0);
  for (const [, attributes] of trialCopyTags) {
    assert.match(
      attributes,
      /data-plan-copy="yearly"/,
      `trial copy must be annual-only: ${attributes.trim()}`
    );
    assert.match(
      attributes,
      /data-pw-var="/,
      `trial copy must carry a Superwall variable: ${attributes.trim()}`
    );
  }
});

test("every price surface stays overridable by localized StoreKit values", async () => {
  const paywall = await source("paywall");
  const markup = paywall.slice(0, paywall.indexOf("<script>"));

  const priceCopyTags = [...markup.matchAll(/<([^>]+)>([^<]*\$[0-9][^<]*)<\//g)];
  assert.ok(priceCopyTags.length > 0);
  for (const [, attributes, text] of priceCopyTags) {
    assert.match(
      attributes,
      /data-pw-var="/,
      `price copy must carry a Superwall variable: ${text.trim()}`
    );
  }
});

test("setup guidance pins localized pricing, trial eligibility, and the served URL", async () => {
  const setup = await source("setup");

  assert.match(setup, /Never hardcode a localized price or a trial promise that Superwall cannot override\./);
  assert.match(setup, /one introductory offer per subscription group/);
  assert.match(setup, /free-trial-eligibility state/);
  assert.match(setup, /https:\/\/ascendstepper\.com\/superwall\/onboarding-paywall`/);
  assert.doesNotMatch(setup, /https:\/\/ascendstepper\.com\/superwall\/onboarding-paywall\.html/);
});

test("launch paywall claims only implemented leaderboard competition", async () => {
  const controlledLaunchCopy = (
    await Promise.all([
      source("paywall"),
      source("website"),
      source("setup"),
      source("onboardingGuide"),
      source("appStoreBrief"),
      source("launchAudit")
    ])
  ).join("\n");

  assert.match(controlledLaunchCopy, /Compete on global leaderboards/);
  assert.doesNotMatch(controlledLaunchCopy, /personalized climbing plan/i);
});

test("public and legal copy describe the annual trial, Lifetime, and the monthly plan still on sale", async () => {
  const [website, terms] = await Promise.all([source("website"), source("terms")]);

  assert.match(website, /1-month free trial on the \$29\.99\/year plan/);
  assert.match(website, /1-month free trial on the yearly plan/);
  assert.doesNotMatch(website, /7-day free trial|\$49\.99\/year/);
  assert.match(terms, /one-month free trial for eligible Apple accounts, then \$29\.99 per year/);
  assert.match(
    terms,
    /not eligible for the free trial, the annual plan is charged \$29\.99 at confirmation of purchase/
  );
  assert.match(terms, /\$9\.99 is charged immediately[\s\S]*with no free trial/);
  assert.match(terms, /free trial applies only to the annual plan/);
  assert.match(terms, /once per Apple account or Family Sharing group/);
  assert.doesNotMatch(terms, /seven-day free trial|\$49\.99 per year/);

  // Lifetime carries no price here: it is read from the App Store at purchase, and the terms
  // only have to say what kind of charge it is.
  const lifetime = terms.match(/<li><strong>Lifetime:<\/strong>([\s\S]*?)<\/li>/)?.[1];
  assert.ok(lifetime, "the terms must describe the Lifetime purchase");
  assert.match(lifetime, /one payment at the price shown on the purchase screen/);
  assert.match(lifetime, /not a subscription/);
  assert.match(lifetime, /no free trial/);
  assert.match(lifetime, /does not renew/);
  assert.match(lifetime, /does not cancel a subscription you already hold/);
  assert.doesNotMatch(lifetime, /\$\d/);
});

test("active guidance names the plans Ascend sells and no stale commerce offer", async () => {
  const guidanceNames = [
    "setup",
    "onboardingGuide",
    "appStoreBrief",
    "launchAudit",
    "projectMemory"
  ];
  const guidance = (await Promise.all(guidanceNames.map(source))).join("\n");

  for (const expected of [
    "$29.99/year",
    "ascend_yearly",
    "ascend_lifetime",
    "ascend_monthly",
    "Entitlement: `app_access`",
    "Current offering: `default`",
    "$rc_annual",
    "$rc_lifetime",
    "product reference `yearly`",
    "product reference `lifetime`",
    "Pay once. No renewal."
  ]) {
    assert.match(guidance, new RegExp(expected.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  }

  assert.doesNotMatch(
    guidance,
    /\$12\.99|\$24\.99|monthly\/weekly|monthly or weekly|weekly,? TBD|one-time offer/i
  );

  // The two documents that state the current offer must not still state the 1.0 one as current.
  const [setup, projectMemory] = await Promise.all([source("setup"), source("projectMemory")]);
  const launchOffer = setup.slice(
    setup.indexOf("## Launch Offer"),
    setup.indexOf("## Lifetime")
  );
  assert.match(launchOffer, /\| Annual \| `ascend_yearly` \|[^\n]*`\$29\.99\/year`[^\n]*One month/);
  assert.match(launchOffer, /\| Lifetime \| `ascend_lifetime` \| Non-consumable[^\n]*\| None \|/);
  assert.match(projectMemory, /`\$29\.99\/year` with a one-month free trial, or Lifetime/);
  assert.doesNotMatch(projectMemory, /\$49\.99\/year|seven-day free trial, or/);
});

test("the separate discount page is not deployable", async () => {
  await assert.rejects(
    access(pathFromRoot("web/public/superwall/one-time-offer.html")),
    {code: "ENOENT"}
  );
});

test("CI reruns the contract for every repository-controlled launch surface", async () => {
  const workflow = await source("workflow");

  for (const input of [
    "AscendApp/Features/Monetization/**",
    "web/public/superwall/**",
    "web/src/pages/index.astro",
    "web/src/pages/terms.astro",
    "docs/superwall-paywall-setup.md",
    "docs/onboarding-design-guide.md",
    "docs/app-store-brief.md",
    "docs/launch-readiness-audit.md",
    "CLAUDE.md"
  ]) {
    assert.match(workflow, new RegExp(`- "${input.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}"`));
  }
});
