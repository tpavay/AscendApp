#!/usr/bin/env node

/**
 * Read-only Firestore and Storage investigation.
 *
 * This exists because hand-rolled `curl` and `grep` answered "is there data
 * here?" wrongly six times in one session, always the same way: a query that
 * never ran produced no output, and no output was reported as an empty
 * database. Every mechanical trap that caused those - resolving credentials,
 * the literal `(default)` database ID inside a shell loop, prefix matching that
 * is really substring matching - is owned here so nobody re-derives it.
 *
 * The tool never writes. It reports exactly one of four outcomes and refuses to
 * collapse them: FOUND, EMPTY (verified), EMPTY (UNVERIFIED), FAILED.
 *
 * Usage:
 *   node scripts/firestore-query.mjs collections --env dev
 *   node scripts/firestore-query.mjs count users/<uid>/workouts --env staging
 *   node scripts/firestore-query.mjs list live_replay_leaderboards --env dev --limit 5
 *   node scripts/firestore-query.mjs get live_replay_leaderboards/live_climb__burj-khalifa --env dev
 *   node scripts/firestore-query.mjs subcollections live_replay_leaderboards/live_climb__burj-khalifa \
 *     --env dev --expect finishers,splitBuckets,completionSnapshots
 *   node scripts/firestore-query.mjs storage profile_pictures/ --env staging
 *   node scripts/firestore-query.mjs count users --env prod --confirm-production
 *
 * With the Firestore emulator running and no --env, every command reads the
 * emulator instead.
 *
 * Prerequisites:
 *   Node.js 20+
 *   cd scripts && npm install
 *   gcloud auth application-default login   (credentials resolve at call time;
 *                                            no token is ever stored here)
 */

import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {connect} from "node:net";

import {isEntrypoint} from "./lib/is-entrypoint.mjs";
import {
  DEFAULT_EMULATOR_HOST,
  OUTCOME,
  classifyRead,
  firestoreConsoleUrl,
  objectMatchesPrefix,
  parseFirestorePath,
  renderReport,
  requirePathKind,
  resolveTarget,
} from "./lib/firestore-read-outcome.mjs";

// The fallback control probe. `users` is the collection every environment has
// data in first, so a zero here means the method is blind, not that the target
// is empty.
const DEFAULT_CONTROL_COLLECTION = "users";
// The bucket root: the one Storage prefix that holds something whenever anything
// does. A bucket reported as empty by a method that also sees nothing at the root
// has not been shown to see anything at all.
const DEFAULT_CONTROL_STORAGE_PREFIX = "/";
const DEFAULT_LIST_LIMIT = 20;
const COMMANDS = ["collections", "get", "list", "count", "subcollections", "storage"];
// Function declarations hoist, so the map can name them before they appear.
const RUNNERS = {
  collections: readRootCollections,
  get: readDocument,
  list: readCollectionSample,
  count: readCollectionCount,
  subcollections: readSubcollections,
  storage: readStoragePrefix,
};

if (isEntrypoint(import.meta.url)) {
  await main(process.argv);
}

/**
 * Runs one investigation and exits with its outcome code.
 * @param {string[]} argv Process argv.
 * @return {Promise<void>} Resolves after the process exit code is assigned.
 */
async function main(argv) {
  let args;
  try {
    args = parseArgs(argv);
  } catch (error) {
    process.stderr.write(`${error.message}\n\nRun with --help for usage.\n`);
    process.exitCode = 2;
    return;
  }

  if (args.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }

  let target;
  try {
    target = resolveTarget({
      env: args.env,
      emulator: args.emulator,
      emulatorHost: process.env.FIRESTORE_EMULATOR_HOST ?? null,
      emulatorRunning: await isEmulatorListening(),
      confirmProduction: args.confirmProduction,
    });
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 2;
    return;
  }

  const clients = initializeClients(target);
  const rendered = await runCommand(args, target, clients);

  if (rendered.stdout !== "") process.stdout.write(`${rendered.stdout}\n`);
  if (rendered.stderr !== "") process.stderr.write(`${rendered.stderr}\n`);
  process.exitCode = rendered.exitCode;
}

