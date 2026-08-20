---
name: sentry
description: Use when reading, triaging, searching, or updating Sentry issues and events for the Ascend iOS app — error investigation, issue detail, stack traces, tag breakdowns, resolving/archiving issues, and weekly error-report follow-up.
---

# Sentry Access

Use this skill for any request to look at Sentry errors, investigate an issue, pull event details, or change issue state (resolve, archive, assign).

This is harness-neutral. If the current AI tool does not support skills, paste or reference this file and follow it as the source-of-truth workflow.

## Project Constants

- Org slug: `ascend-uk`
- Project slug: `ascend-ios`
- Project ID: `4511621439815680`
- API base: `https://sentry.io/api/0`
- Web UI: `https://ascend-uk.sentry.io`
- Issue short IDs look like `ASCEND-IOS-B`; numeric issue IDs look like `7582495782`. Both appear in alert emails.
- **Only `production` reports.** Dev and staging no longer initialise the SDK at all (`SentryReportingPolicy`; `docs/sentry-setup.md`), so `environment:dev` and `environment:staging` hold history, not live traffic. `SentryOptionsFactory` owns every option the app starts with.
- Useful custom tags set by the app: `ascend_error_code`, `ascend_error_context`, `build_config`, `app_environment`, `has_app_access`, `last_diagnostic_event`, `release` (format `com.TylerPavay.AscendApp.staging@1.0+<build>`).

## Authentication

All API calls need a **user auth token** in the `Authorization: Bearer` header.

Token resolution order:

1. `SENTRY_AUTH_TOKEN` environment variable.
2. `token` under `[auth]` in `~/.sentryclirc`.

```bash
SENTRY_TOKEN="${SENTRY_AUTH_TOKEN:-$(awk -F= '/^token/{gsub(/ /,"",$2); print $2}' ~/.sentryclirc 2>/dev/null)}"
```

If no token is found, stop and ask the user to create one:

1. Open `https://ascend-uk.sentry.io/settings/account/api/auth-tokens/` (User Auth Tokens — NOT an Organization Auth Token; org tokens are CI-scoped for releases/dSYMs).
2. Create a token with scopes: `event:read`, `event:write`, `org:read`, `project:read`. Add `event:admin` only if issue deletion is needed.
3. Store it user-locally, e.g. `export SENTRY_AUTH_TOKEN=...` in `~/.zshrc`, or in `~/.sentryclirc`.

Rules:

- Never commit a token, write it into any repo file, or echo it into output/logs.
- The `SENTRY_AUTH_TOKEN` GitHub Actions secret is a separate CI token for dSYM upload (fastlane). Do not reuse or print it.

Verify access:

```bash
curl -sf -H "Authorization: Bearer $SENTRY_TOKEN" \
  "https://sentry.io/api/0/organizations/ascend-uk/" >/dev/null \
  && echo "sentry auth ok" || echo "sentry auth FAILED"
```

## Read Operations (safe, do freely)

List unresolved issues (default triage view; sorted by last seen):

```bash
curl -s -H "Authorization: Bearer $SENTRY_TOKEN" \
  "https://sentry.io/api/0/projects/ascend-uk/ascend-ios/issues/?query=is:unresolved&statsPeriod=14d" \
  | jq -r '.[] | [.shortId, .count, .userCount, .substatus, .title] | @tsv'
```

Common query variations (URL-encode the `query` value):

- Filter environment: append `&environment=staging` (or `dev` / `production`).
- Sort by event count: `&sort=freq`. New issues first: `&sort=new`.
- By custom tag: `query=is:unresolved ascend_error_code:lifecycle_event_record_failed`
- By release: `query=release:com.TylerPavay.AscendApp.staging@1.0+120`
- Escalating only: `query=is:unresolved is:escalating`

Look up an issue by short ID (from an alert email):

```bash
curl -s -H "Authorization: Bearer $SENTRY_TOKEN" \
  "https://sentry.io/api/0/organizations/ascend-uk/issues/?query=issue:ASCEND-IOS-B&project=4511621439815680" | jq '.[0]'
```

Issue detail (counts, first/last seen, status):

```bash
curl -s -H "Authorization: Bearer $SENTRY_TOKEN" \
  "https://sentry.io/api/0/organizations/ascend-uk/issues/{issue_id}/" | jq .
```

