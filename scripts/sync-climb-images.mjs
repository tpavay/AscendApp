#!/usr/bin/env node

/**
 * Ascend Climb Image Sync Tool
 *
 * Audits, diffs, uploads, and syncs climb artwork (climb-images/) across the
 * dev, staging, and production Firebase Storage buckets. Climb images are
 * remote-only content - the app ships no artwork - so every environment's
 * bucket must carry the images its hosted catalog references.
 *
 * Unlike the fixture seeders, production is a legitimate TARGET here (this is
 * content publishing, not test data). Any write to production requires the
 * explicit --confirm-production flag.
 *
 * Usage:
 *   node scripts/sync-climb-images.mjs audit --project dev
 *   node scripts/sync-climb-images.mjs diff --from staging --to production
 *   node scripts/sync-climb-images.mjs sync --from staging --to production --dry-run
 *   node scripts/sync-climb-images.mjs sync --from staging --to production --confirm-production
 *   node scripts/sync-climb-images.mjs sync --from staging --to dev --climb burj-khalifa
 *   node scripts/sync-climb-images.mjs upload --project staging --climb burj-khalifa --dir ~/art/burj --image-set-version 2
 */

import {existsSync, readFileSync} from "node:fs";
import {resolve, dirname, join} from "node:path";
import {fileURLToPath} from "node:url";
import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getStorage} from "firebase-admin/storage";
import {
  PRODUCTION_PROJECT_ID,
  resolveProjectId,
  seedEnvironmentName,
} from "./seed/lib/environments.mjs";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, "..");
const CATALOG_PATH = resolve(REPO_ROOT, "web/public/climbs/catalog-v1.json");

export const IMAGE_PREFIX = "climb-images/";
export const IMAGE_SIZES = ["hero", "card", "thumb"];
const IMAGE_CONTENT_TYPE = "image/heic";
// Versioned paths are immutable - a new image set bumps imageSetVersion and
// gets a new path - so clients and CDNs may cache aggressively.
const IMAGE_CACHE_CONTROL = "public, max-age=604800, immutable";

const apps = new Map();

function appFor(projectId) {
  if (!apps.has(projectId)) {
    apps.set(
      projectId,
      initializeApp(
        {
          credential: applicationDefault(),
          projectId,
          storageBucket: `${projectId}.firebasestorage.app`,
        },
        projectId
      )
    );
  }
  return apps.get(projectId);
}

function bucketFor(projectId) {
  return getStorage(appFor(projectId)).bucket();
}

function parseArgs(argv) {
  const [command, ...rest] = argv;
  const flags = {};
  for (let index = 0; index < rest.length; index++) {
    const arg = rest[index];
    if (!arg.startsWith("--")) {
      throw new Error(`Unexpected argument: ${arg}`);
    }
    const key = arg.slice(2);
    const next = rest[index + 1];
    if (next === undefined || next.startsWith("--")) {
      flags[key] = true;
    } else {
      flags[key] = next;
      index++;
    }
  }
  return {command, flags};
}

function requireProject(flags, name) {
  const value = flags[name];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`--${name} <dev|staging|production> is required.`);
  }
  return resolveProjectId(value, REPO_ROOT);
}

function assertWritableTarget(projectId, flags) {
  if (projectId === PRODUCTION_PROJECT_ID && flags["confirm-production"] !== true) {
    throw new Error(
      `Refusing to write to production (${projectId}) without --confirm-production.`
    );
  }
}

function loadCatalog() {
  return JSON.parse(readFileSync(CATALOG_PATH, "utf-8"));
}

/**
 * The paths the app will actually try for one variant, in the order it tries
 * them. This mirrors `FirebaseClimbImageRepository.candidateRemotePaths`: the
 * versioned path first, then the unversioned legacy path. An audit that only
 * knew the versioned path would report a legacy-served climb as MISSING, and a
 * gate that cries wolf is a gate somebody turns off.
 */
export function candidateObjectPaths(climb, size) {
  const version = climb.imageSetVersion ?? 1;
  return [
    `${IMAGE_PREFIX}${climb.id}/v${version}/${size}.heic`,
    `${IMAGE_PREFIX}${climb.id}/${size}.heic`,
  ];
}

function expectedObjectPaths(catalog) {
  const paths = new Map();
  for (const climb of catalog.climbs ?? catalog) {
    for (const size of IMAGE_SIZES) {
      paths.set(candidateObjectPaths(climb, size)[0], {
        climbId: climb.id,
        releaseState: climb.releaseState,
        size,
      });
    }
  }
  return paths;
}

/**
 * What the app would find for one climb. A climb is only publishable when every
 * variant resolves: a hero with no card renders worse than a climb with no
 * artwork at all, because the card is the surface people browse.
 */