/**
 * Dispatches a parsed command and renders its outcome.
 * @param {object} args Parsed arguments.
 * @param {object} target Resolved target.
 * @param {object} clients Firestore and Storage handles.
 * @return {Promise<object>} Rendered report.
 */
async function runCommand(args, target, clients) {
  const runner = RUNNERS[args.command];

  const probe = await runner(args, target, clients);
  const control = probe.needsControl && probe.read.matchCount === 0 && !probe.read.failure
    ? await runControl(args, target, clients, probe.controlPath)
    : null;

  const classified = classifyRead({...probe.read, control});
  const detail = [...probe.detail];

  if (classified.outcome !== OUTCOME.failed && probe.consolePath !== null) {
    detail.push(`console: ${firestoreConsoleUrl(target.projectId, probe.consolePath)}`);
  }

  return renderReport({
    target,
    command: args.command,
    path: probe.label,
    classified,
    detail,
  });
}

/**
 * Runs the same method against a path expected to hold data.
 * @param {object} args Parsed arguments.
 * @param {object} target Resolved target.
 * @param {object} clients Firestore and Storage handles.
 * @param {?string} controlPath Control path, or null when none can be guessed.
 * @return {Promise<?object>} Control probe result.
 */
async function runControl(args, target, clients, controlPath) {
  if (controlPath === null) return null;

  const controlArgs = {...args, path: controlPath, expect: [], control: null, controlRun: true};
  const runner = RUNNERS[args.command];

  try {
    const probe = await runner(controlArgs, target, clients);
    return {
      path: controlPath,
      matchCount: probe.read.matchCount,
      failure: probe.read.failure ? String(probe.read.failure.message ?? probe.read.failure) : null,
    };
  } catch (error) {
    return {path: controlPath, matchCount: null, failure: error.message};
  }
}

/**
 * Lists the database's root collection IDs.
 * @param {object} args Parsed arguments.
 * @param {object} target Resolved target.
 * @param {object} clients Firestore and Storage handles.
 * @return {Promise<object>} Probe result.
 */
async function readRootCollections(args, target, clients) {
  try {
    const collections = await clients.firestore.listCollections();
    return {
      label: "/",
      read: {matchCount: collections.length, failure: null},
      detail: collections.length > 0
        ? collections.map((collection) => collection.id)
        : [
            "No control path can prove this one from inside the same database. " +
              "Run `collections --env dev` and confirm it lists collections before " +
              "believing this zero.",
          ],
      needsControl: false,
      controlPath: null,
      consolePath: null,
    };
  } catch (error) {
    return failedProbe("/", error);
  }
}

/**
 * Reads one document, and always reports its subcollections alongside.
 *
 * A missing document is not an empty subtree: Firestore keeps subcollections
 * under a document that was never written, and the Firebase console renders that
 * document in italics with nothing under it until you select it.
 * @param {object} args Parsed arguments.
 * @param {object} target Resolved target.
 * @param {object} clients Firestore and Storage handles.
 * @return {Promise<object>} Probe result.
 */
async function readDocument(args, target, clients) {
  try {
    const segments = requirePathKind(args.path, "document");
    const reference = clients.firestore.doc(segments.join("/"));
    const snapshot = await reference.get();
    const children = await reference.listCollections();
    const detail = [];

    if (snapshot.exists) {
      detail.push(`fields: ${Object.keys(snapshot.data() ?? {}).sort().join(", ") || "(none)"}`);
    } else {
      detail.push("This document has no fields of its own.");
    }

    detail.push(
      children.length > 0
        ? `subcollections seen: ${children.map((child) => child.id).join(", ")}`
        : "subcollections seen: none listed - see `subcollections --expect`, a negative here is weak"
    );

    if (!snapshot.exists && children.length > 0) {
      detail.push(
        "The document does not exist but data lives beneath it. Do not report this path as empty."
      );
    }

    return {
      label: args.path,
      read: {matchCount: snapshot.exists ? 1 : 0, failure: null},
      detail,
      needsControl: children.length === 0,
      controlPath: args.control,
      consolePath: args.path,
    };
  } catch (error) {
    return failedProbe(args.path, error);
  }
}

