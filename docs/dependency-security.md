# Dependency Security

Run `npm audit --package-lock-only` from the repository root and from each npm project before upgrading dependencies.
Treat `functions/` as production code because it runs with Firebase Admin credentials, while `web/` is the deployed static site.
The root package intentionally does not install `firebase-tools`; its rules-test command invokes the CLI directly, so a second pinned CLI tree would be unused and vulnerable between releases.
It pins `firebase-tools@15.22.1`, and that same pin applies everywhere the CLI runs: CI (`ci.yml`'s `firebase-verify` job), `functions/package.json`'s `test:emulator` script, both deploy workflows, and the human-run Firebase commands documented in `CLAUDE.md`, `docs/production-backend-rollout-runbook.md`, `functions/EMAIL_SETUP.md`, and the `live-climb-content` skill.
Rules have to be validated and shipped by the same CLI, so validation never passes on a version that differs from the one that deploys, and an unpinned `@latest` would let an upstream release turn unrelated required checks red.
Bump every one of those pins together.

## Functions

Keep `firebase-admin` on the latest 13.x release until a dedicated 14.x migration is verified against the full Functions test suite.
The 13.x tree still requests `uuid` 9 through Google Cloud clients, so `functions/package.json` overrides `uuid` to `^11.1.1`.
Those clients exercise the unchanged `v4` API, and dropping the override reintroduces the buffer-bounds advisory.

Lint runs on ESLint 10 flat config (`functions/eslint.config.mjs`) with `typescript-eslint`.
ESLint 8 and 9 both resolve `minimatch` 3, whose only available `brace-expansion` line is vulnerable to the unbounded-expansion DoS advisory; ESLint 10 is the first release whose tree resolves the patched `brace-expansion` 5.
`eslint-config-google` and `eslint-plugin-import` were dropped in the same move: the former is eslintrc-only and unmaintained, and the latter still pins `minimatch` 3.
Google's `max-len` rule is reproduced directly in the flat config, so do not re-add either package to restore it.

Do not re-add `firebase-functions-test` without a test that imports it.
The existing suite uses Node's test runner and injectable gateways, so the unused package only added the vulnerable `ts-deepmerge` tree.

## Web

Keep Astro at or above 7.1.5.
Astro 6.4.8 became vulnerable to new XSS advisories and capped `sharp` at the unpatched 0.34 line, so the website accepted Astro 7's Rust compiler and changed HTML whitespace defaults.
Astro 7 still declares `sharp` as `^0.34.0 || ^0.35.0` while the inherited libvips advisory covers every release below 0.35.0, so `web/package.json` overrides `sharp` to `^0.35.0`.
Astro 7 declares `esbuild` as `^0.28.0` and its `vite` dependency declares `^0.27.0 || ^0.28.0`, both of which still admit the releases covered by the dev-server path-traversal advisory (`>=0.27.3 <0.28.1`), so `web/package.json` overrides `esbuild` to `^0.28.1`.
Remove either override once every declared range in the tree resolves only to patched releases, after `npm run build` passes.
