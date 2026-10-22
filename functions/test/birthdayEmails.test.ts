import test from "node:test";
import assert from "node:assert/strict";
import {
  birthdayEligibility,
  buildBirthdayEmailPayload,
  couldBeBirthdayInAnyZone,
} from "../src/birthdayEmails";
import {renderEmailContentForJob} from "../src/email/catalog";
import {
  ageOnBirthday,
  birthdaySubject,
  buildBirthdayDedupeKey,
  celebrationDay,
  cleanFirstName,
  isBirthdayOn,
  isInBirthdaySendWindow,
  isLeapYear,
  localMomentIn,
  parseBirthDate,
} from "../src/email/birthday";
import {
  renderBirthdayEmail,
  renderBirthdayEmailFromPayload,
  renderWeeklyRecapActiveEmail,
  renderWeeklyRecapInactiveEmail,
} from "../src/email/templates";
import {EMAIL_TYPES} from "../src/email/types";
import type {EmailJobDocument, EmailJobPayload} from "../src/email/types";

const UNSUBSCRIBE = "https://ascendstepper.com/api/unsubscribe?token=abc";
const APP_URL = "https://apps.apple.com/app/id6757202987";

/**
 * Parses a birthday the test knows is valid.
 * @param {string} raw - "YYYY-MM-DD"
 * @return {NonNullable<ReturnType<typeof parseBirthDate>>} The birthday
 */
function birth(raw: string): NonNullable<ReturnType<typeof parseBirthDate>> {
  const parsed = parseBirthDate(raw);
  assert.ok(parsed, `expected ${raw} to parse`);
  return parsed;
}

test("birthday is a registered email type", () => {
  assert.ok((EMAIL_TYPES as readonly string[]).includes("birthday"));
});

test("the subject greets the climber by first name with a celebration emoji",
  () => {
    assert.equal(
      birthdaySubject("Tyler"),
      "Happy Birthday from Ascend, Tyler! \u{1F389}"
    );
    const rendered = renderBirthdayEmail(
      {ctaUrl: APP_URL, firstName: "Tyler"},
      {unsubscribeUrl: UNSUBSCRIBE}
    );
    assert.equal(
      rendered.subject,
      "Happy Birthday from Ascend, Tyler! \u{1F389}"
    );
  });

test("a climber with no usable name gets the nameless subject", () => {
  assert.equal(birthdaySubject(undefined), "Happy Birthday from Ascend! \u{1F389}");

  for (const stored of [undefined, null, "", "   ", "\n\t", "CHANGE", "change", 7]) {
    assert.equal(cleanFirstName(stored), null, `stored ${String(stored)}`);
    const payload = buildBirthdayEmailPayload(stored);
    assert.equal("firstName" in payload, false);

    const rendered = renderBirthdayEmailFromPayload(payload as EmailJobPayload);
    assert.equal(rendered.subject, "Happy Birthday from Ascend! \u{1F389}");
    assert.match(rendered.html, /HAPPY BIRTHDAY!/);
    assert.doesNotMatch(rendered.html, /HAPPY BIRTHDAY,/);
    assert.doesNotMatch(rendered.text, /undefined|null/);
  }
});

test("a stored name is cleaned before it reaches a subject or the HTML", () => {
  assert.equal(cleanFirstName("  Tyler\r\nBcc: x@y.z  "), "Tyler Bcc: x@y.z");
  assert.equal(cleanFirstName("a".repeat(100))?.length, 40);

  const rendered = renderBirthdayEmail(
    {ctaUrl: APP_URL, firstName: "<script>alert(1)</script>"},
    {unsubscribeUrl: UNSUBSCRIBE}
  );
  assert.doesNotMatch(rendered.html, /<script>/);
  assert.match(rendered.html, /&lt;SCRIPT&gt;/);
  assert.doesNotMatch(rendered.subject, /[\r\n]/);
});