/**
 * Lists a bounded sample of a collection's documents.
 * @param {object} args Parsed arguments.
 * @param {object} target Resolved target.
 * @param {object} clients Firestore and Storage handles.
 * @return {Promise<object>} Probe result.
 */
async function readCollectionSample(args, target, clients) {
  try {
    const segments = requirePathKind(args.path, "collection");
    const collection = clients.firestore.collection(segments.join("/"));
    const snapshot = await collection.limit(args.limit).get();
    const phantoms = snapshot.size === 0 ? await phantomParentIds(collection) : [];

    return {
      label: args.path,
      read: {matchCount: Math.max(snapshot.size, phantoms.length), failure: null},
      detail: [
        ...snapshot.docs.map((document) => document.id),
        ...phantomDetail(phantoms, args.limit),
        snapshot.size === args.limit ? `(sample capped at --limit ${args.limit}; use count)` : null,
      ].filter((line) => line !== null),
      needsControl: true,
      controlPath: args.control ?? DEFAULT_CONTROL_COLLECTION,
      consolePath: args.path,
    };
  } catch (error) {
    return failedProbe(args.path, error);
  }
}

/**
 * Counts a collection with a server-side aggregation.
 * @param {object} args Parsed arguments.
 * @param {object} target Resolved target.
 * @param {object} clients Firestore and Storage handles.
 * @return {Promise<object>} Probe result.
 */
async function readCollectionCount(args, target, clients) {
  try {
    const segments = requirePathKind(args.path, "collection");
    const collection = clients.firestore.collection(segments.join("/"));
    const aggregate = await collection.count().get();
    const counted = aggregate.data().count;
    const phantoms = counted === 0 ? await phantomParentIds(collection) : [];

    return {
      label: args.path,
      read: {matchCount: Math.max(counted, phantoms.length), failure: null},
      detail: phantomDetail(phantoms, args.limit),
      needsControl: true,
      controlPath: args.control ?? DEFAULT_CONTROL_COLLECTION,
      consolePath: args.path,
    };
  } catch (error) {
    return failedProbe(args.path, error);
  }
}

/**
 * Lists a document's subcollections, and directly probes the expected names.
 *
 * `listCollections` (REST `:listCollectionIds`) has answered "none" for a
 * document with three populated subcollections. Treat a negative from it as no
 * information, and settle the question with `--expect`, which counts each named
 * path directly.
 * @param {object} args Parsed arguments.
 * @param {object} target Resolved target.
 * @param {object} clients Firestore and Storage handles.
 * @return {Promise<object>} Probe result.
 */
async function readSubcollections(args, target, clients) {
  try {
    const segments = requirePathKind(args.path, "document");
    const reference = clients.firestore.doc(segments.join("/"));
    const listed = await reference.listCollections();
    const detail = [
      listed.length > 0
        ? `listed: ${listed.map((child) => child.id).join(", ")}`
        : "listed: none - which is not evidence of absence",
    ];

    let directHits = 0;
    for (const name of args.expect) {
      const child = reference.collection(name);
      const counted = (await child.count().get()).data().count;
      const phantoms = counted === 0 ? await phantomParentIds(child) : [];
      const found = Math.max(counted, phantoms.length);
      directHits += found;
      detail.push(
        `direct probe ${args.path}/${name}: ${found}` +
          (phantoms.length > 0 ? ` (all ${phantoms.length} are subcollection parents)` : "")
      );
    }

    if (args.expect.length === 0 && listed.length === 0) {
      detail.push("Pass --expect <names> to probe the subcollections you believe exist.");
    }

    return {
      label: args.path,
      read: {matchCount: Math.max(listed.length, directHits > 0 ? 1 : 0), failure: null},
      detail,
      needsControl: true,
      controlPath: args.control,
      consolePath: args.path,
    };
  } catch (error) {
    return failedProbe(args.path, error);
  }
}

/**
 * Counts Storage objects under a prefix.
 *
 * The prefix anchors server-side, so `profile_pictures/` cannot pick up
 * `users/<uid>/profile_pictures/` the way a substring grep does. Every returned
 * name is re-checked against the prefix before it is counted.
 * @param {object} args Parsed arguments.
 * @param {object} target Resolved target.
 * @param {object} clients Firestore and Storage handles.
 * @return {Promise<object>} Probe result.
 */