export function resolveClimbImageSet(climb, actual) {
  const found = [];
  const missing = [];
  for (const size of IMAGE_SIZES) {
    const hit = candidateObjectPaths(climb, size).find((path) => actual.has(path));
    if (hit) found.push({size, path: hit});
    else missing.push(size);
  }
  return {climb, found, missing, complete: missing.length === 0};
}

async function listImageObjects(projectId) {
  const [files] = await bucketFor(projectId).getFiles({prefix: IMAGE_PREFIX});
  const objects = new Map();
  for (const file of files) {
    objects.set(file.name, {
      md5: file.metadata.md5Hash ?? null,
      size: Number(file.metadata.size ?? 0),
    });
  }
  return objects;
}

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

async function commandAudit(flags) {
  const projectId = requireProject(flags, "project");
  const catalog = loadCatalog();
  const climbs = catalog.climbs ?? catalog;
  const expected = expectedObjectPaths(catalog);
  const actual = await listImageObjects(projectId);

  // A control probe, not decoration. A listing that failed and a bucket that is
  // empty both produce an empty map, and reporting the second when it was the
  // first is how a green audit gets published over a bucket nobody could read.
  if (actual.size === 0) {
    process.exitCode = 1;
    console.log(
      `Climb image audit - ${seedEnvironmentName(projectId)} (${projectId})\n` +
        `  Listed ZERO objects under ${IMAGE_PREFIX}. Refusing to call that a verified ` +
        "empty bucket: an unauthorized or misrouted listing looks identical."
    );
    return;
  }

  const sets = climbs.map((climb) => resolveClimbImageSet(climb, actual));
  const incompleteAvailable = sets.filter(
    (set) => set.climb.releaseState === "available" && !set.complete
  );
  const incompleteOther = sets.filter(
    (set) => set.climb.releaseState !== "available" && !set.complete
  );
  const orphans = [...actual.keys()].filter((path) => !expected.has(path));

  console.log(`Climb image audit - ${seedEnvironmentName(projectId)} (${projectId})`);
  console.log(`  catalog climbs: ${sets.length}`);
  console.log(`  objects in bucket under ${IMAGE_PREFIX}: ${actual.size}`);
  console.log(
    `  AVAILABLE climbs: ${sets.filter((set) => set.climb.releaseState === "available").length}` +
      ` (${incompleteAvailable.length} without a complete image set)`
  );
  for (const set of incompleteAvailable) {
    const state = set.found.length === 0 ? "NO IMAGES" : `PARTIAL (${set.found.length}/3)`;
    console.log(`    ${state} ${set.climb.id} - missing ${set.missing.join(", ")}`);
  }
  console.log(`  unreleased climbs without a complete set: ${incompleteOther.length}`);
  for (const set of incompleteOther) {
    console.log(`    [${set.climb.releaseState}] ${set.climb.id} - missing ${set.missing.join(", ")}`);
  }
  console.log(`  objects not referenced by current catalog: ${orphans.length}`);
  for (const path of orphans) {
    console.log(`    EXTRA ${path}`);
  }

  if (incompleteAvailable.length > 0) {
    process.exitCode = 1;
    console.log(
      `\n${incompleteAvailable.length} AVAILABLE climb(s) lack a complete image set in ` +
        `${seedEnvironmentName(projectId)}. Every one of them renders as an empty card on the ` +
        "browse surface. Publish the artwork before publishing the catalog:\n" +
        `  node scripts/sync-climb-images.mjs sync --from staging --to ${seedEnvironmentName(projectId)}` +
        `${projectId === PRODUCTION_PROJECT_ID ? " --confirm-production" : ""}`
    );
  }
}

function computeCopyPlan(sourceObjects, targetObjects, climbFilter) {
  const plan = [];
  for (const [path, sourceInfo] of sourceObjects) {
    if (climbFilter && !path.startsWith(`${IMAGE_PREFIX}${climbFilter}/`)) {
      continue;
    }
    const targetInfo = targetObjects.get(path);
    if (!targetInfo) {
      plan.push({path, reason: "missing", bytes: sourceInfo.size});
    } else if (targetInfo.md5 !== sourceInfo.md5) {
      plan.push({path, reason: "changed", bytes: sourceInfo.size});
    }
  }
  return plan;
}

async function commandDiff(flags) {
  const fromProject = requireProject(flags, "from");
  const toProject = requireProject(flags, "to");
  const [sourceObjects, targetObjects] = await Promise.all([
    listImageObjects(fromProject),
    listImageObjects(toProject),
  ]);
  const plan = computeCopyPlan(sourceObjects, targetObjects, flags.climb);
  const onlyInTarget = [...targetObjects.keys()].filter((path) => !sourceObjects.has(path));

  console.log(
    `Diff ${seedEnvironmentName(fromProject)} → ${seedEnvironmentName(toProject)}: ` +
      `${plan.length} object(s) would copy, ${onlyInTarget.length} exist only in target`
  );
  for (const item of plan) {
    console.log(`  ${item.reason.toUpperCase()} ${item.path} (${formatBytes(item.bytes)})`);
  }
  for (const path of onlyInTarget) {
    console.log(`  TARGET-ONLY ${path}`);
  }
}

