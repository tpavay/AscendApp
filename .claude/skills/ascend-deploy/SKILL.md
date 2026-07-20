---
name: ascend-deploy
description: Use when working on Ascend CI/CD - GitHub Actions workflows, the staging and production deploy pipelines, Firebase deploy ordering, deploy authentication, Fastlane lanes, match code signing, or TestFlight upload. Covers the required secrets, the deprecated ones, the real job graph, and the open OIDC / Workload Identity Federation migration.
paths:
  - .github/workflows/**
  - fastlane/**
  - Gemfile
---

# Deploy

## Workflows

Read the workflow file before changing it - the job graph below is the contract, and it is not the same on staging and production.

`.github/workflows/ci.yml` runs on PRs to `develop` and `main`, and is the only automated gate before either. Every verify job is gated on the changed paths, so a functions-only PR skips the iOS jobs and an iOS-only PR skips the functions job:
- `changes` - a `dorny/paths-filter` job that resolves the `ios`, `functions`, `scripts`, `web`, and `root_npm` outputs. Every other job declares `needs: changes` and an `if:` on one of those outputs, so a new verify job is skipped by default until you add it to the filter.
- `functions-verify` - installs `functions/`, then lints, tests, and audits (`npm --prefix functions ci`, `run lint`, `test`, `audit --audit-level=low`).
- `scripts-verify` - audits the `scripts/` lockfile (`--package-lock-only`) and runs the `scripts/test/*.test.mjs` suite with `node --test` (no dependency install - the migration-discipline libraries and the shared vector-pinned predicate/derivation are pure Node). Gated on changes to `scripts/**` or `SharedTestVectors/**`.
- `web-verify` - installs `web/`, builds the Astro site, then audits. Gated on changes to `web/**`.
- `root-npm-verify` - audits the committed root lockfile with `--package-lock-only` (no install). Gated on changes to `package.json` / `package-lock.json`.
- `ios-verify` - runs `test` only (no build step) with `-scheme "AscendApp-Staging" -configuration Staging ENABLE_TESTABILITY=YES`. It provisions the simulator at runtime via `xcrun simctl` against the newest installed iOS runtime - downloading the runtime if the image ships none - then reuses a preferred iPhone model, falls back to any iPhone, and finally creates one, failing only when the runtime supports no iPhone device type. It does not pass `CODE_SIGNING_ALLOWED=NO`.
- `ios-verify-release` - the only job that compiles Release and the only place `CODE_SIGNING_ALLOWED=NO` appears, paired with `-scheme "AscendApp" -configuration Release -sdk iphoneos -destination "generic/platform=iOS"`. It exists so Release-only build errors surface on the PR instead of on the production deploy.

Every npm project is audit-gated at `--audit-level=low`, so any newly published advisory fails its verify job. In the jobs that install and prove code (`functions-verify`, `web-verify`) the audit runs last on purpose, so an advisory cannot hide the lint/test/build results that prove the code itself. Deliberate pins and overrides that keep those audits clean are documented in `docs/dependency-security.md`.

A trigger pointing at a branch that no longer exists silently disables the workflow rather than failing. When the branching model changes, change the trigger in the same PR.

`.github/workflows/deploy-staging.yml` runs on pushes to `develop` and on manual dispatch. Three jobs, **not** a sequential chain:
- `build-ios` - Staging scheme, produces the IPA.
- `deploy-firebase` - has **no `needs:`**, so it runs in parallel with `build-ios` and will deploy even if the app build fails. Steps 2-6 of the old "sequential" story are in fact one command: `--only functions,firestore:rules,firestore:indexes,storage,hosting`. The workflow comment frames this as tolerated, but it is a known CI safety gap tracked in issue #202 - treat it as a gap, not as settled design.
- `upload-testflight` - the only gated job here: `needs: [build-ios, deploy-firebase]`. Last because it is hardest to reverse.

`develop` is what makes the staging trigger safe: staging cannot run on pushes to `main`, because `deploy-production.yml` already does and one push would deploy both. Keep the two deploy workflows on disjoint branches - pointing either at the other's branch reintroduces the double-deploy.

`.github/workflows/deploy-production.yml` runs on pushes to `main` and manual dispatch. It is **stricter** than staging, not a mirror of it: every job is gated behind `PRODUCTION_READY=true` plus GitHub `production` environment protection, and `deploy-firebase` keeps `needs: [production-gate, build-ios]`, so a failed build stops the deploy. Same combined `--only` deploy command, Release configuration.

## Deploy Authentication

**Today (what the workflows actually do):** both pipelines authenticate to Firebase with a single long-lived `FIREBASE_TOKEN` repository secret, passed as `--token "$FIREBASE_TOKEN"` on the `firebase-tools` deploy step (`deploy-staging.yml`, `deploy-production.yml`). Both deploy jobs declare only `permissions: contents: read`. Commit a3c4021 moved deploys to this token and removed the `google-github-actions/auth@v2` steps. If you are editing a deploy step now, this is the mechanism you are working with.

**Target (not yet implemented):** move deploys to OIDC + GCP Workload Identity Federation and retire the standing long-lived credential. This is a real open security gap, not a settled decision - `FIREBASE_TOKEN` is a broad, non-expiring credential that OIDC's short-lived tokens would replace.

The migration needs work that does not exist yet, so do not assume any of it is in place:
- No OIDC or WIF reference exists anywhere in `.github/`.
- These secrets are **not currently configured** - do not reference them from a workflow until they are provisioned: `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT_EMAIL`, and the `_PRODUCTION` variants of both.
- The deploy jobs would additionally need `permissions: id-token: write`.

Deprecated for deploy auth: `FIREBASE_SERVICE_ACCOUNT_STAGING`.

Do not introduce a *new* long-lived JSON service-account key for deploy auth; that moves away from the target.

## Fastlane
- `Gemfile` and `fastlane/` define lanes for:
  - `build_staging`
  - `build_production`
  - `upload_testflight`
- iOS deploy lanes use `fastlane match` for signing material sync (CI runs in `readonly` mode).
- Required iOS signing secrets for CI:
  - `MATCH_GIT_URL`
  - `MATCH_PASSWORD`
  - `MATCH_GIT_PRIVATE_KEY`
- Legacy manual-signing CI secrets are deprecated:
  - `BUILD_CERTIFICATE_BASE64`
  - `BUILD_PROVISION_PROFILE_BASE64`
  - `P12_PASSWORD`
  - `KEYCHAIN_PASSWORD`
  - production-specific `*_PRODUCTION` variants of the above

## CI Firebase plists

`GoogleService-Info*.plist` files are gitignored. CI decodes them from base64 secrets into `AscendApp/App/Firebase/` before building:
`GOOGLE_SERVICE_INFO_DEV_BASE64`, `GOOGLE_SERVICE_INFO_STAGING_BASE64`, `GOOGLE_SERVICE_INFO_PRODUCTION_BASE64`.

## Related
- For archive/export/IPA automation, load `asc-xcode-build`.
- For App Store Connect release, metadata, submission, and TestFlight tasks, load `asc-release-flow`, `asc-metadata-sync`, `asc-submission-health`, `asc-testflight-orchestration`.