async function readStoragePrefix(args, target, clients) {
  try {
    if (target.kind === "emulator") {
      throw new Error("Storage reads need a real project; pass --env dev|staging|prod.");
    }
    const prefix = args.path === "/" ? "" : args.path;
    // A control probe only has to answer "can this method see anything at all",
    // so it reads one page instead of walking a whole bucket.
    const [files] = args.controlRun === true
      ? await clients.storage.getFiles({prefix, maxResults: 1, autoPaginate: false})
      : await clients.storage.getFiles({prefix});
    const anchored = files.filter((file) => objectMatchesPrefix(file.name, prefix));
    const stray = files.length - anchored.length;

    return {
      label: prefix === "" ? "(bucket root)" : prefix,
      read: {matchCount: anchored.length, failure: null},
      detail: [
        `bucket: ${clients.storage.name}`,
        ...anchored.slice(0, args.limit).map((file) => file.name),
        anchored.length > args.limit ? `(${anchored.length - args.limit} more)` : null,
        stray > 0 ? `WARNING: ${stray} returned objects did not anchor to the prefix` : null,
      ].filter((line) => line !== null),
      needsControl: true,
      controlPath: args.control ?? DEFAULT_CONTROL_STORAGE_PREFIX,
      consolePath: null,
    };
  } catch (error) {
    return failedProbe(args.path, error);
  }
}

/**
 * Document IDs that exist only as parents of subcollections.
 *
 * `live_replay_leaderboards/<key>/splitBuckets` counts zero while
 * `splitBuckets/0/entries` holds fifty-nine rows: the bucket document itself was
 * never written, so a count query and the Firebase console both show nothing.
 * `listDocuments` is the only read that sees these, and without it the busiest
 * collection in the app reports as empty.
 * @param {object} collection Collection reference.
 * @return {Promise<string[]>} Phantom parent document IDs.
 */
async function phantomParentIds(collection) {
  const references = await collection.listDocuments();
  return references.map((reference) => reference.id);
}

/**
 * Renders phantom parents so they cannot be mistaken for an empty collection.
 * @param {string[]} phantoms Phantom parent document IDs.
 * @param {number} limit How many IDs to show.
 * @return {string[]} Detail lines.
 */
function phantomDetail(phantoms, limit) {
  if (phantoms.length === 0) return [];
  return [
    `0 documents have fields, but ${phantoms.length} document ID(s) exist as ` +
      "parents of subcollections. Data lives below them; this path is not empty.",
    `phantom parents: ${phantoms.slice(0, limit).join(", ")}`,
  ];
}

/**
 * Wraps a thrown error as a failed probe, never as an empty one.
 * @param {string} label Path label.
 * @param {Error} error The thrown error.
 * @return {object} Probe result.
 */
function failedProbe(label, error) {
  return {
    label,
    read: {matchCount: null, failure: error},
    detail: [],
    needsControl: false,
    controlPath: null,
    consolePath: null,
  };
}

/**
 * Initializes read-only Firestore and Storage handles for the target.
 * @param {object} target Resolved target.
 * @return {{firestore: object, storage: object}} Client handles.
 */
function initializeClients(target) {
  if (target.kind === "emulator") {
    process.env.FIRESTORE_EMULATOR_HOST = target.emulatorHost;
    initializeApp({projectId: target.projectId});
    return {firestore: getFirestore(), storage: null};
  }

  initializeApp({
    credential: applicationDefault(),
    projectId: target.projectId,
    storageBucket: `${target.projectId}.firebasestorage.app`,
  });
  return {firestore: getFirestore(), storage: getStorage().bucket()};
}

/**
 * Whether something is listening on the default Firestore emulator port.
 * @return {Promise<boolean>} True when the emulator answers.
 */
