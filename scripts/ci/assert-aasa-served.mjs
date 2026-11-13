#!/usr/bin/env node
// After a Hosting deploy: the apple-app-site-association file has to come back the way Apple's
// fetch needs it - 200, no redirect, application/json - and has to be the one this repository
// deploys, not the generated one Firebase Hosting serves when `appAssociation` is left on AUTO
// (that one claims every path on the site). `docs/universal-links.md`.
//
//   node scripts/ci/assert-aasa-served.mjs https://<project>.web.app

const AASA_PATH = "/.well-known/apple-app-site-association";
const EXPECTED_COMPONENT_PATHS = ["/go", "/go/*"];

export async function assertAasaServed(baseURL, fetchImpl = fetch) {
  const url = new URL(AASA_PATH, baseURL);
  const response = await fetchImpl(url, { redirect: "manual" });
  const problems = [];

  if (response.status !== 200) {
    problems.push(`${url} answered ${response.status}; Apple does not follow redirects for this file and needs a 200`);
  }

  const contentType = response.headers.get("content-type") ?? "(none)";
  if (!/^application\/json\b/i.test(contentType)) {
    problems.push(`${url} is served as "${contentType}"; it must be application/json`);
  }

  let body = null;
  try {
    body = JSON.parse(await response.text());
  } catch {
    problems.push(`${url} is not valid JSON`);
  }

  if (body !== null) {
    const details = body?.applinks?.details ?? [];
    const paths = details.flatMap((detail) => (detail.components ?? []).map((component) => component["/"]));

    if (JSON.stringify(paths) !== JSON.stringify(EXPECTED_COMPONENT_PATHS)) {
      problems.push(
        `${url} claims ${JSON.stringify(details)}; expected components ${JSON.stringify(EXPECTED_COMPONENT_PATHS)} ` +
          "(Firebase's generated file claims /* - check appAssociation is NONE in firebase.json)"
      );
    }
  }

  return problems;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const baseURL = process.argv[2];
  if (!baseURL) {
    console.error("Pass the site's base URL, for example https://ascend-prod-9c8f2.web.app");
    process.exit(2);
  }

  let problems;
  try {
    problems = await assertAasaServed(baseURL);
  } catch (error) {
    problems = [`could not fetch ${baseURL}: ${error.message}`];
  }

  if (problems.length > 0) {
    for (const problem of problems) console.error(problem);
    process.exit(1);
  }
  console.log(`Verified ${baseURL}${AASA_PATH} serves the Ascend universal-link file`);
}