test("the email carries the greeting, the challenge line, and the CTA", () => {
  const rendered = renderBirthdayEmail(
    {ctaUrl: APP_URL, firstName: "Tyler"},
    {unsubscribeUrl: UNSUBSCRIBE}
  );

  assert.match(rendered.html, /HAPPY BIRTHDAY, TYLER!/);
  assert.match(rendered.html, /Everyone at Ascend is wishing you a great one/);
  assert.match(rendered.html, /Climb one floor for every year of your age today\./);
  assert.match(rendered.html, /Start my birthday climb/);
  assert.ok(rendered.html.includes(`href="${APP_URL}"`));
  assert.match(rendered.text, /Start my birthday climb: https:\/\/apps\.apple\.com/);
  assert.match(
    rendered.text,
    /^Climb one floor for every year of your age today\.$/m
  );
  assert.match(
    rendered.text,
    /^You get this because you shared your birthday in Ascend\.$/m
  );
  assert.doesNotMatch(rendered.text, /board|optional/i);
  assert.ok(!rendered.html.includes("—") && !rendered.text.includes("—"));
});

test("the email wears the recap shell, footer, and unsubscribe link", () => {
  const rendered = renderBirthdayEmail(
    {ctaUrl: APP_URL, firstName: "Tyler"},
    {unsubscribeUrl: UNSUBSCRIBE}
  );

  assert.match(rendered.html, /<meta name="color-scheme" content="dark">/);
  assert.match(rendered.html, /ascend-a-icon\.png/);
  assert.match(rendered.html, /background:#86D30A/);
  assert.match(rendered.html, /Privacy Policy/);
  assert.ok(rendered.html.includes(`href="${UNSUBSCRIBE}"`));
  assert.match(rendered.text, /Unsubscribe: https:\/\/ascendstepper\.com/);

  const withoutLink = renderBirthdayEmail(
    {ctaUrl: APP_URL},
    {}
  );
  assert.doesNotMatch(withoutLink.html, /Unsubscribe/);
});

test("the email is plain text on the recap structure, with no age, box or label",
  () => {
    const rendered = renderBirthdayEmail(
      {ctaUrl: APP_URL, firstName: "Tyler"},
      {unsubscribeUrl: UNSUBSCRIBE}
    );

    // No bordered card, no big number and no eyebrow label: the body is the
    // cake, headline and two lines of copy, then the button.
    assert.doesNotMatch(rendered.html, /border-radius:20px/);
    assert.doesNotMatch(rendered.html, /font-size:56px/);
    assert.doesNotMatch(rendered.html, /letter-spacing:0\.22em/);
    assert.doesNotMatch(rendered.html, /Birthday Climb/);
    assert.doesNotMatch(rendered.text, /Birthday Climb/);
    assert.doesNotMatch(rendered.html, /floors, one for every year/i);
    assert.doesNotMatch(rendered.text, /\d+ floors?/);
    assert.doesNotMatch(rendered.text, /Your birthday climb:/);
    assert.doesNotMatch(rendered.html, />\d{1,3}<\/p>/);

    // Headline and body are left-aligned, as in every other Ascend email.
    const bodyRow = rendered.html.split("<tr>")
      .find((row) => row.includes("<h1")) ?? "";
    assert.doesNotMatch(bodyRow, /text-align:center/);
    assert.match(bodyRow, /padding:40px 30px 34px;/);
    assert.match(bodyRow, /<h1 style="margin:0 0 18px;font-size:34px;/);

    // The button sits in its own centered row, the same markup the active
    // recap ends its body with.
    const ctaRow = (html: string): string | undefined => html.match(
      /<tr><td style="padding:0 30px 40px;text-align:center;"><a [^]*?<\/a><\/td><\/tr>/
    )?.[0];
    const active = renderWeeklyRecapActiveEmail({
      calendar: [],
      climbsCompleted: 3,
      ctaUrl: APP_URL,
      earnedBadges: [],
      landmarksFinished: [],
      periodLabel: "Sep 15 - Sep 21",
      totalFloors: 210,
      totalSteps: 8500,
    });
    const birthdayCta = ctaRow(rendered.html);
    assert.ok(birthdayCta, "birthday button is in a centered row");
    assert.equal(
      birthdayCta?.replace(/>[^<]*<\/a>/, "></a>"),
      ctaRow(active.html)?.replace(/>[^<]*<\/a>/, "></a>")
    );
    assert.match(birthdayCta ?? "", />Start my birthday climb<\/a>/);

    // The headline wears the "We missed you" headline style.
    const inactive = renderWeeklyRecapInactiveEmail(
      {
        ctaUrl: APP_URL,
        earnedBadges: [],
        firstAscents: [],
        gapCount: 2,
        periodLabel: "Oct 5 - Oct 11",
      },
      {unsubscribeUrl: UNSUBSCRIBE}
    );
    const headlineStyle = "font-size:34px;line-height:1.1;font-weight:800;" +
      "color:#ffffff;letter-spacing:-0.02em;";
    assert.ok(inactive.html.includes(headlineStyle));
    assert.ok(rendered.html.includes(headlineStyle));
  });

test("birthday jobs render through the queue and reject a bad payload", () => {
  const job = {
    payload: buildBirthdayEmailPayload("Tyler"),
    type: "birthday",
  } as unknown as EmailJobDocument;
  const rendered = renderEmailContentForJob(job, {unsubscribeUrl: UNSUBSCRIBE});
  assert.equal(rendered.subject, "Happy Birthday from Ascend, Tyler! \u{1F389}");

  for (const bad of [
    {},
    {firstName: "Tyler"},
    {ctaUrl: "not a url"},
  ]) {
    assert.throws(
      () => renderEmailContentForJob(
        {payload: bad, type: "birthday"} as unknown as EmailJobDocument
      ),
      /invalid_birthday_payload/
    );
  }
});

test("a stored birth_date must be a real calendar date", () => {
  assert.deepEqual(parseBirthDate("1992-10-22"), {day: 22, month: 10, year: 1992});
  assert.deepEqual(parseBirthDate("1992-02-29"), {day: 29, month: 2, year: 1992});
  for (const raw of [
    undefined, null, 19921022, "", "1992-1-22", "92-10-22", "1992-13-01",
    "1992-00-10", "1992-04-31", "1993-02-29", "1900-02-29", "1992-10-22T00:00",
  ]) {
    assert.equal(parseBirthDate(raw), null, String(raw));
  }
  assert.ok(parseBirthDate("2000-02-29"));
});

test("a February 29 birthday is celebrated on February 28 in a common year",
  () => {
    const leapling = birth("1996-02-29");

    assert.equal(isLeapYear(2028), true);
    assert.equal(isLeapYear(2100), false);
    assert.equal(isLeapYear(2000), true);
    assert.deepEqual(celebrationDay(leapling, 2028), {day: 29, month: 2});
    assert.deepEqual(celebrationDay(leapling, 2027), {day: 28, month: 2});
    assert.deepEqual(celebrationDay(leapling, 2100), {day: 28, month: 2});

    const feb28 = {day: 28, hour: 9, month: 2, year: 2027};
    const mar1 = {day: 1, hour: 9, month: 3, year: 2027};
    assert.equal(isBirthdayOn(leapling, feb28), true);
    assert.equal(isBirthdayOn(leapling, mar1), false);
    // In a leap year it is the 29th, and the 28th is an ordinary day.
    assert.equal(isBirthdayOn(leapling, {...feb28, year: 2028}), false);
    assert.equal(
      isBirthdayOn(leapling, {day: 29, hour: 9, month: 2, year: 2028}),
      true
    );
    // A real February 28 birthday is unaffected.
    assert.equal(isBirthdayOn(birth("1995-02-28"), feb28), true);
    assert.equal(ageOnBirthday(leapling, 2027), 31);
  });

test("a February 29 birthday sends on February 28 and never twice", () => {
  const leapling = birth("1996-02-29");
  const feb28 = new Date("2027-02-28T16:00:00Z");
  const mar1 = new Date("2027-03-01T16:00:00Z");

  assert.deepEqual(
    birthdayEligibility(leapling, "America/Chicago", feb28),
    {age: 31, year: 2027}
  );
  assert.equal(birthdayEligibility(leapling, "America/Chicago", mar1), null);
  assert.equal(
    birthdayEligibility(leapling, "America/Chicago", new Date("2028-02-28T16:00:00Z")),
    null
  );
  assert.deepEqual(
    birthdayEligibility(leapling, "America/Chicago", new Date("2028-02-29T16:00:00Z")),
    {age: 32, year: 2028}
  );
});

test("a birthday is due from 9 AM until the evening in the climber's zone",
  () => {
    const climber = birth("1992-10-22");
    const at = (iso: string, zone: string) =>
      birthdayEligibility(climber, zone, new Date(iso));

    // 2026-10-22 13:59Z is 08:59 in Chicago (CDT): not yet.
    assert.equal(at("2026-10-22T13:59:00Z", "America/Chicago"), null);
    assert.deepEqual(
      at("2026-10-22T14:00:00Z", "America/Chicago"),
      {age: 34, year: 2026}
    );
    assert.deepEqual(
      at("2026-10-23T01:59:00Z", "America/Chicago"),
      {age: 34, year: 2026}
    );
    // 02:00Z is 21:00 Chicago: the morning greeting window has closed.
    assert.equal(at("2026-10-23T02:00:00Z", "America/Chicago"), null);

    // The same instant is a different local day elsewhere.
    // 12:00Z is 21:00 in Tokyo: that morning's window has closed there.
    assert.equal(at("2026-10-22T12:00:00Z", "Asia/Tokyo"), null);
    assert.deepEqual(
      at("2026-10-22T00:00:00Z", "Asia/Tokyo"),
      {age: 34, year: 2026}
    );
    assert.deepEqual(
      at("2026-10-22T17:00:00Z", "America/Los_Angeles"),
      {age: 34, year: 2026}
    );
    // Auckland is already on the 23rd by the time Los Angeles reaches 9 AM.
    assert.equal(at("2026-10-22T17:00:00Z", "Pacific/Auckland"), null);
  });

test("an unknown zone falls back to the default zone instead of throwing", () => {
  const instant = new Date("2026-10-22T15:00:00Z");
  assert.deepEqual(
    localMomentIn(instant, "Not/AZone"),
    localMomentIn(instant, "America/Chicago")
  );
  assert.deepEqual(
    birthdayEligibility(birth("1992-10-22"), "garbage", instant),
    {age: 34, year: 2026}
  );
});

test("the send window is a half-open local range", () => {
  const moment = (hour: number) => ({day: 1, hour, month: 1, year: 2026});
  assert.equal(isInBirthdaySendWindow(moment(8)), false);
  assert.equal(isInBirthdaySendWindow(moment(9)), true);
  assert.equal(isInBirthdaySendWindow(moment(20)), true);
  assert.equal(isInBirthdaySendWindow(moment(21)), false);
  assert.equal(isInBirthdaySendWindow(moment(0)), false);
});

test("a corrupt age never gets a birthday email", () => {
  const instant = new Date("2026-10-22T15:00:00Z");
  assert.equal(birthdayEligibility(birth("2020-10-22"), "UTC", instant), null);
  assert.equal(birthdayEligibility(birth("1850-10-22"), "UTC", instant), null);
  assert.equal(birthdayEligibility(birth("2026-10-22"), "UTC", instant), null);
});

test("the dedupe key is one per climber per year", () => {
  assert.equal(buildBirthdayDedupeKey("user_1", 2026), "birthday-email:2026:user_1");
  assert.notEqual(
    buildBirthdayDedupeKey("user_1", 2026),
    buildBirthdayDedupeKey("user_1", 2027)
  );
  assert.notEqual(
    buildBirthdayDedupeKey("user_1", 2026),
    buildBirthdayDedupeKey("user_2", 2026)
  );
});

test("only birthdays near today in some zone are worth a zone lookup", () => {
  const now = new Date("2026-10-22T15:00:00Z");
  assert.equal(couldBeBirthdayInAnyZone(birth("1992-10-22"), now), true);
  // 15:00Z is already the 23rd in Auckland and still the 22nd in Honolulu, so
  // the 21st is past everywhere and the 23rd is not.
  assert.equal(couldBeBirthdayInAnyZone(birth("1992-10-21"), now), false);
  assert.equal(couldBeBirthdayInAnyZone(birth("1992-10-23"), now), true);
  assert.equal(couldBeBirthdayInAnyZone(birth("1992-10-24"), now), false);
  assert.equal(couldBeBirthdayInAnyZone(birth("1992-03-14"), now), false);
  assert.equal(
    couldBeBirthdayInAnyZone(birth("1996-02-29"), new Date("2027-02-28T12:00:00Z")),
    true
  );
});

test("the payload omits the name rather than storing undefined", () => {
  assert.deepEqual(buildBirthdayEmailPayload("Tyler"), {
    ctaUrl: APP_URL,
    firstName: "Tyler",
  });
  assert.deepEqual(buildBirthdayEmailPayload(""), {
    ctaUrl: APP_URL,
  });
});
