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
- `ASCEND_SENTRY_ENABLED`: optional kill switch. Use `false`/`0`/`no`/`off` to force-disable Sentry.

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

Use `.agents/skills/ascend-error-triage/SKILL.md` for the triage rubric.

## Debug Symbols

For production-quality stack traces, the app build phase runs `scripts/upload-sentry-dsyms.sh` after the Firebase Crashlytics upload step.

Required CI/build environment:

- `SENTRY_AUTH_TOKEN`: secret token used by `sentry-cli`.
- `SENTRY_ORG`: optional; defaults to `ascend-uk`.
- `SENTRY_PROJECT`: optional; defaults to `ascend-ios`.
- `SENTRY_CLI_PATH`: optional; use only when `sentry-cli` is not on `PATH`.

GitHub Actions passes `secrets.SENTRY_AUTH_TOKEN` into the Fastlane staging and production build steps. This does not belong in the private `match` repo; `match` should stay limited to certificates and provisioning profiles.

Local builds skip Sentry dSYM upload when `SENTRY_AUTH_TOKEN` is missing. Keep Sentry auth tokens out of the repo.
