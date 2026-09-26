import {execFileSync} from "node:child_process";
import {realpathSync} from "node:fs";
import {createRequire} from "node:module";
import {dirname, join} from "node:path";

// The deploy gates that talk to Google APIs load private firebase-tools
// modules, so they are only correct for the exact pinned version. Keep in sync
// with docs/dependency-security.md and every `firebase-tools@` pin it lists.
export const PINNED_FIREBASE_TOOLS_VERSION = "15.22.1";
export const PINNED_FIREBASE_TOOLS = `firebase-tools@${PINNED_FIREBASE_TOOLS_VERSION}`;

/**
 * Refuses any tree that is not the pinned firebase-tools release.
 * @param {NodeRequire} require A require function able to load the tree.
 * @param {string} firebaseToolsRoot The package root to check.
 * @return {void}
 */
export function assertPinnedFirebaseTools(require, firebaseToolsRoot) {
  let manifest;
  try {
    manifest = require(join(firebaseToolsRoot, "package.json"));
  } catch {
    throw new Error(
      `FIREBASE_TOOLS_ROOT does not hold a package: ${firebaseToolsRoot}`
    );
  }

  if (manifest.name !== "firebase-tools") {
    throw new Error(
      `FIREBASE_TOOLS_ROOT resolved ${manifest.name}, not firebase-tools: ` +
        firebaseToolsRoot
    );
  }
  if (manifest.version !== PINNED_FIREBASE_TOOLS_VERSION) {
    throw new Error(
      `This reader uses private firebase-tools ` +
        `${PINNED_FIREBASE_TOOLS_VERSION} internals, but ` +
        `${firebaseToolsRoot} resolved ${manifest.version}`
    );
  }
}

/**
 * Loads the pinned CLI's private auth module and resolves the refresh token
 * every request will be minted from.
 *
 * FIREBASE_TOKEN wins, because that is the credential every deploy step uses;
 * a developer's logged-in CLI session is the local fallback.
 * @param {object} input Loader input.
 * @param {string} input.firebaseToolsRoot The pinned package root.
 * @param {?string} [input.refreshToken] An explicit refresh token.
 * @return {{auth: object, refreshToken: string}} The auth module and token.
 */
export function loadPinnedFirebaseToolsAuth({firebaseToolsRoot, refreshToken}) {
  const require = createRequire(import.meta.url);
  assertPinnedFirebaseTools(require, firebaseToolsRoot);
  const auth = require(join(firebaseToolsRoot, "lib/auth.js"));

  const resolvedRefreshToken = refreshToken ??
    auth.getGlobalDefaultAccount?.()?.tokens?.refresh_token;
  if (
    typeof resolvedRefreshToken !== "string" ||
    resolvedRefreshToken.length === 0
  ) {
    throw new Error(
      "FIREBASE_TOKEN or an authenticated Firebase CLI session is required"
    );
  }

  return {auth, refreshToken: resolvedRefreshToken};
}

/**
 * Mints Google OAuth access tokens from the deploy's own Firebase credential.
 *
 * Reading Secret Manager, the Cloud Functions API and Firestore from CI needs a
 * Google credential, and the one the deploy already holds is FIREBASE_TOKEN: a
 * refresh token for the Firebase CLI's OAuth client, granted the
 * `cloud-platform` scope. Reusing it adds no privilege the deploy does not
 * already have, where a service account for these reads would be a new
 * standing credential with production secret access.
 *
 * The pinned CLI caches the token until shortly before it expires, so calling
 * the returned function per request costs nothing.
 * @param {object} input Source input.
 * @param {string} input.firebaseToolsRoot The pinned package root.
 * @param {?string} [input.refreshToken] An explicit refresh token.
 * @return {function(): Promise<string>} Resolves a bearer token.
 */
export function createGoogleAccessTokenSource({firebaseToolsRoot, refreshToken}) {
  const {auth, refreshToken: resolvedRefreshToken} = loadPinnedFirebaseToolsAuth({
    firebaseToolsRoot,
    refreshToken,
  });
  if (typeof auth.getAccessToken !== "function") {
    throw new Error("Pinned firebase-tools auth API is unavailable");
  }

  return async function getAccessToken() {
    const tokens = await auth.getAccessToken(resolvedRefreshToken, []);
    const accessToken = tokens?.access_token;
    // On an OAuth 400 or 401 the pinned CLI hands the refresh token back as
    // though it were an access token, and every request then fails as a
    // confusing 401. Naming the credential here is the useful version of that.
    if (
      typeof accessToken !== "string" ||
      accessToken.length === 0 ||
      accessToken === resolvedRefreshToken
    ) {
      throw new Error(
        "Google refused the Firebase refresh token (FIREBASE_TOKEN or the " +
          "local CLI session), so no request could be authenticated."
      );
    }
    return accessToken;
  };
}

/**
 * Resolves the package root of the pinned CLI, installing it through npm's
 * exec cache when it is not there yet.
 *
 * FIREBASE_TOOLS_ROOT wins when set. Otherwise this is the same resolution the
 * index gate's workflow step performs in shell, done here so a local run needs
 * no setup beyond a logged-in CLI.
 * @param {object} [input] Resolver input.
 * @param {NodeJS.ProcessEnv} [input.env] Environment to read.
 * @param {Function} [input.execFile] execFileSync-compatible runner.
 * @return {string} The realpath of the pinned package root.
 */
export function resolvePinnedFirebaseToolsRoot({
  env = process.env,
  execFile = execFileSync,
} = {}) {
  if (env.FIREBASE_TOOLS_ROOT) {
    return env.FIREBASE_TOOLS_ROOT;
  }

  const binary = String(
    execFile(
      "npm",
      [
        "exec",
        "--yes",
        `--package=${PINNED_FIREBASE_TOOLS}`,
        "--",
        "which",
        "firebase",
      ],
      {encoding: "utf8", stdio: ["ignore", "pipe", "inherit"]}
    )
  ).trim();
  if (binary.length === 0) {
    throw new Error(`npm exec could not locate ${PINNED_FIREBASE_TOOLS}`);
  }

  return realpathSync(join(dirname(binary), "..", "firebase-tools"));
}
