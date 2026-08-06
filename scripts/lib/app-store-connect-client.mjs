import {createSign} from "node:crypto";

const API_ROOT = "https://api.appstoreconnect.apple.com/v1";
const API_ORIGIN = new URL(API_ROOT).origin;
const TOKEN_LIFETIME_SECONDS = 900;

export const APP_ID_PATTERN = /^\d+$/;
export const BUNDLE_ID_PATTERN = /^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/;
export const BUILD_NUMBER_PATTERN = /^\d+$/;

function base64url(input) {
  return Buffer.from(input).toString("base64url");
}

export function readAppStoreConnectCredentials(environment = process.env) {
  const keyId = environment.APP_STORE_CONNECT_API_KEY_ID;
  const issuerId = environment.APP_STORE_CONNECT_API_ISSUER_ID;
  const encodedKey = environment.APP_STORE_CONNECT_API_KEY;

  const missing = [
    ["APP_STORE_CONNECT_API_KEY_ID", keyId],
    ["APP_STORE_CONNECT_API_ISSUER_ID", issuerId],
    ["APP_STORE_CONNECT_API_KEY", encodedKey],
  ]
    .filter(([, value]) => !value)
    .map(([name]) => name);

  if (missing.length > 0) {
    throw new Error(`Missing environment variable(s): ${missing.join(", ")}`);
  }

  return {
    keyId,
    issuerId,
    privateKey: Buffer.from(encodedKey, "base64").toString("utf8"),
  };
}

/**
 * App Store Connect requires the raw r||s ECDSA signature encoding used by JWT,
 * rather than the ASN.1 DER encoding Node uses by default.
 */
export function makeAppStoreConnectToken(
  {keyId, issuerId, privateKey},
  nowSeconds = Math.floor(Date.now() / 1000),
) {
  const header = base64url(JSON.stringify({alg: "ES256", kid: keyId, typ: "JWT"}));
  const payload = base64url(
    JSON.stringify({
      iss: issuerId,
      iat: nowSeconds,
      exp: nowSeconds + TOKEN_LIFETIME_SECONDS,
      aud: "appstoreconnect-v1",
    }),
  );

  const signer = createSign("SHA256");
  signer.update(`${header}.${payload}`);
  const signature = signer.sign({key: privateKey, dsaEncoding: "ieee-p1363"});

  return `${header}.${payload}.${signature.toString("base64url")}`;
}

export async function appStoreConnectRequest(
  token,
  pathOrURL,
  {method = "GET", body, fetchImplementation = fetch} = {},
) {
  const url = pathOrURL.startsWith("http")
    ? new URL(pathOrURL)
    : new URL(`${API_ROOT}/${pathOrURL.replace(/^\//, "")}`);
  if (url.origin !== API_ORIGIN) {
    throw new Error(`Refusing to send App Store Connect credentials to ${url.origin}.`);
  }

  const response = await fetchImplementation(url, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(body ? {"Content-Type": "application/json"} : {}),
    },
    ...(body ? {body: JSON.stringify(body)} : {}),
  });

  if (response.status === 204) return null;

  const text = await response.text();
  const parsed = text ? JSON.parse(text) : null;

  if (!response.ok) {
    const detail = parsed?.errors
      ?.map((error) => `${error.title}: ${error.detail}`)
      .join("; ");
    const error = new Error(
      `App Store Connect ${method} ${url.pathname} failed (${response.status}): ${detail ?? text}`,
    );
    error.status = response.status;
    throw error;
  }

  return parsed;
}

/**
 * A rate limit or a server-side outage says nothing about the request; every
 * other status says Apple understood it and refused it, and no amount of
 * retrying changes that answer.
 */
export function isTransientAppStoreConnectFailure(error) {
  return error?.status === undefined || error.status === 429 || error.status >= 500;
}

/**
 * An expired, revoked, or wrongly scoped API key is the most common deterministic
 * refusal there is, and it says nothing about the query it happened to refuse.
 */
export function isAppStoreConnectCredentialRejection(error) {
  return error?.status === 401 || error?.status === 403;
}

/**
 * Deterministic refusals are how an unsupported filter, a rejected query
 * parameter, or a withdrawn relationship surfaces, and the raw status alone
 * does not say which assumption stopped holding. A rejected credential is
 * deterministic too, but blaming the query for it sends the operator hunting
 * an Apple API change that never happened.
 */
export async function requestUnderContract(token, pathOrURL, request, assumption) {
  try {
    return await request(token, pathOrURL);
  } catch (error) {
    if (isTransientAppStoreConnectFailure(error)) throw error;

    const failure = isAppStoreConnectCredentialRejection(error)
      ? new Error(
          `APP_STORE_CREDENTIALS_REJECTED: ${error.message}. App Store Connect refused the API ` +
            "key itself, so no query assumption is implicated. Check that " +
            "APP_STORE_CONNECT_API_KEY_ID, APP_STORE_CONNECT_API_ISSUER_ID and " +
            "APP_STORE_CONNECT_API_KEY still name a current key with access to this app.",
        )
      : new Error(
          `APP_STORE_CONTRACT_REJECTED: ${error.message}. ` +
            `The App Store Connect assumption that stopped holding: ${assumption}.`,
        );
    failure.status = error.status;
    throw failure;
  }
}

/**
 * An app ID is an opaque number, so a wrong one reads as a working configuration
 * right up to the point it allocates or inspects the wrong app's builds.
 */
export async function assertAppOwnsBundleId(
  {token, appId, expectedBundleId},
  request = appStoreConnectRequest,
) {
  if (!APP_ID_PATTERN.test(String(appId))) {
    throw new Error(`App Store Connect app ID must be numeric, got '${appId}'.`);
  }
  if (!BUNDLE_ID_PATTERN.test(String(expectedBundleId))) {
    throw new Error(`Expected bundle ID is invalid, got '${expectedBundleId}'.`);
  }

  const app = await requestUnderContract(
    token,
    `/apps/${appId}?fields%5Bapps%5D=bundleId,name`,
    request,
    "GET /v1/apps/{id} accepts fields[apps]=bundleId,name",
  );
  const actualBundleId = app?.data?.attributes?.bundleId;
  if (actualBundleId !== expectedBundleId) {
    throw new Error(
      `App Store Connect app ${appId} belongs to '${actualBundleId ?? "(missing)"}', ` +
        `not expected bundle '${expectedBundleId}'.`,
    );
  }
}
