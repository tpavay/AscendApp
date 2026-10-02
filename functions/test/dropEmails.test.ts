import test from "node:test";
import {createHash} from "node:crypto";
import {existsSync, readFileSync} from "node:fs";
import {join} from "node:path";
import assert from "node:assert/strict";
import {
  buildDropDedupeKey,
  buildDropTestDedupeKey,
  catalogueRequirement,
  dropCatalogueMismatches,
  preferenceOwnerUid,
  selectDropAudience,
} from "../src/dropEmails";
import {renderEmailContentForJob} from "../src/email/catalog";
import {
  dropEmailImagePaths,
  dropEmailItems,
  parseDropEmailPayload,
  renderDropEmail,
} from "../src/email/dropTemplate";
import {buildDropEmailPayload, DROP_EMAILS} from "../src/email/drops";
import type {EmailJobDocument, EmailJobPayload} from "../src/email/types";

const ASSETS = "https://ascendstepper.com";
const UNSUBSCRIBE = "https://ascendstepper.com/api/unsubscribe?token=abc";

/**
 * One catalogue item row, shaped like `web/public/unlocks/catalog.json`.
 * @param {string} id - Item id
 * @param {string} event - Event id
 * @param {string} metric - Earn metric
 * @param {number} threshold - Earn threshold
 * @return {object} Catalogue item
 */
function item(id: string, event: string, metric: string, threshold: number) {
  return {id, status: "live", earn: {path: "event", event, metric, threshold}};
}

/**
 * The Halloween half of the unlock catalogue as it ships on
 * fm/ascend-seasonal-events, plus a Thanksgiving item the Halloween email
 * must ignore.
 * @return {object} Catalogue
 */
function shippedCatalogue() {
  return {
    events: [
      {id: "halloween-2026", monthName: "October", startsOn: "2026-10-01",
        endsBefore: "2026-11-01"},
      {id: "thanksgiving-2026", monthName: "November", startsOn: "2026-11-01",
        endsBefore: "2026-12-01"},
    ],
    items: [
      item("pumpkin_classic", "halloween-2026", "visits", 1),
      item("pumpkin_ghost", "halloween-2026", "climbs", 1),
      item("witch_hat", "halloween-2026", "climbs", 3),
      item("pumpkin_heirloom", "halloween-2026", "climbs", 5),
      item("pumpkin_lantern", "halloween-2026", "climbs", 10),
      item("candy_corn", "halloween-2026", "climbs", 15),
      item("ghost_sheet", "halloween-2026", "climbs", 20),
      item("witching_shorts", "halloween-2026", "days", 7),
      item("pumpkin_head", "halloween-2026", "days", 31),
      item("ember_trainers", "halloween-2026", "onDay", 31),
      item("pumpkin_midnight", "halloween-2026", "steps", 25000),
      item("chocolate_bar", "halloween-2026", "steps", 10000),
      item("pumpkin_giant", "halloween-2026", "steps", 50000),
      item("glow_trainers", "halloween-2026", "steps", 75000),
      item("pumpkin_giant_lantern", "halloween-2026", "steps", 100000),
      item("pumpkin_pie", "thanksgiving-2026", "climbs", 1),
    ],
  };
}

const halloween = () => buildDropEmailPayload("halloween-2026", ASSETS);

test("the Halloween email matches the catalogue the app ships", () => {
  assert.deepEqual(
    dropCatalogueMismatches(halloween(), shippedCatalogue()),
    []
  );
  // The fact row and the intro count what the groups hold.
  assert.equal(dropEmailItems(halloween()).length, 15);
  assert.equal(halloween().facts[0].value, "15");
  assert.match(halloween().intro, /since October 1 already count\./);
});