Latest event for an issue (full stack trace, breadcrumbs, tags, contexts — the main debugging payload; it is large, so filter with `jq`):

```bash
curl -s -H "Authorization: Bearer $SENTRY_TOKEN" \
  "https://sentry.io/api/0/organizations/ascend-uk/issues/{issue_id}/events/latest/" \
  | jq '{title, dateCreated, tags, "exception": [.entries[] | select(.type=="exception")], "breadcrumbs": [.entries[] | select(.type=="breadcrumbs")]}'
```

Tag breakdown for an issue (e.g. which releases/devices are affected):

```bash
curl -s -H "Authorization: Bearer $SENTRY_TOKEN" \
  "https://sentry.io/api/0/organizations/ascend-uk/issues/{issue_id}/tags/release/values/" | jq .
```

Recent events across an issue:

```bash
curl -s -H "Authorization: Bearer $SENTRY_TOKEN" \
  "https://sentry.io/api/0/organizations/ascend-uk/issues/{issue_id}/events/?statsPeriod=14d" \
  | jq -r '.[] | [.dateCreated, .eventID, .title] | @tsv'
```

Pagination: responses use a `Link` header with `cursor`. Fetch the next page by appending `&cursor=<value>` from the `Link` header where `results="true"`.

## Write Operations (mutations — only when the user explicitly asks)

Never resolve, archive, assign, or delete issues as a side effect of investigation. Confirm intent first, and name the short IDs being mutated.

Resolve an issue:

```bash
curl -s -X PUT -H "Authorization: Bearer $SENTRY_TOKEN" -H "Content-Type: application/json" \
  "https://sentry.io/api/0/organizations/ascend-uk/issues/{issue_id}/" \
  -d '{"status": "resolved"}' | jq '{shortId, status}'
```

Resolve in next release: `{"status": "resolvedInNextRelease"}`.

Archive (ignore) an issue: `{"status": "ignored"}`. Archive until it escalates: `{"status": "ignored", "substatus": "archived_until_escalating"}`.

Bulk update by ID list:

```bash
curl -s -X PUT -H "Authorization: Bearer $SENTRY_TOKEN" -H "Content-Type: application/json" \
  "https://sentry.io/api/0/projects/ascend-uk/ascend-ios/issues/?id={id1}&id={id2}" \
  -d '{"status": "resolved"}'
```

Add a triage note to an issue:

```bash
curl -s -X POST -H "Authorization: Bearer $SENTRY_TOKEN" -H "Content-Type: application/json" \
  "https://sentry.io/api/0/organizations/ascend-uk/issues/{issue_id}/comments/" \
  -d '{"text": "Root cause: ..."}'
```

## Triage Conventions

- Everything arriving now is production. Historic `environment:staging` (TestFlight + CI) and `environment:dev` (simulator/local) issues predate the production-only gate and stopped growing when it shipped; date-bound any query that mixes them in, and never read a flat 30-day count as current volume.
- A production error carries a masked screenshot and a view hierarchy. There is no session replay and there is not meant to be: it was built on this branch and dropped, because on-error mode records the whole session after the first error and buffer mode renders the screen on the main thread once a second in every session (`docs/sentry-setup.md`). Do not go looking for a replay, and do not turn one on to investigate an issue. Everything legible in the two attachments is painted out - open them for layout, navigation state, and which surface failed, never expecting to read a value off one.
- `ascend_flood_guard_dropped` on an event means that session had already hit a client-side ceiling and dropped that many events before this one. Treat it as evidence of a loop, and remember the counts below it are floors rather than totals. Crashes and app hangs are never dropped, so their counts are always exact.
- Issues titled `AscendAppTests.*` are unit-test errors leaking into Sentry from a test host with telemetry enabled — telemetry noise to suppress at the source, never real app bugs. Safe to archive after the leak is fixed.
- `App Hang` issues are Sentry ANR detection. Unsymbolicated frames (`?` frames) mean dSYMs were missing for that build; check whether the release predates CI dSYM upload before investigating.
- When reporting findings, cite issue short IDs and web links (`https://ascend-uk.sentry.io/issues/{issue_id}/`) so the user can click through.

## Output Checklist

When done, report:

- Which issues were inspected (short IDs + links).
- Root-cause hypothesis per issue, with the app code path where relevant.
- Any mutations performed (resolve/archive/note), each explicitly requested by the user.
- Whether any follow-up code fix is needed, and where.
