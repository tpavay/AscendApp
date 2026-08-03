import {createSign} from "node:crypto";

const API_ROOT = "https://api.appstoreconnect.apple.com/v1";
const API_ORIGIN = new URL(API_ROOT).origin;
const TOKEN_LIFETIME_SECONDS = 900;

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
    throw new Error(
      `App Store Connect ${method} ${url.pathname} failed (${response.status}): ${detail ?? text}`,
    );
  }

  return parsed;
}
