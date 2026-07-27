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
  assert.match(configuration, /revenueCatYearlyProductID: String = "ascend_yearly"/);
  assert.match(configuration, /revenueCatMonthlyProductID: String = "ascend_monthly"/);
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
  assert.match(
    paywall,
    /data-plan-copy="yearly" data-pw-purchase="primary"[\s\S]*?Try 7 Days Free/
  );
  assert.match(
    paywall,
    /data-plan-copy="monthly" data-pw-purchase="secondary"[\s\S]*?Subscribe for \$9\.99\/month/
  );
});

test("switching plans swaps every price, trial, CTA, and legal disclosure surface", async () => {
  const paywall = await source("paywall");

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
});

test("public and legal copy describe the exact annual and immediate monthly offers", async () => {
  const [website, terms] = await Promise.all([source("website"), source("terms")]);

  assert.match(website, /7-day free trial on the \$49\.99\/year plan/);
  assert.match(website, /\$9\.99\/month plan is charged immediately and has no trial/);
  assert.match(terms, /seven-day free trial, then \$49\.99 per year/);
  assert.match(terms, /\$9\.99 is charged immediately[\s\S]*with no free trial/);
  assert.match(terms, /free trial applies only to the annual plan/);
});

test("active guidance contains two launch products and no stale commerce offer", async () => {
  const guidanceNames = [
    "setup",
    "onboardingGuide",
    "appStoreBrief",
    "launchAudit",
    "projectMemory"
  ];
  const guidance = (await Promise.all(guidanceNames.map(source))).join("\n");

  for (const expected of [
    "$49.99/year",
    "$9.99/month",
    "ascend_yearly",
    "ascend_monthly",
    "app_access",
    "default",
    "$rc_annual",
    "$rc_monthly",
    "product reference `primary`",
    "product reference `secondary`"
  ]) {
    assert.match(guidance, new RegExp(expected.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  }

  assert.doesNotMatch(
    guidance,
    /\$12\.99|\$24\.99|monthly\/weekly|monthly or weekly|weekly,? TBD|one-time offer/i
  );
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
