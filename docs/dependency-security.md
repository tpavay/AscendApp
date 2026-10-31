# Dependency Security

Run `npm audit --package-lock-only` from the repository root and from each npm project before upgrading dependencies.
Treat `functions/` as production code because it runs with Firebase Admin credentials, while `web/` is the deployed static site.
The root package intentionally does not install `firebase-tools`; its rules-test command invokes the CLI directly, so a second pinned CLI tree would be unused and vulnerable between releases.
It pins `firebase-tools@15.22.1`, and that same pin applies everywhere the CLI runs: CI (`ci.yml`'s `firebase-verify` job), `functions/package.json`'s `test:emulator` script, both deploy workflows, and the human-run Firebase commands documented in `CLAUDE.md`, `docs/production-backend-rollout-runbook.md`, `functions/EMAIL_SETUP.md`, and the `live-climb-content` skill.
The production index waiter resolves the temporary package root created by `npm exec` and uses that exact pinned CLI's authenticated Firestore client, so it does not justify adding `firebase-tools` to the root dependency tree.
It loads that CLI's private `lib/auth.js` and `lib/firestore/api.js`, and the Functions secret guard (`scripts/verify-functions-secrets.mjs`) mints its Google access token through the same private `lib/auth.js`, so `PINNED_FIREBASE_TOOLS_VERSION` in `scripts/lib/pinned-firebase-tools.mjs` is one of the pins to bump together, and both refuse to run against any other resolved version rather than loading unverified internals.
Rules have to be validated and shipped by the same CLI, so validation never passes on a version that differs from the one that deploys, and an unpinned `@latest` would let an upstream release turn unrelated required checks red.
Bump every one of those pins together.

## CI audit gate allowlist

Every npm project's audit step in `ci.yml` (`functions-verify`, `scripts-verify`, `web-verify`, `root-npm-verify`) runs through a pinned `audit-ci@7.1.0` rather than a bare `npm audit`.
`audit-ci` is IBM's maintained CI wrapper around `npm audit`; it adds a reviewable, file-based allowlist with per-entry expiry, so this repository did not need to build that mechanism from scratch.
Bump this pin the same way as the `firebase-tools` pin above: everywhere it appears in `ci.yml`'s four audit steps, all at once.

Each project keeps its own config at its root: `audit-ci.json`, `functions/audit-ci.json`, `scripts/audit-ci.json`, `web/audit-ci.json`.
Every config sets `"low": true`, which fails the gate on low-or-higher severity exactly like the `--audit-level=low` it replaced.
`scripts/test/audit-ci-allowlist-contract.test.mjs` enforces the shape of every entry in every config, so a malformed or overly broad suppression fails CI on the PR that adds it rather than silently doing nothing.

An advisory disclosed after a project's lockfile last landed fails every PR that touches that project's path filter, even one unrelated to the vulnerable dependency, until the lockfile is patched or the advisory is allowlisted.
To allowlist one that has no fix available yet, add an entry to the affected project's `audit-ci.json`'s `allowlist` array, keyed by its GitHub Security Advisory ID:

```json
{
  "low": true,
  "allowlist": [
    {
      "GHSA-xxxx-xxxx-xxxx": {
        "active": true,
        "notes": "Why this can't be fixed yet, and a link to the tracking issue.",
        "expiry": "2026-12-06"
      }
    }
  ]
}
```

`audit-ci` stops applying an entry once its `expiry` passes, so the advisory starts failing the gate again rather than staying silently suppressed forever.
That is the mechanism that forces a genuine re-review; it is not a follow-up task someone has to remember.
The contract test additionally refuses an `expiry` more than 180 days out, so an entry cannot be added with an effectively permanent suppression date.

Only allowlist by GitHub Security Advisory ID (the `GHSA-xxxx-xxxx-xxxx` form above).
Never allowlist by bare module name (`"axios"`) or by dependency path (`"a>b>c"`): both suppress every current *and future* advisory for that dependency, not just the one advisory under review, and the contract test rejects both forms.

## Functions

Keep `firebase-admin` on the latest 13.x release until a dedicated 14.x migration is verified against the full Functions test suite.
The 13.x tree still requests `uuid` 9 through Google Cloud clients, so `functions/package.json` overrides `uuid` to `^11.1.1`.
Those clients exercise the unchanged `v4` API, and dropping the override reintroduces the buffer-bounds advisory.

Express 4 declares `qs` as `~6.15.1`, a range that cannot admit the patched 6.16.0 and for which no 6.15.x patch release exists, so `functions/package.json` overrides `qs` to `~6.16.1`.
Dropping the override reintroduces the bracket-key array-limit bypass (GHSA-x5fp-wj9c-mxmx) and the attacker-controlled `isBuffer` denial of service (GHSA-4mjr-xmp4-gh2g), which fail the audit gate on every backend pull request.
The floor is 6.16.1 because 6.16.0 still throws on a `comma`-format `qs.stringify` of an array element with a non-callable own `toString` (GHSA-6pq8-jhm2-2vcw, published 2026-10-27), and the tilde keeps the override on the 6.16 patch line so an unreviewed `qs` minor cannot change how a handler parses its query string.
Do not clear those advisories by bumping `firebase-functions` instead: 7.3.2 moves to Express 5, whose default `query parser` is `simple` rather than the `qs`-backed `extended`, so a security patch would silently change how every `onRequest` handler parses its own query string.
Remove the override once the resolved Express line declares a `qs` range that admits only 6.16.1 or later.

Express 4 declares `body-parser` as `~1.20.5`, a range that admits every release below the patched 1.20.9, so `functions/package.json` overrides `body-parser` to `^1.20.9`.
Dropping the override reintroduces the trailing-bytes-after-a-compressed-body denial of service (GHSA-27r3-jxmh-p828), published 2026-10-23, which fails `Functions Verify` on every backend pull request.
The 1.20.9 release only tightens how a compressed request body is drained, so no `onRequest` handler parses its body differently.
Remove the override once the resolved Express line declares a `body-parser` range that admits only 1.20.9 or later.

Lint runs on ESLint 10 flat config (`functions/eslint.config.mjs`) with `typescript-eslint`.
ESLint 8 and 9 both resolve `minimatch` 3, whose only available `brace-expansion` line is vulnerable to the unbounded-expansion DoS advisory; ESLint 10 is the first release whose tree resolves the patched `brace-expansion` 5.
`eslint-config-google` and `eslint-plugin-import` were dropped in the same move: the former is eslintrc-only and unmaintained, and the latter still pins `minimatch` 3.
Google's `max-len` rule is reproduced directly in the flat config, so do not re-add either package to restore it.
ESLint 10, `@eslint/config-array` and `@typescript-eslint/typescript-estree` declare `minimatch` as `^10.2.x`, a range that cannot admit the patched 11.0.1, so `functions/package.json` overrides `minimatch` to `^11.0.1`.
Dropping the override reintroduces the globparts-amplification denial of service (GHSA-g3hv-75wg-m249), which fails `Functions Verify` on every backend pull request.
The tree is lint-only, and `npm run lint` passes on the 11 line unchanged.
Remove the override once the resolved ESLint and `typescript-eslint` lines declare a `minimatch` range that admits only 11.0.1 or later.

Do not re-add `firebase-functions-test` without a test that imports it.
The existing suite uses Node's test runner and injectable gateways, so the unused package only added the vulnerable `ts-deepmerge` tree.

## Web

Keep Astro at or above 7.3.8.
Astro 6.4.8 became vulnerable to new XSS advisories and capped `sharp` at the unpatched 0.34 line, so the website accepted Astro 7's Rust compiler and changed HTML whitespace defaults.
Astro 7.1.0 through 7.3.2 are covered by the View Transitions CSS injection advisory (GHSA-mpr7-6m5w-76rw), which failed `Web Verify` on 2026-10-23.
Astro 7.3.8 declares `sharp` as `^0.35.4`, past the inherited libvips advisory that covers every release below 0.35.0, so the `sharp` override that guarded the older `^0.34.0 || ^0.35.0` range was removed.
Astro 7.3.8 no longer depends on `esbuild`, but its `vite` dependency still declares `esbuild` as an optional peer at `^0.27.0 || ^0.28.0`, which admits the releases covered by the dev-server path-traversal advisory (`>=0.27.3 <0.28.1`), so `web/package.json` overrides `esbuild` to `^0.28.1`.
Remove that override once every declared range in the tree resolves only to patched releases, after `npm run build` passes.

Astro 7.3.8 reaches `undici` through `unifont`, which declares it as `^8.0.0`, a range that admits the releases below 8.12.2 covered by three advisories published 2026-10-23: the EventSource parser unbounded-memory denial of service (GHSA-4qv8-2p9j-2685), the Subresource Integrity bypass via non-lowercase algorithm tokens (GHSA-f72v-6w45-q472), and the unhandled-error denial of service on excessive content-encodings (GHSA-xjj6-f33q-929c).
They failed `Web Verify` on every pull request from that day, so `web/package.json` overrides `undici` to `^8.12.2`.
Remove the override once the resolved `unifont` line declares an `undici` range that admits only 8.12.2 or later, after `npm run build` passes.

## Root

`@firebase/firestore` declares `@grpc/grpc-js` as `~1.9.0`, a range that cannot admit the patched 1.13.6 and 1.14.5 releases, so the root `package.json` overrides `@grpc/grpc-js` to `^1.13.6`.
It reaches the root tree only through the `@firebase/rules-unit-testing` dev dependency that runs the emulator-backed rules suite.
Dropping the override reintroduces the unauthorized-certificate advisory (GHSA-m9gg-hp2v-232j) and the handler-error disclosure advisory (GHSA-f596-whhp-79r4), which fail the root audit gate on every pull request.
Remove the override once the resolved Firestore SDK declares a `@grpc/grpc-js` range that admits only patched releases, after `npm run test:firebase-rules` passes.
