# Sentry Setup

Ascend uses Sentry as a diagnostics companion to Firebase Crashlytics.

## Role

- **Sentry**: issue triage, breadcrumbs, handled errors, release/environment filtering, and agent-assisted debugging.
- **Crashlytics**: Firebase-native crash-free metrics and release stability.
- **Mixpanel/Firebase Analytics**: product funnels, retention, and behavior analytics.

Sentry is not used for product analytics or cross-app tracking.

## App Configuration

The app reads Sentry config from `Info.plist`:

- `ASCEND_SENTRY_DSN`: the Sentry project DSN.
- `ASCEND_SENTRY_ENABLED`: optional kill switch for the in-app SDK only. Use `false`/`0`/`no`/`off` to stop the app from initializing Sentry and sending events.
  It does not gate dSYM upload: symbols are debug metadata with no user data, and upload stays independent so a shipped build can never become permanently unsymbolicated.

Sentry is still gated by `TelemetryManager.shouldEnableCollection()`:

- Debug defaults to off unless `ASC_DEBUG_TELEMETRY_ENABLED=true` or `-TelemetryEnabled` is set.
- Staging and Release default to on when a DSN is present.

Events are tagged with:

- `app_environment`: `dev`, `staging`, or `production`
- `build_config`: `debug`, `staging`, or `release`
- `app_version`
- `build_number`
- `ascend_error_context` and `ascend_error_code` for handled errors

## MCP Workflow

Use Sentry MCP for agent triage:

```sh
codex mcp add sentry https://mcp.sentry.dev/mcp
```

Authentication should happen through Sentry OAuth or a local token flow. Do not commit Sentry tokens, auth headers, DSNs, or MCP credentials.

Typical prompt:

```text
Assess unresolved production Sentry errors from the past 14 days. Prioritize them, explain likely root causes, and fix the top actionable issue.
```

Use `.claude/skills/sentry/SKILL.md` for the triage rubric.

## Debug Symbols

For production-quality stack traces, both signed Fastlane build lanes run `scripts/upload-sentry-dsyms.sh` immediately after the archive is created and before the IPA is exported.
The staging and production workflows install a pinned Sentry CLI before invoking Fastlane.
The upload waits for Sentry to process the files under an explicit bounded timeout, so a degraded Sentry queue fails fast with a Sentry-specific error instead of consuming the release job's timeout.
Any missing token, CLI, archive dSYM directory, or upload failure stops the CI build before an unreadable IPA can reach TestFlight.

The script takes the dSYM directory to upload as its first argument; the lanes pass the archive's `dSYMs` folder.
With no argument it falls back to `DWARF_DSYM_FOLDER_PATH`.

Required CI/build environment:

- `SENTRY_AUTH_TOKEN`: secret token used by `sentry-cli`.
- `SENTRY_ORG`: optional; defaults to `ascend-uk`.
- `SENTRY_PROJECT`: optional; defaults to `ascend-ios`.
- `SENTRY_CLI_PATH`: optional; use only when `sentry-cli` is not on `PATH`.
- `SENTRY_WAIT_TIMEOUT`: optional; seconds to wait for server-side processing before failing. Defaults to `300`.

GitHub Actions validates and passes `secrets.SENTRY_AUTH_TOKEN` into the Fastlane staging and production build steps.
This does not belong in the private `match` repo; `match` should stay limited to certificates and provisioning profiles.

Local Fastlane archives skip Sentry dSYM upload when `SENTRY_AUTH_TOKEN` is missing.
CI archives fail when the secret is missing.
Keep Sentry auth tokens out of the repo.
