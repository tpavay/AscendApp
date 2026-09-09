import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

// An allowlist entry that never expires is a permanent, unreviewed
// suppression wearing a temporary one's clothes. This bounds how far out an
// expiry may be set, so accepting a suppression always means scheduling its
// own re-review rather than forgetting about it.
const MAX_ALLOWLIST_WINDOW_DAYS = 180;

const GHSA_PATTERN = /^GHSA-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}$/;
const ISO_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

const CONFIG_PATHS = [
  "audit-ci.json",
  "functions/audit-ci.json",
  "scripts/audit-ci.json",
  "web/audit-ci.json",
];

function readConfig(path) {
  const raw = readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
  return JSON.parse(raw);
}

for (const path of CONFIG_PATHS) {
  test(`${path} fails the gate on low-or-higher severity, exactly like the audit-level it replaced`, () => {
    const config = readConfig(path);
    assert.equal(config.low, true, `${path} must set "low": true`);
  });

  test(`${path} allowlist entries are reviewable advisory suppressions with a bounded expiry`, () => {
    const config = readConfig(path);
    assert.ok(
      Array.isArray(config.allowlist),
      `${path} must declare an "allowlist" array`,
    );

    const now = Date.now();
    const maxExpiry = now + MAX_ALLOWLIST_WINDOW_DAYS * 24 * 60 * 60 * 1000;

    for (const entry of config.allowlist) {
      assert.equal(
        typeof entry,
        "object",
        `${path}: allowlist entries must be objects keyed by advisory ID, ` +
          "never a bare string - a bare string carries no reason or expiry " +
          "and audit-ci treats it as suppressed forever",
      );

      const keys = Object.keys(entry);
      assert.equal(
        keys.length,
        1,
        `${path}: each allowlist entry must have exactly one advisory key`,
      );

      const [advisoryId] = keys;
      assert.match(
        advisoryId,
        GHSA_PATTERN,
        `${path}: "${advisoryId}" must be a GitHub Security Advisory ID ` +
          "(GHSA-xxxx-xxxx-xxxx), not a module name or dependency path - " +
          "those suppress every current and future advisory for that " +
          "dependency instead of the one advisory under review",
      );

      const record = entry[advisoryId];

      assert.equal(
        typeof record.active,
        "boolean",
        `${path}: "${advisoryId}" must carry a boolean "active" field`,
      );

      assert.equal(
        typeof record.notes,
        "string",
        `${path}: "${advisoryId}" must carry a "notes" string explaining ` +
          "why it can't be fixed yet",
      );
      assert.ok(
        record.notes.trim().length > 0,
        `${path}: "${advisoryId}" notes must not be empty`,
      );

      assert.equal(
        typeof record.expiry,
        "string",
        `${path}: "${advisoryId}" must carry an "expiry" date`,
      );
      assert.match(
        record.expiry,
        ISO_DATE_PATTERN,
        `${path}: "${advisoryId}" expiry must be an ISO "YYYY-MM-DD" date`,
      );

      const expiryDate = new Date(`${record.expiry}T00:00:00Z`);
      assert.ok(
        !Number.isNaN(expiryDate.getTime()),
        `${path}: "${advisoryId}" expiry "${record.expiry}" is not a valid date`,
      );
      assert.ok(
        expiryDate.getTime() <= maxExpiry,
        `${path}: "${advisoryId}" expiry "${record.expiry}" is more than ` +
          `${MAX_ALLOWLIST_WINDOW_DAYS} days out - shorten it so the ` +
          "suppression forces a real re-review",
      );
    }
  });
}
