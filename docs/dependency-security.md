# Dependency Security

Run `npm audit --package-lock-only` from the repository root and from each npm project before upgrading dependencies.
Treat `functions/` as production code because it runs with Firebase Admin credentials, while `web/` is the deployed static site.
The root package intentionally does not install `firebase-tools`; its rules-test command invokes `firebase-tools@latest` directly, so a second pinned CLI tree would be unused and vulnerable between releases.

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

Keep Astro on the latest 6.x release until an Astro 7 migration deliberately accepts its Rust compiler and changed HTML whitespace defaults.
Astro 6.4.8 fixes the deployed Astro advisories but still requests vulnerable `esbuild` 0.27.x, so `web/package.json` overrides `esbuild` to `^0.28.1`.
Remove the override once Astro's declared range resolves to a patched `esbuild` release, after `npm run build` passes.
