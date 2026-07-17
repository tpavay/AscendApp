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

`.github/workflows/ci.yml` runs on PRs to `main`, and is the only automated gate before `main`. Every verify job is gated on the changed paths, so a functions-only PR skips the iOS jobs and an iOS-only PR skips the functions job:
- `changes` - a `dorny/paths-filter` job that resolves the `ios` and `functions` outputs. Every other job declares `needs: changes` and an `if:` on one of those outputs, so a new verify job is skipped by default until you add it to the filter.
- `functions-verify` - installs `functions/` and runs its test suite (`npm --prefix functions ci`, then `npm --prefix functions test`).
- `ios-verify` - runs `test` only (no build step) with `-scheme "AscendApp-Staging" -configuration Staging ENABLE_TESTABILITY=YES`. It picks the simulator at runtime from `xcodebuild -showdestinations`, preferring recent iPhone models and failing if none are available. It does not pass `CODE_SIGNING_ALLOWED=NO`.
- `ios-verify-release` - the only job that compiles Release and the only place `CODE_SIGNING_ALLOWED=NO` appears, paired with `-scheme "AscendApp" -configuration Release -sdk iphoneos -destination "generic/platform=iOS"`. It exists so Release-only build errors surface on the PR instead of on the production deploy.

A trigger pointing at a branch that no longer exists silently disables the workflow rather than failing. When the branching model changes, change the trigger in the same PR.

`.github/workflows/deploy-staging.yml` runs on manual dispatch only. Three jobs, **not** a sequential chain:
- `build-ios` - Staging scheme, produces the IPA.
- `deploy-firebase` - has **no `needs:`**, so it runs in parallel with `build-ios` and will deploy even if the app build fails. Steps 2-6 of the old "sequential" story are in fact one command: `--only functions,firestore:rules,firestore:indexes,storage,hosting`. The workflow comment frames this as tolerated, but it is a known CI safety gap tracked in issue #202 - treat it as a gap, not as settled design.
- `upload-testflight` - the only gated job here: `needs: [build-ios, deploy-firebase]`. Last because it is hardest to reverse.

Staging has no automatic trigger, which is a known gap rather than the end state. It cannot simply run on pushes to `main`, because `deploy-production.yml` already does and one push would deploy both. Choosing a non-colliding trigger is tracked in issue #203.

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
