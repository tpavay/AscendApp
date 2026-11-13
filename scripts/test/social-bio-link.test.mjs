import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

// The page's own logic, loaded through Node's type stripping: the test runs
// the exact functions the /go page ships.
import {
  APP_STORE_CAMPAIGN_PATH,
  APP_STORE_PROVIDER_TOKEN,
  BIO_LINK_CAMPAIGNS,
  BIO_LINK_DEFAULT_CAMPAIGN,
  appStoreCampaignURL,
  bioLinkCampaignToken
} from "../../web/src/appStore.ts";
import {
  APP_FALLBACK_DELAY_MS,
  appOpenURL,
  attemptAppOpen,
  classifyBrowser,
  handoffPlan
} from "../../web/src/goHandoff.ts";
import { ciFilterPatterns } from "./support/ci-workflow-filters.mjs";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
const pathFromRoot = (...parts) => join(repositoryRoot, ...parts);

const sourcePaths = {
  page: pathFromRoot("web/src/pages/go.astro"),
  hosting: pathFromRoot("firebase.json"),
  doc: pathFromRoot("docs/social-bio-link.md"),
  ci: pathFromRoot(".github/workflows/ci.yml")
};

async function source(name) {
  return readFile(sourcePaths[name], "utf8");
}

// The exact App Store campaign link the captain's bios attribute through.
// pt is Ascend's provider token, ct the campaign, mt=8 the App Store.
const CAMPAIGN_PREFIX = "https://apps.apple.com/app/apple-store/id6757202987?pt=128011549&ct=";
const campaignURL = (token, scheme = "https") =>
  `${scheme}://apps.apple.com/app/apple-store/id6757202987?pt=128011549&ct=${token}&mt=8`;

const iphone = (tail) =>
  `Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) ${tail}`;

const USER_AGENTS = {
  instagram: iphone("Mobile/15E148 Instagram 384.0.0.0.0 (iPhone16,2; iOS 18_6; en_US; en; scale=3.00; 1179x2556; 737531334)"),
  facebook: iphone("Mobile/15E148 [FBAN/FBIOS;FBAV/525.0.0.0;FBBV/740000000;FBDV/iPhone16,2;FBMD/iPhone;FBSN/iOS;FBSV/18.6;FBSS/3;FBID/phone;FBLC/en_US;FBOP/5;FBRV/0]"),
  messenger: iphone("Mobile/15E148 [FBAN/MessengerForiOS;FBAV/480.0.0.0;FBBV/700000000;FBDV/iPhone16,2;FBMD/iPhone;FBSN/iOS;FBSV/18.6;FBSS/3;FBID/phone;FBLC/en_US;FBOP/5]"),
  tiktok: iphone("Mobile/15E148 musical_ly_42.0.0 JsSdk/2.0 NetType/WIFI Channel/App Store ByteLocale/en Region/US isDarkMode/1 WKWebView/1 RevealType/Dialog BytedanceWebview/d8a21c6"),
  youtube: "com.google.ios.youtube/20.40.1 iSL/3.4 iPhone/18.6 hw/iPhone16_2 (gzip)",
  unnamedWebView: iphone("Mobile/15E148"),
  safari: iphone("Version/18.6 Mobile/15E148 Safari/604.1"),
  chrome: iphone("CriOS/141.0.7390.56 Mobile/15E148 Safari/604.1"),
  firefox: iphone("FxiOS/141.0 Mobile/15E148 Safari/605.1.15"),
  edge: iphone("Version/18.0 EdgiOS/141.0.3537.57 Mobile/15E148 Safari/604.1"),
  desktopSafari: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15",
  desktopChrome: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36",
  androidChrome: "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36",
  androidInstagram: "Mozilla/5.0 (Linux; Android 15; Pixel 9 Build/AP4A.250105.002; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/141.0.0.0 Mobile Safari/537.36 Instagram 384.0.0.0.0 Android"
};

