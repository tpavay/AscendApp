export const PUBLIC_DISPLAY_NAME = "Climber";
export const PUBLIC_PHOTO_URL = "";
export const DEFAULT_SANITIZATION_BATCH_SIZE = 400;

const MODES = new Set(["dry-run", "apply", "audit"]);

export function parseSanitizationArgs(argv) {
  const parsed = {
    env: null,
    mode: null,
    rerun: false,
    productionConfirmation: null,
    batchSize: DEFAULT_SANITIZATION_BATCH_SIZE,
    help: false,
  };

  for (let index = 2; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--env") {
      parsed.env = requiredValue(argv, ++index, value);
    } else if (value === "--confirm-production") {
      parsed.productionConfirmation = requiredValue(argv, ++index, value);
    } else if (value === "--batch-size") {
      parsed.batchSize = Number(requiredValue(argv, ++index, value));
    } else if (value === "--rerun") {
      parsed.rerun = true;
    } else if (value === "--help" || value === "-h") {
      parsed.help = true;
    } else if (value.startsWith("--") && MODES.has(value.slice(2))) {
      if (parsed.mode) {
        throw new Error("Pass exactly one of --dry-run, --apply, or --audit.");
      }
      parsed.mode = value.slice(2);
    } else {
      throw new Error(`Unknown argument: ${value}`);
    }
  }

  if (parsed.help) return parsed;
  if (!parsed.env) throw new Error("Missing --env.");
  if (!parsed.mode) {
    throw new Error("Pass exactly one of --dry-run, --apply, or --audit.");
  }
  if (!Number.isInteger(parsed.batchSize) || parsed.batchSize < 1 || parsed.batchSize > 450) {
    throw new Error("--batch-size must be an integer from 1 through 450.");
  }
  if (parsed.rerun && parsed.mode !== "apply") {
    throw new Error("--rerun is valid only with --apply.");
  }
  return parsed;
}

export function isTrustedSyntheticRecord(data) {
  return data?.isSynthetic === true || data?.source === "synthetic";
}

export function isTrustedSyntheticFirstAscent(data) {
  if (data?.firstAscentIsSynthetic === true) return true;

  return data?.source === "seeded" &&
    typeof data?.seedPackId === "string" &&
    data.seedPackId.length > 0 &&
    typeof data?.firstAscentUserId === "string" &&
    data.firstAscentUserId.startsWith("seeded:");
}

export function needsIdentitySanitization(data) {
  return data?.displayName !== PUBLIC_DISPLAY_NAME ||
    data?.photoURL !== PUBLIC_PHOTO_URL ||
    (data?.avatarToken ?? "") !== "" ||
    data?.isSynthetic !== false;
}

export function needsFirstAscentSanitization(data) {
  if (!data || data.firstAscentCompletedAt === undefined) return false;
  if (isTrustedSyntheticFirstAscent(data)) {
    return data.firstAscentIsSynthetic !== true;
  }
  return data.firstAscentDisplayName !== PUBLIC_DISPLAY_NAME ||
    data.firstAscentPhotoURL !== PUBLIC_PHOTO_URL ||
    (data.firstAscentAvatarToken ?? "") !== "" ||
    data.firstAscentIsSynthetic !== false;
}

export function publicIdentityWrite() {
  return {
    avatarToken: "",
    displayName: PUBLIC_DISPLAY_NAME,
    isSynthetic: false,
    photoURL: PUBLIC_PHOTO_URL,
  };
}

export function publicProfileIdentityWrite() {
  return {
    displayName: PUBLIC_DISPLAY_NAME,
    photoURL: PUBLIC_PHOTO_URL,
  };
}

export function firstAscentIdentityWrite(data) {
  if (isTrustedSyntheticFirstAscent(data)) {
    return {firstAscentIsSynthetic: true};
  }
  return {
    firstAscentAvatarToken: "",
    firstAscentDisplayName: PUBLIC_DISPLAY_NAME,
    firstAscentIsSynthetic: false,
    firstAscentPhotoURL: PUBLIC_PHOTO_URL,
  };
}

export function collectPublishedPhotoURLs(records) {
  const urls = new Set();
  for (const record of records) {
    for (const field of ["photoURL", "firstAscentPhotoURL"]) {
      const value = record?.[field];
      if (typeof value === "string" && value.trim().length > 0) {
        urls.add(value.trim());
      }
    }
  }
  return urls;
}

export function storageObjectFromDownloadURL(value) {
  if (typeof value !== "string" || value.length > 4096) return null;

  let url;
  try {
    url = new URL(value);
  } catch {
    return null;
  }
  if (url.protocol !== "https:" || url.hostname !== "firebasestorage.googleapis.com") {
    return null;
  }

  const match = url.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
  const token = url.searchParams.get("token");
  if (!match || !token) return null;

  try {
    return {
      bucket: decodeURIComponent(match[1]),
      path: decodeURIComponent(match[2]),
      token,
      url: value,
    };
  } catch {
    return null;
  }
}

export function replacementDownloadURL(bucket, path, token) {
  return `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(bucket)}` +
    `/o/${encodeURIComponent(path)}?alt=media&token=${encodeURIComponent(token)}`;
}

export function packBatches(items, batchSize) {
  const batches = [];
  for (let offset = 0; offset < items.length; offset += batchSize) {
    batches.push(items.slice(offset, offset + batchSize));
  }
  return batches;
}

export function planSanitizationPage(records, kind) {
  return records.flatMap((record) => {
    if (kind === "firstAscent") {
      return needsFirstAscentSanitization(record.data)
        ? [{...record, update: firstAscentIdentityWrite(record.data)}]
        : [];
    }
    if (kind === "publicProfile" || kind === "leaderboard") {
      return record.data?.displayName !== PUBLIC_DISPLAY_NAME ||
        record.data?.photoURL !== PUBLIC_PHOTO_URL
        ? [{...record, update: publicProfileIdentityWrite()}]
        : [];
    }
    if (isTrustedSyntheticRecord(record.data)) return [];
    return needsIdentitySanitization(record.data)
      ? [{...record, update: publicIdentityWrite()}]
      : [];
  });
}

function requiredValue(argv, index, flag) {
  const value = argv[index];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value.`);
  }
  return value;
}