async function commandSync(flags) {
  const fromProject = requireProject(flags, "from");
  const toProject = requireProject(flags, "to");
  if (fromProject === toProject) {
    throw new Error("--from and --to must be different environments.");
  }
  const dryRun = flags["dry-run"] === true;
  if (!dryRun) {
    assertWritableTarget(toProject, flags);
  }

  const [sourceObjects, targetObjects] = await Promise.all([
    listImageObjects(fromProject),
    listImageObjects(toProject),
  ]);
  const plan = computeCopyPlan(sourceObjects, targetObjects, flags.climb);
  const totalBytes = plan.reduce((sum, item) => sum + item.bytes, 0);

  console.log(
    `Sync ${seedEnvironmentName(fromProject)} → ${seedEnvironmentName(toProject)}: ` +
      `${plan.length} object(s), ${formatBytes(totalBytes)}${dryRun ? " (dry run)" : ""}`
  );

  if (plan.length === 0) {
    console.log("Nothing to copy - target is up to date.");
    return;
  }

  const sourceBucket = bucketFor(fromProject);
  const targetBucket = bucketFor(toProject);
  for (const item of plan) {
    console.log(`  ${dryRun ? "would copy" : "copying"} ${item.path}`);
    if (dryRun) continue;
    await sourceBucket.file(item.path).copy(targetBucket.file(item.path));
    // contentType is pinned rather than inherited. A copy carries the source
    // object's metadata, so a source uploaded through the console with a
    // guessed type would propagate that guess into production, where the app
    // decodes the bytes as HEIC or shows nothing.
    await targetBucket.file(item.path).setMetadata({
      cacheControl: IMAGE_CACHE_CONTROL,
      contentType: IMAGE_CONTENT_TYPE,
    });
  }

  if (!dryRun) {
    console.log(`Copied ${plan.length} object(s). Run audit --project ${flags.to} to verify.`);
  }
}

async function commandUpload(flags) {
  const projectId = requireProject(flags, "project");
  assertWritableTarget(projectId, flags);

  const climbId = flags.climb;
  if (typeof climbId !== "string" || climbId.length === 0) {
    throw new Error("--climb <climb-id> is required.");
  }
  const directory = flags.dir;
  if (typeof directory !== "string" || !existsSync(directory)) {
    throw new Error("--dir <folder containing hero.heic, card.heic, thumb.heic> is required.");
  }
  const version = Number(flags["image-set-version"] ?? 1);
  if (!Number.isInteger(version) || version < 1) {
    throw new Error("--image-set-version must be a positive integer.");
  }

  const localFiles = IMAGE_SIZES.map((size) => ({
    size,
    localPath: join(directory, `${size}.heic`),
    remotePath: `${IMAGE_PREFIX}${climbId}/v${version}/${size}.heic`,
  }));
  const missingLocal = localFiles.filter((file) => !existsSync(file.localPath));
  if (missingLocal.length > 0) {
    throw new Error(
      `Missing local files: ${missingLocal.map((file) => file.localPath).join(", ")}`
    );
  }

  const bucket = bucketFor(projectId);
  for (const file of localFiles) {
    console.log(`  uploading ${file.remotePath}`);
    await bucket.upload(file.localPath, {
      destination: file.remotePath,
      metadata: {
        cacheControl: IMAGE_CACHE_CONTROL,
        contentType: IMAGE_CONTENT_TYPE,
      },
    });
  }
  console.log(
    `Uploaded ${localFiles.length} image(s) for ${climbId} v${version} to ` +
      `${seedEnvironmentName(projectId)}. Ensure the catalog's imageSetVersion matches.`
  );
}

function printUsage() {
  console.log(`Commands:
  audit  --project <env>                       Check bucket contents against the catalog
  diff   --from <env> --to <env> [--climb id]  Show what sync would copy
  sync   --from <env> --to <env> [--climb id] [--dry-run] [--confirm-production]
  upload --project <env> --climb <id> --dir <folder> [--image-set-version n] [--confirm-production]

Environments: dev, staging, production. Writes to production require --confirm-production.`);
}

async function main() {
  const {command, flags} = parseArgs(process.argv.slice(2));
  switch (command) {
  case "audit":
    await commandAudit(flags);
    break;
  case "diff":
    await commandDiff(flags);
    break;
  case "sync":
    await commandSync(flags);
    break;
  case "upload":
    await commandUpload(flags);
    break;
  default:
    printUsage();
    process.exitCode = command ? 1 : 0;
  }
}

// Guarded so the contract test can import the path helpers without the CLI
// running - the helpers are the half that must not drift from the app.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error.message ?? error);
    process.exit(1);
  });
}