test("the four bio sources map to exactly the campaign tokens the captain named", () => {
  assert.deepEqual(BIO_LINK_CAMPAIGNS, {
    instagram: "Instagram-bio",
    tiktok: "TikTok-bio",
    youtube: "YouTube-shorts",
    facebook: "Facebook-bio"
  });
  assert.equal(BIO_LINK_DEFAULT_CAMPAIGN, "Link-direct");
  assert.equal(APP_STORE_PROVIDER_TOKEN, "128011549");
  assert.equal(APP_STORE_CAMPAIGN_PATH, "apps.apple.com/app/apple-store/id6757202987");

  // Case and whitespace are forgiven; anything unknown is the direct campaign,
  // never an invented token.
  assert.equal(bioLinkCampaignToken("instagram"), "Instagram-bio");
  assert.equal(bioLinkCampaignToken(" TikTok "), "TikTok-bio");
  assert.equal(bioLinkCampaignToken("YouTube"), "YouTube-shorts");
  assert.equal(bioLinkCampaignToken("facebook"), "Facebook-bio");
  for (const source of [null, undefined, "", "direct", "twitter", "Instagram-bio", "__proto__", "constructor"]) {
    assert.equal(bioLinkCampaignToken(source), "Link-direct", `source ${JSON.stringify(source)}`);
  }
});