test("a catalogue change the email does not reflect is reported", () => {
  const raised = shippedCatalogue();
  raised.items[5].earn.threshold = 12;
  raised.items[2].status = "hidden";
  raised.items.push(item("bat_wings", "halloween-2026", "climbs", 25));

  const mismatches = dropCatalogueMismatches(halloween(), raised);

  assert.deepEqual(mismatches, [
    "Witch Hat: catalogue status is \"hidden\", not \"live\".",
    "Candy Corn: the email says \"15 climbs\", the catalogue says " +
      "\"12 climbs\".",
    "\"bat_wings\" is live in the catalogue but missing from the email.",
  ]);
  assert.deepEqual(
    dropCatalogueMismatches(halloween(), {events: [], items: []}),
    ["The unlock catalogue has no event \"halloween-2026\"."]
  );
  assert.deepEqual(
    dropCatalogueMismatches(halloween(), null),
    ["The unlock catalogue has no events or items."]
  );
});

test("requirements use the redesign's bare counts", () => {
  const event = {id: "e", monthName: "October", startsOn: "2026-10-01",
    endsBefore: "2026-11-01"};
  const cases: Array<[string, number, string]> = [
    ["visits", 1, "Open Ascend in October"],
    ["climbs", 1, "1 climb"],
    ["climbs", 3, "3 climbs"],
    ["days", 1, "1 day"],
    ["days", 7, "7 days"],
    ["days", 31, "31 days"],
    ["onDay", 31, "Oct 31"],
    ["onDay", 1, "Oct 1"],
    ["steps", 10000, "10K steps"],
    ["steps", 12500, "12,500 steps"],
  ];
  for (const [metric, threshold, expected] of cases) {
    assert.equal(
      catalogueRequirement(item("x", "e", metric, threshold), event),
      expected,
      `${metric} ${threshold}`
    );
  }
  assert.equal(catalogueRequirement(item("x", "e", "dance", 1), event), null);
});

test("the drop renders through the queue with its unsubscribe link", () => {
  const job = {
    payload: halloween(),
    type: "drop_announcement",
  } as unknown as EmailJobDocument;

  const rendered = renderEmailContentForJob(job, {unsubscribeUrl: UNSUBSCRIBE});

  assert.equal(rendered.subject, "Halloween on the stair stepper");
  assert.ok(rendered.html.includes(
    "href=\"https://ascendstepper.com/api/unsubscribe?token=abc\""
  ));
  assert.match(rendered.text, /Unsubscribe: https:\/\/ascendstepper\.com\/api\/unsubscribe\?token=abc/);
  assert.match(rendered.text, /Climb tonight: https:\/\/apps\.apple\.com\/app\/id6757202987/);
  for (const dropItem of dropEmailItems(halloween())) {
    assert.ok(rendered.text.includes(dropItem.name), dropItem.name);
    assert.ok(rendered.html.includes(
      `${ASSETS}/${dropItem.imagePath}`
    ), dropItem.imagePath);
  }
});

