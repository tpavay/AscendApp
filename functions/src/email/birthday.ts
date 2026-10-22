/**
 * Pure rules for the birthday email: reading the stored birthday, deciding
 * whether today is it in the climber's own time zone, and wording the greeting.
 * Nothing here touches Firestore, so every rule is testable without it.
 */

/** A calendar birthday as `ProfileBirthday` stores it: no time zone. */
export interface BirthDate {
  day: number;
  month: number;
  year: number;
}

/** A wall-clock instant read in one time zone. */
export interface LocalMoment {
  day: number;
  hour: number;
  month: number;
  year: number;
}

/**
 * The zone a climber with no registered device is greeted in. Central is the
 * middle of the US population, so a 9 AM send lands between 7 AM Pacific and
 * 10 AM Eastern instead of before dawn on one coast.
 */
export const DEFAULT_BIRTHDAY_TIME_ZONE = "America/Chicago";
/** Local hour the greeting becomes eligible: "around 9 AM". */
export const BIRTHDAY_SEND_HOUR = 9;
/**
 * Local hour the greeting stops being eligible. Between the two, every hourly
 * sweep may retry a climber the earlier sweeps missed, but a morning greeting
 * never arrives in the evening.
 */
export const BIRTHDAY_SEND_CUTOFF_HOUR = 21;

const BIRTH_DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;
const MAX_FIRST_NAME_LENGTH = 40;
/**
 * The stored first name for an Apple or Google sign-in that supplied none
 * (`SignInNamePlaceholder`). It is an instruction to the climber, not a name.
 */
const PLACEHOLDER_FIRST_NAME = "change";

/**
 * Whether a year is a Gregorian leap year.
 * @param {number} year - Calendar year
 * @return {boolean} True when February has 29 days
 */
export function isLeapYear(year: number): boolean {
  return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
}

/**
 * Parses the profile's raw `birth_date`, refusing anything that is not a real
 * calendar date.
 * @param {unknown} value - Stored `birth_date`, "YYYY-MM-DD"
 * @return {BirthDate | null} The birthday, or null when unusable
 */
export function parseBirthDate(value: unknown): BirthDate | null {
  if (typeof value !== "string") {
    return null;
  }
  const match = BIRTH_DATE_PATTERN.exec(value);
  if (!match) {
    return null;
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (year < 1 || month < 1 || month > 12 || day < 1) {
    return null;
  }
  const daysInMonth = [
    31, isLeapYear(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31,
  ][month - 1];
  return day <= daysInMonth ? {day, month, year} : null;
}

/**
 * The calendar day a birthday is celebrated on in a given year. A February 29
 * birthday moves to February 28 in a year without one, so it is never skipped.
 * @param {BirthDate} birth - The climber's birthday
 * @param {number} year - The year being celebrated
 * @return {{month: number, day: number}} Month and day of the celebration
 */
export function celebrationDay(
  birth: BirthDate,
  year: number
): {day: number; month: number} {
  if (birth.month === 2 && birth.day === 29 && !isLeapYear(year)) {
    return {day: 28, month: 2};
  }
  return {day: birth.day, month: birth.month};
}

/**
 * Whether a wall-clock date is the climber's birthday.
 * @param {BirthDate} birth - The climber's birthday
 * @param {LocalMoment} local - The climber's local date
 * @return {boolean} True on the celebration day
 */
export function isBirthdayOn(birth: BirthDate, local: LocalMoment): boolean {
  const target = celebrationDay(birth, local.year);
  return target.month === local.month && target.day === local.day;
}

/**
 * Whether a local moment is inside the morning window the greeting is sent in.
 * @param {LocalMoment} local - The climber's local time
 * @return {boolean} True from 9 AM until the evening cutoff
 */
export function isInBirthdaySendWindow(local: LocalMoment): boolean {
  return local.hour >= BIRTHDAY_SEND_HOUR &&
    local.hour < BIRTHDAY_SEND_CUTOFF_HOUR;
}

/**
 * The age a climber turns on the birthday being celebrated.
 * @param {BirthDate} birth - The climber's birthday
 * @param {number} year - The year being celebrated
 * @return {number} Age in whole years
 */
export function ageOnBirthday(birth: BirthDate, year: number): number {
  return year - birth.year;
}

/**
 * Whether a string names a time zone this runtime can format in.
 * @param {string} timeZone - Candidate IANA zone name
 * @return {boolean} True when `Intl` accepts it
 */
export function isValidTimeZone(timeZone: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", {timeZone}).format(0);
    return true;
  } catch {
    return false;
  }
}

/**
 * Reads an instant as wall-clock parts in a time zone, falling back to the
 * default zone when the given one is not a real zone.
 * @param {Date} instant - The instant to read
 * @param {string} timeZone - IANA zone name
 * @return {LocalMoment} Date and hour on that zone's clock
 */
export function localMomentIn(instant: Date, timeZone: string): LocalMoment {
  const zone = isValidTimeZone(timeZone) ?
    timeZone :
    DEFAULT_BIRTHDAY_TIME_ZONE;
  const parts = new Intl.DateTimeFormat("en-US", {
    day: "numeric",
    hour: "numeric",
    hourCycle: "h23",
    month: "numeric",
    timeZone: zone,
    year: "numeric",
  }).formatToParts(instant);
  const read = (type: string): number =>
    Number(parts.find((part) => part.type === type)?.value);
  return {
    day: read("day"),
    hour: read("hour"),
    month: read("month"),
    year: read("year"),
  };
}

/**
 * The one-send dedupe key: one greeting per climber per calendar year.
 * @param {string} uid - Firebase Auth user ID
 * @param {number} year - Local year of the birthday being celebrated
 * @return {string} Stable dedupe key
 */
export function buildBirthdayDedupeKey(uid: string, year: number): string {
  return `birthday-email:${year}:${uid}`;
}

/**
 * Cleans a stored first name for use in a subject line and greeting.
 *
 * Returns null for anything that is not a name worth greeting: empty, the
 * sign-in placeholder, or control characters only. Whitespace is collapsed
 * and control characters removed so a stored name can never break a header.
 * @param {unknown} value - Stored first name
 * @return {string | null} Display-safe first name, or null
 */
export function cleanFirstName(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  // eslint-disable-next-line no-control-regex
  const cleaned = value.replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, MAX_FIRST_NAME_LENGTH)
    .trim();
  if (
    cleaned.length === 0 ||
    cleaned.toLowerCase() === PLACEHOLDER_FIRST_NAME
  ) {
    return null;
  }
  return cleaned;
}

/**
 * The subject line, with the nameless greeting when no name is on file.
 * @param {string | undefined} firstName - Cleaned first name, when known
 * @return {string} Subject line
 */
export function birthdaySubject(firstName: string | undefined): string {
  return firstName ?
    `Happy Birthday from Ascend, ${firstName}! \u{1F389}` :
    "Happy Birthday from Ascend! \u{1F389}";
}