test("the campaign URL carries pt, ct and mt=8 and nothing else", () => {
  assert.equal(appStoreCampaignURL("instagram"), campaignURL("Instagram-bio"));
  assert.equal(appStoreCampaignURL("tiktok"), campaignURL("TikTok-bio"));
  assert.equal(appStoreCampaignURL("youtube"), campaignURL("YouTube-shorts"));
  assert.equal(appStoreCampaignURL("facebook"), campaignURL("Facebook-bio"));
  assert.equal(appStoreCampaignURL(null), campaignURL("Link-direct"));
  assert.equal(appStoreCampaignURL("instagram", "itms-apps"), campaignURL("Instagram-bio", "itms-apps"));

  const url = new URL(appStoreCampaignURL("instagram"));
  assert.deepEqual([...url.searchParams.keys()].sort(), ["ct", "mt", "pt"]);
  // Storefront-agnostic, like every other App Store link on the site.
  assert.doesNotMatch(url.pathname, /^\/[a-z]{2}\//);
});

test("every in-app browser is recognised from its user agent and every real browser is not", () => {
  for (const name of ["instagram", "facebook", "messenger", "tiktok", "youtube", "unnamedWebView", "androidInstagram"]) {
    assert.equal(classifyBrowser(USER_AGENTS[name]).inApp, true, `${name} should be in-app`);
  }

  for (const name of ["safari", "chrome", "firefox", "edge", "desktopSafari", "desktopChrome", "androidChrome"]) {
    assert.equal(classifyBrowser(USER_AGENTS[name]).inApp, false, `${name} should be a real browser`);
  }

  assert.equal(classifyBrowser("").inApp, false);
});

test("an iOS in-app browser gets the tap-first App Store scheme; everything else redirects to the product page", () => {
  for (const [name, token] of [["instagram", "Instagram-bio"], ["facebook", "Facebook-bio"], ["tiktok", "TikTok-bio"], ["youtube", "YouTube-shorts"]]) {
    const plan = handoffPlan(USER_AGENTS[name], `?src=${name}`);
    assert.equal(plan.inApp, true, name);
    assert.equal(plan.redirect, false, name);
    assert.equal(plan.campaignToken, token);
    assert.equal(plan.handoffURL, campaignURL(token, "itms-apps"), `${name} hand-off`);
    assert.equal(plan.storeURL, campaignURL(token), `${name} product page`);
  }

  for (const name of ["safari", "chrome", "desktopChrome", "androidChrome"]) {
    const plan = handoffPlan(USER_AGENTS[name], "?src=instagram");
    assert.equal(plan.inApp, false, name);
    assert.equal(plan.redirect, true, name);
    assert.equal(plan.handoffURL, campaignURL("Instagram-bio"), `${name} redirects to the https product page`);
  }

  // Android has no App Store app to hand to, so an Android in-app browser
  // keeps the tap-first page but its button carries the https product page.
  const android = handoffPlan(USER_AGENTS.androidInstagram, "?src=instagram");
  assert.equal(android.inApp, true);
  assert.equal(android.redirect, false);
  assert.equal(android.handoffURL, campaignURL("Instagram-bio"));

  // The source survives alongside other query parameters, and its absence is
  // the direct campaign.
  assert.equal(handoffPlan(USER_AGENTS.safari, "?utm_x=1&src=tiktok").campaignToken, "TikTok-bio");
  assert.equal(handoffPlan(USER_AGENTS.safari, "").campaignToken, "Link-direct");
});

test("every iPhone visitor is first offered the App Store build's own go link; nobody else is", () => {
  for (const name of ["safari", "chrome", "firefox", "edge", "instagram", "youtube", "unnamedWebView"]) {
    const plan = handoffPlan(USER_AGENTS[name], "?src=email-trial-reminder");
    assert.equal(plan.appURL, "ascendapp://go?src=email-trial-reminder", name);
  }
  for (const name of ["desktopSafari", "desktopChrome", "androidChrome", "androidInstagram"]) {
    assert.equal(handoffPlan(USER_AGENTS[name], "?src=email-trial-reminder").appURL, null, name);
  }

  // The App Store fallback is unchanged by the attempt.
  const safari = handoffPlan(USER_AGENTS.safari, "?src=instagram");
  assert.equal(safari.redirect, true);
  assert.equal(safari.handoffURL, campaignURL("Instagram-bio"));
});

test("the app link carries only a tag the app knows", () => {
  for (const tag of ["email-paywall-abandoned", "email-free-week-unused", "email-trial-reminder", "instagram", "tiktok", "youtube", "facebook"]) {
    assert.equal(appOpenURL(tag), `ascendapp://go?src=${tag}`);
  }
  assert.equal(appOpenURL(" Email-Trial-Reminder "), "ascendapp://go?src=email-trial-reminder");
  for (const source of [null, undefined, "", "none", "other", "twitter", "x&y=1", "__proto__", "javascript:alert(1)"]) {
    assert.equal(appOpenURL(source), "ascendapp://go", `source ${JSON.stringify(source)}`);
  }
});

function fakeAppOpenEnvironment() {
  const listeners = new Map();
  const timers = new Map();
  let nextTimer = 1;
  const env = {
    hidden: false,
    frames: [],
    openInFrame: (url) => env.frames.push(url),
    isHidden: () => env.hidden,
    listen: (type, handler) => listeners.set(type, [...(listeners.get(type) ?? []), handler]),
    setTimeout: (handler, delayMs) => {
      const id = nextTimer++;
      timers.set(id, { handler, delayMs });
      return id;
    },
    clearTimeout: (id) => timers.delete(id),
    fire: (type) => (listeners.get(type) ?? []).forEach((handler) => handler()),
    runTimers: () => {
      for (const [id, { handler }] of [...timers]) {
        timers.delete(id);
        handler();
      }
    },
    timers
  };
  return env;
}

test("the app is tried in a frame, and the store follows once only if the page is still on screen", () => {
  const env = fakeAppOpenEnvironment();
  let fallbacks = 0;
  attemptAppOpen(env, "ascendapp://go?src=email-trial-reminder", () => fallbacks++);

  assert.deepEqual(env.frames, ["ascendapp://go?src=email-trial-reminder"], "the page itself never navigates to the scheme");
  assert.deepEqual([...env.timers.values()].map(({ delayMs }) => delayMs), [APP_FALLBACK_DELAY_MS]);
  assert.equal(APP_FALLBACK_DELAY_MS, 1500);
  assert.equal(fallbacks, 0, "nothing happens before the wait is over");

  env.runTimers();
  assert.equal(fallbacks, 1);
  env.fire("blur");
  env.fire("pagehide");
  env.runTimers();
  assert.equal(fallbacks, 1, "the fallback runs at most once");
});

test("the app taking over cancels the store fallback, whichever way the page notices", () => {
  for (const leave of [
    (env) => { env.hidden = true; env.fire("visibilitychange"); },
    (env) => env.fire("pagehide"),
    (env) => env.fire("blur")
  ]) {
    const env = fakeAppOpenEnvironment();
    let fallbacks = 0;
    attemptAppOpen(env, "ascendapp://go", () => fallbacks++);
    leave(env);
    env.hidden = false;
    env.runTimers();
    assert.equal(fallbacks, 0);
    assert.equal(env.timers.size, 0, "the timer is cleared, not left to fire on return");
  }

  // A visibility change that leaves the page visible is not the app opening.
  const env = fakeAppOpenEnvironment();
  let fallbacks = 0;
  attemptAppOpen(env, "ascendapp://go", () => fallbacks++);
  env.fire("visibilitychange");
  env.runTimers();
  assert.equal(fallbacks, 1);

  // A page already hidden when the wait ends does not send the climber on.
  const hidden = fakeAppOpenEnvironment();
  let hiddenFallbacks = 0;
  attemptAppOpen(hidden, "ascendapp://go", () => hiddenFallbacks++);
  hidden.hidden = true;
  hidden.runTimers();
  assert.equal(hiddenFallbacks, 0);
});

test("the /go page is served clean, never hardcodes the store, and loads no tracking", async () => {
  const page = await source("page");

  // The store URL and its app scheme have one home: web/src/appStore.ts.
  assert.ok(!page.includes("https://apps.apple.com"), "the page repeats the store URL instead of importing it");
  assert.ok(!page.includes("itms-apps"), "the scheme belongs to appStore.ts, not the page");

  assert.ok(page.includes('<meta name="robots" content="noindex" />'), "a bounce page must not be indexed");
  assert.ok(page.includes("<noscript>"), "a visitor without JavaScript needs a fallback");

  // No tracking script: the site has none, and a bounce page must not be
  // where one appears.
  assert.doesNotMatch(page, /<script[^>]*\ssrc=/i);
  assert.doesNotMatch(page, /gtag|googletagmanager|mixpanel/i);

  // Firebase Hosting serves web/dist/go.html at /go only with clean URLs on,
  // and the hosting block has no rewrite that would shadow the path.
  const hosting = JSON.parse(await source("hosting")).hosting;
  assert.equal(hosting.cleanUrls, true);
  assert.equal(hosting.public, "web/dist");
  for (const rewrite of hosting.rewrites ?? []) {
    assert.doesNotMatch(rewrite.source, /^\/go(\/|$|\*)|^\*\*$/, `rewrite ${rewrite.source} would shadow /go`);
  }
});

test("the doc publishes one URL per platform and CI runs this suite when its inputs change", async () => {
  const doc = await source("doc");
  for (const [source, token] of Object.entries(BIO_LINK_CAMPAIGNS)) {
    assert.match(doc, new RegExp(`https://ascendstepper\\.com/go\\?src=${source}\\b`), `doc lacks the ${source} link`);
    assert.ok(doc.includes(`${CAMPAIGN_PREFIX}${token}&mt=8`), `doc lacks the ${token} campaign URL`);
  }
  assert.ok(doc.includes(campaignURL("Link-direct")));

  const scriptsFilter = ciFilterPatterns(await source("ci")).get("scripts") ?? [];
  for (const input of ["web/src/appStore.ts", "web/src/goHandoff.ts", "web/src/pages/go.astro", "docs/social-bio-link.md"]) {
    assert.ok(scriptsFilter.includes(input), `ci.yml scripts filter lacks ${input}`);
  }
});