test("the html stays inside what every target client draws", () => {
  const {html} = renderDropEmail(halloween(), {unsubscribeUrl: UNSUBSCRIBE});

  // Outlook on Windows drops an rgba colour outright.
  assert.doesNotMatch(html, /rgba\(/);
  // Layout is inline; the one <style> block only upsizes the header for
  // wide windows, so a client that drops it still draws the phone layout.
  // No positioning or flex/grid, which Gmail ignores.
  assert.equal((html.match(/<style>/g) ?? []).length, 1);
  assert.match(html, /<style>@media only screen and \(min-width:640px\)/);
  assert.doesNotMatch(html, /[;"]position:|display:flex|display:grid/);
  assert.doesNotMatch(html, /<svg/);
  assert.match(html, /<meta name="color-scheme" content="dark">/);
  // Hyphenated names never break across lines.
  assert.ok(html.includes("Jack&#8209;o&#39;&#8209;Lantern"));
});

test("tiles run three across, and a short last row is centred", () => {
  const {html} = renderDropEmail(halloween(), {});
  const steps = html.slice(
    html.indexOf("Steps in October"),
    html.indexOf("Days in October")
  );
  // Five step items: a full row of three and a centred row of two, every
  // tile the same third of the width.
  assert.equal((steps.match(/<td valign="top" width="33%"/g) ?? []).length, 3);
  assert.equal((steps.match(/<td valign="top" width="50%"/g) ?? []).length, 2);
  assert.match(steps, /width="100%" align="center"/);
  assert.match(steps, /width="67%" align="center"/);
});

test("with pictures blocked, every picture is a sized, filled box", () => {
  const {html} = renderDropEmail(halloween(), {});
  const images = html.match(/<img [^>]*>/g) ?? [];
  // The header art, 15 items and the feature picture; the brand mark and
  // the cobwebs are backgrounds, never an <img>.
  assert.equal(images.length, 17);
  for (const image of images) {
    assert.match(image, / width="\d+" height="\d+"/, image);
    assert.match(image, /alt="[^"]+"/, image);
    // A fill, or transparent for the header art cut out on the band's glow.
    assert.match(image, /background-color:(#[0-9a-f]{6}|transparent);/i, image);
    assert.match(image, /font-size:\d+px;/, image);
  }
  assert.doesNotMatch(html, /<img [^>]*ascend-a-icon/);
  assert.match(html, /background-image:url\('[^']*ascend-a-icon\.png'\)/);
});

test("the footer carries a postal address only when one is set", () => {
  const without = renderDropEmail(halloween(), {});
  assert.doesNotMatch(without.text, /PO Box/);
  const withAddress = renderDropEmail(
    {...halloween(), postalAddress: "Ascend, PO Box 1, Austin, TX 78701"},
    {}
  );
  assert.ok(withAddress.html.includes("Ascend, PO Box 1, Austin, TX 78701"));
  assert.ok(withAddress.text.includes("Ascend, PO Box 1, Austin, TX 78701"));
});

test("the footer draws Unsubscribe only from a signed link", () => {
  const {html, text} = renderDropEmail(halloween(), {});
  assert.doesNotMatch(html, /Unsubscribe/);
  assert.doesNotMatch(text, /Unsubscribe/);
});

test("a stored payload is validated before it is drawn", () => {
  const valid = halloween() as unknown as Record<string, unknown>;
  const broken: Array<[string, Record<string, unknown>]> = [
    ["theme", {...valid, theme: "christmas"}],
    ["http asset site", {...valid, assetBaseUrl: "http://ascendstepper.com"}],
    ["absolute image", {...valid, feature: {alt: "x", path: "https://evil.example/x.png"}}],
    ["parent image", {...valid, feature: {alt: "x", path: "images/../../x.png"}}],
    ["no groups", {...valid, groups: []}],
    ["empty group", {...valid, groups: [{heading: "Nothing", items: []}]}],
    ["blank subject", {...valid, subject: "  "}],
  ];
  for (const [label, payload] of broken) {
    assert.throws(
      () => parseDropEmailPayload(payload as unknown as EmailJobPayload),
      /drop_email_invalid_payload/,
      label
    );
  }
});

test("names from a payload are escaped", () => {
  const payload = halloween();
  payload.groups[1].items[0].name = "<script>x</script>";
  const {html} = renderDropEmail(payload, {});
  assert.doesNotMatch(html, /<script>/);
  assert.ok(html.includes("&lt;script&gt;x&lt;/script&gt;"));
});

test("every image the email draws is listed for the preflight", () => {
  const paths = dropEmailImagePaths(halloween());
  // The cobweb, 15 items (the header art is one of them) and the feature.
  assert.equal(paths.length, 17);

});

test("only a recorded yes with an address is in the audience", () => {
  const audience = selectDropAudience([
    {path: "users/b/communication_preferences/current",
      data: {lifecycleEmailsEnabled: true}},
    {path: "users/a/communication_preferences/current",
      data: {lifecycleEmailsEnabled: true}},
    {path: "users/c/communication_preferences/current",
      data: {lifecycleEmailsEnabled: false}},
    {path: "users/d/communication_preferences/current",
      data: {pushClimbDropsEnabled: true}},
    {path: "users/e/communication_preferences/current",
      data: {lifecycleEmailsEnabled: true}},
    {path: "teams/x/communication_preferences/current",
      data: {lifecycleEmailsEnabled: true}},
  ], new Map([
    ["a", "a@example.com"],
    ["b", "b@example.com"],
    ["c", "c@example.com"],
    ["d", "d@example.com"],
    ["e", null],
  ]));

  assert.deepEqual(audience.recipients, [
    {email: "a@example.com", uid: "a"},
    {email: "b@example.com", uid: "b"},
  ]);
  assert.equal(audience.notOptedIn, 2);
  assert.equal(audience.skippedNoEmail, 1);
});

test("preference paths resolve to their owner only", () => {
  assert.equal(
    preferenceOwnerUid("users/u1/communication_preferences/current"),
    "u1"
  );
  assert.equal(
    preferenceOwnerUid("users/u1/communication_preferences/other"),
    null
  );
  assert.equal(preferenceOwnerUid("teams/u1/communication_preferences/current"),
    null);
});

test("the real send and a test send never share a dedupe key", () => {
  assert.equal(buildDropDedupeKey("halloween-2026", "u1"),
    "drop:halloween-2026:u1");
  const testKey = buildDropTestDedupeKey("halloween-2026", "u1", "20261002");
  assert.equal(testKey, "drop-test:halloween-2026:u1:20261002");
  assert.ok(!testKey.startsWith("drop:halloween-2026:"));
});

test("every drop is keyed by its own id and names a minimum app version",
  () => {
    for (const [id, definition] of Object.entries(DROP_EMAILS)) {
      assert.equal(definition.content.dropId, id);
      assert.match(definition.minimumAppStoreVersion, /^\d+\.\d+(\.\d+)?$/);
      parseDropEmailPayload(buildDropEmailPayload(id, ASSETS));
    }
    assert.throws(() => buildDropEmailPayload("nope", ASSETS), /Unknown drop/);
  });

test("every picture is published under its own content hash", () => {
  // Runs from functions/lib/test; the site's files are web/public.
  const publicDir = join(__dirname, "..", "..", "..", "web", "public");
  const paths = dropEmailImagePaths(halloween());
  for (const path of paths) {
    const match = /-([0-9a-f]{12})\.(png|jpe?g)$/.exec(path);
    assert.ok(match, `${path} carries no content hash`);
    const file = join(publicDir, path);
    assert.ok(existsSync(file), `${path} is not published under web/public`);
    const hash = createHash("sha256").update(readFileSync(file)).digest("hex");
    assert.equal(hash.slice(0, 12), match[1], `${path} does not match its bytes`);
  }
});

test("the subject and preheader read as one thought", () => {
  const payload = halloween();
  assert.equal(payload.subject, "Halloween on the stair stepper");
  assert.match(payload.preheader, /^Open Ascend for a free Pumpkin/);
  const {html} = renderDropEmail(payload, {});
  // The preheader is padded so a preview never runs on into the body.
  assert.ok(html.includes("&#847;&zwnj;&nbsp;".repeat(90)));
});

test("no insider shorthand reaches the reader", () => {
  const {html, text} = renderDropEmail(halloween(), {});
  for (const phrase of [/pumpkin is (already )?in/i, /drop emails/i,
    /counts from/i]) {
    assert.doesNotMatch(text, phrase);
    assert.doesNotMatch(html, phrase);
  }
  // The header says Halloween once, in the headline; no pill repeats it.
  assert.doesNotMatch(html, />Halloween<\/span>/);
});

test("lime is only the button and the Free pill", () => {
  const {html} = renderDropEmail(halloween(), {});
  // Every lime anywhere is the button's fill, its glow, or the pill's fill.
  assert.equal((html.match(/background:#86D30A/gi) ?? []).length, 2);
  assert.equal((html.match(/#86D30A/gi) ?? []).length, 4);
});
