import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
const pathFromRoot = (...parts) => join(repositoryRoot, ...parts);

const sourcePaths = {
  appStore: pathFromRoot("web/src/appStore.ts"),
  badge: pathFromRoot("web/src/components/AppStoreBadge.astro"),
  nav: pathFromRoot("web/src/components/Nav.astro"),
  slideMenu: pathFromRoot("web/src/components/SlideMenu.astro"),
  home: pathFromRoot("web/src/pages/index.astro")
};

async function source(name) {
  return readFile(sourcePaths[name], "utf8");
}

// The bare, storefront-agnostic form. Ascend ships to 147 countries, so a
// `/us/` segment would pin every visitor to the American storefront and
// `?uo=4` would attach an affiliate parameter Ascend does not use.
const APP_STORE_URL = "https://apps.apple.com/app/id6757202987";

async function webSourceFiles() {
  const roots = ["web/src/pages", "web/src/components", "web/src/layouts"];
  const files = [];

  for (const root of roots) {
    for (const entry of await readdir(pathFromRoot(root))) {
      files.push({ path: join(root, entry), contents: await readFile(pathFromRoot(root, entry), "utf8") });
    }
  }

  return files;
}

test("the App Store link is one bare, storefront-agnostic constant", async () => {
  const appStore = await source("appStore");

  assert.match(appStore, new RegExp(`export const APP_STORE_URL = ['"]${APP_STORE_URL}['"]`));

  for (const { path, contents } of await webSourceFiles()) {
    assert.doesNotMatch(contents, /apps\.apple\.com\/[a-z]{2}\//, `${path} pins a single storefront`);
    assert.doesNotMatch(contents, /apps\.apple\.com[^\s"'<]*uo=4/, `${path} carries the uo=4 affiliate parameter`);
    assert.doesNotMatch(
      contents,
      /["']https:\/\/apps\.apple\.com/,
      `${path} repeats the App Store URL instead of importing APP_STORE_URL`
    );
  }
});

test("every download surface sends the climber to the store", async () => {
  const surfaces = [
    ["nav", /<a class="nav-cta" href=\{APP_STORE_URL\}>Download<\/a>/],
    ["slideMenu", /<a href=\{APP_STORE_URL\}>Download<\/a>/]
  ];

  for (const [name, expected] of surfaces) {
    const contents = await source(name);
    assert.match(contents, /import \{ APP_STORE_URL \} from ['"]\.\.\/appStore['"]/, `${name} does not import the constant`);
    assert.match(contents, expected, `${name} does not link to the store`);
    assert.doesNotMatch(contents, /Coming Soon/i, `${name} still says coming soon`);
  }

  const home = await source("home");
  const badgeUses = home.match(/<AppStoreBadge[^/]*\/>/g) ?? [];
  assert.equal(badgeUses.length, 2, "expected the hero and closing-CTA badges");
  for (const use of badgeUses) {
    assert.match(use, /href=\{APP_STORE_URL\}/, `badge rendered without the store link: ${use}`);
  }
});

test("the badge has no non-linking pre-launch state to fall back to", async () => {
  const badge = await source("badge");

  // `href` is required: once every call site passes a URL, a "coming soon"
  // branch is unreachable code that could only ever resurface by accident.
  assert.match(badge, /href: string;/);
  assert.doesNotMatch(badge, /href\?: string/);
  assert.doesNotMatch(badge, /Coming soon/i);
  assert.match(badge, /alt="Download on the App Store"/);
});

test("no pre-launch language survives on the website", async () => {
  // Two documented exemptions, both unrelated to Ascend's own launch:
  // VideoPlayer's placeholder is about a missing video asset, and privacy's
  // waitlist mentions are accurate history about data Ascend still holds.
  const exempt = new Set(["web/src/components/VideoPlayer.astro", "web/src/pages/privacy.astro"]);
  const preLaunch = /coming soon|launching soon|coming to the App Store|be available\?|waitlist|notify me|pre-launch/i;

  for (const { path, contents } of await webSourceFiles()) {
    if (exempt.has(path)) continue;
    assert.doesNotMatch(contents, preLaunch, `${path} still carries pre-launch language`);
  }

  const home = await source("home");
  assert.match(home, /Where do I get Ascend\?/);
  assert.match(home, /Ascend is out now on the App Store/);
});
