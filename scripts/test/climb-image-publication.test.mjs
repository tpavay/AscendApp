import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {fileURLToPath} from "node:url";

import {
  IMAGE_PREFIX,
  IMAGE_SIZES,
  candidateObjectPaths,
  resolveClimbImageSet,
} from "../sync-climb-images.mjs";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));

function read(path) {
  return readFileSync(`${repositoryRoot}/${path}`, "utf8");
}

function catalogClimbs() {
  const catalog = JSON.parse(read("web/public/climbs/catalog-v1.json"));
  return catalog.climbs ?? catalog;
}

/**
 * The audit is only a gate if it looks where the app looks. `candidateRemotePaths`
 * is the app's authority on that, so the two are pinned to each other rather
 * than to a remembered convention.
 */
test("the audit resolves the same candidate paths the app requests", () => {
  const repository = read(
    "AscendApp/Features/Climbs/Repositories/FirebaseClimbImageRepository.swift"
  );

  assert.match(
    repository,
    /"\\\(climb\.id\)\/v\\\(climb\.imageSetVersion\)\/\\\(variant\.rawValue\)\.heic"/,
    "the app's versioned path template changed - update candidateObjectPaths"
  );
  assert.match(
    repository,
    /"\\\(climb\.id\)\/\\\(variant\.rawValue\)\.heic"/,
    "the app's legacy fallback path template changed - update candidateObjectPaths"
  );
  assert.match(
    repository,
    /storage\.reference\(withPath: "climb-images\/\\\(remotePath\)"\)/,
    "the app's Storage prefix changed - update IMAGE_PREFIX"
  );

  assert.deepEqual(candidateObjectPaths({id: "macau-tower", imageSetVersion: 2}, "card"), [
    `${IMAGE_PREFIX}macau-tower/v2/card.heic`,
    `${IMAGE_PREFIX}macau-tower/card.heic`,
  ]);
  assert.deepEqual(candidateObjectPaths({id: "macau-tower"}, "hero"), [
    `${IMAGE_PREFIX}macau-tower/v1/hero.heic`,
    `${IMAGE_PREFIX}macau-tower/hero.heic`,
  ]);
});

test("a climb needs every variant before it counts as published", () => {
  const climb = {id: "az-tower", releaseState: "available"};
  const full = new Map(
    IMAGE_SIZES.map((size) => [`${IMAGE_PREFIX}az-tower/v1/${size}.heic`, {}])
  );

  assert.equal(resolveClimbImageSet(climb, full).complete, true);

  // A hero with no card is the case that reads worse than no artwork at all:
  // the card is the surface people browse.
  const partial = new Map(full);
  partial.delete(`${IMAGE_PREFIX}az-tower/v1/card.heic`);
  const partialResult = resolveClimbImageSet(climb, partial);
  assert.equal(partialResult.complete, false);
  assert.deepEqual(partialResult.missing, ["card"]);

  const absent = resolveClimbImageSet(climb, new Map());
  assert.equal(absent.complete, false);
  assert.deepEqual(absent.missing, IMAGE_SIZES);
});

test("artwork served only from the legacy path still counts as published", () => {
  const climb = {id: "gateway-arch", imageSetVersion: 1};
  const legacyOnly = new Map(
    IMAGE_SIZES.map((size) => [`${IMAGE_PREFIX}gateway-arch/${size}.heic`, {}])
  );

  const result = resolveClimbImageSet(climb, legacyOnly);
  assert.equal(result.complete, true, "the app falls back to the unversioned path");
  assert.deepEqual(
    result.found.map((entry) => entry.path).sort(),
    IMAGE_SIZES.map((size) => `${IMAGE_PREFIX}gateway-arch/${size}.heic`).sort()
  );
});

test("every available climb declares an image set the audit can demand", () => {
  const available = catalogClimbs().filter((climb) => climb.releaseState === "available");

  assert.ok(available.length > 0, "the catalog must publish at least one climb");
  for (const climb of available) {
    const version = climb.imageSetVersion ?? 1;
    assert.ok(
      Number.isInteger(version) && version >= 1,
      `${climb.id} has a non-integer imageSetVersion, so its image path is undefined`
    );
    assert.equal(
      resolveClimbImageSet(climb, new Map()).missing.length,
      IMAGE_SIZES.length,
      `${climb.id} must require all of ${IMAGE_SIZES.join(", ")}`
    );
  }
});

/**
 * The regression pin. Publishing the catalogue is what makes a climb browsable
 * and what triggers its drop notification, so the production Hosting deploy is
 * the last point anything can stop a climb going live with no artwork. On
 * 2026-08-10 nothing did, and 28 of 58 available climbs rendered as empty cards
 * for fifteen days. This fails if the audit is removed or reordered after the
 * deploy it guards.
 */
test("the production deploy audits artwork before it publishes the catalogue", () => {
  const workflow = read(".github/workflows/deploy-production.yml");

  const auditIndex = workflow.indexOf(
    "node scripts/sync-climb-images.mjs audit --project"
  );
  assert.notEqual(auditIndex, -1, "deploy-production must audit production climb artwork");

  const hostingIndex = workflow.indexOf("--only hosting");
  assert.notEqual(hostingIndex, -1, "deploy-production must deploy hosting");
  assert.ok(
    auditIndex < hostingIndex,
    "the artwork audit must run BEFORE the hosting deploy - after it, the empty cards are already live"
  );

  // Stronger than "before Hosting": a catalogue missing artwork should stop the
  // release without production having been touched at all.
  const firstDeployIndex = workflow.indexOf("firebase-tools@15.22.1 deploy");
  assert.notEqual(firstDeployIndex, -1, "deploy-production must deploy something");
  assert.ok(
    auditIndex < firstDeployIndex,
    "the artwork audit must run before the FIRST deploy step, so a failure leaves production untouched"
  );

  const authIndex = workflow.indexOf("google-github-actions/auth");
  assert.notEqual(
    authIndex,
    -1,
    "the audit reads the production bucket through the Admin SDK and needs a Google credential"
  );
  assert.ok(authIndex < auditIndex, "authentication must precede the audit");
  assert.match(
    workflow,
    /id-token: write/,
    "Workload Identity Federation needs the job's OIDC token"
  );
});