function isEmulatorListening() {
  if (process.env.FIRESTORE_EMULATOR_HOST) return Promise.resolve(true);

  const [host, port] = DEFAULT_EMULATOR_HOST.split(":");
  return new Promise((resolve) => {
    const socket = connect({host, port: Number(port)});
    const settle = (answer) => {
      socket.destroy();
      resolve(answer);
    };
    socket.setTimeout(300);
    socket.once("connect", () => settle(true));
    socket.once("timeout", () => settle(false));
    socket.once("error", () => settle(false));
  });
}

/**
 * Parses command-line arguments.
 * @param {string[]} argv Process argv.
 * @return {object} Parsed arguments.
 */
export function parseArgs(argv) {
  const parsed = {
    command: null,
    path: null,
    env: null,
    emulator: false,
    confirmProduction: false,
    control: null,
    expect: [],
    limit: DEFAULT_LIST_LIMIT,
    help: false,
    controlRun: false,
  };

  for (let index = 2; index < argv.length; index += 1) {
    const value = argv[index];
    switch (value) {
      case "--env":
        parsed.env = requireValue(argv, ++index, "--env");
        break;
      case "--control":
        parsed.control = requireValue(argv, ++index, "--control");
        break;
      case "--expect":
        parsed.expect = requireValue(argv, ++index, "--expect")
          .split(",")
          .map((name) => name.trim())
          .filter((name) => name !== "");
        break;
      case "--limit":
        parsed.limit = requirePositiveInteger(requireValue(argv, ++index, "--limit"));
        break;
      case "--emulator":
        parsed.emulator = true;
        break;
      case "--confirm-production":
        parsed.confirmProduction = true;
        break;
      case "--help":
      case "-h":
        parsed.help = true;
        break;
      default:
        if (value.startsWith("-")) throw new Error(`Unknown argument: ${value}`);
        if (parsed.command === null) parsed.command = value;
        else if (parsed.path === null) parsed.path = value;
        else throw new Error(`Unexpected argument: ${value}`);
    }
  }

  if (parsed.help) return parsed;

  if (parsed.command === null || !COMMANDS.includes(parsed.command)) {
    throw new Error(`Command must be one of: ${COMMANDS.join(", ")}.`);
  }
  if (parsed.command === "collections") {
    parsed.path = "/";
  } else if (parsed.path === null) {
    throw new Error(`\`${parsed.command}\` needs a path.`);
  } else if (parsed.command !== "storage") {
    parseFirestorePath(parsed.path);
  }

  return parsed;
}

/**
 * Reads a flag's value or names the flag that is missing one.
 * @param {string[]} argv Process argv.
 * @param {number} index Value index.
 * @param {string} flag Flag name.
 * @return {string} Flag value.
 */
function requireValue(argv, index, flag) {
  const value = argv[index];
  if (value === undefined || value.startsWith("--")) {
    throw new Error(`${flag} needs a value.`);
  }
  return value;
}

/**
 * Parses a positive integer flag value.
 * @param {string} value Raw flag value.
 * @return {number} Parsed integer.
 */
function requirePositiveInteger(value) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`Expected a positive integer, got "${value}".`);
  }
  return parsed;
}

/**
 * The command-line usage text.
 * @return {string} Usage text.
 */
export function usage() {
  return [
    "Read-only Firestore and Storage investigation.",
    "",
    "  node scripts/firestore-query.mjs <command> [path] [flags]",
    "",
    "Commands:",
    "  collections                 Root collection IDs",
    "  get <doc path>              One document, plus the subcollections beneath it",
    "  list <collection path>      A bounded sample of document IDs",
    "  count <collection path>     Server-side count",
    "  subcollections <doc path>   Listed subcollections, plus --expect direct probes",
    "  storage <prefix>            Objects under an anchored Storage prefix",
    "",
    "Flags:",
    "  --env dev|staging|prod      Real backend. Omit it to read a running emulator.",
    "  --emulator                  Force the emulator.",
    "  --confirm-production        Required for --env prod.",
    "  --control <path>            Known-populated path to prove the method can see data.",
    "  --expect a,b,c              Subcollection names to probe directly.",
    "  --limit <n>                 Sample size (default 20).",
    "",
    "Exit codes: 0 found or verified empty, 2 failed, 3 empty but unverified.",
  ].join("\n");
}

export {main, runCommand};
