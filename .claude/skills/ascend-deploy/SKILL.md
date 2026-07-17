---
name: ascend-deploy
description: Use when working on Ascend CI/CD - GitHub Actions workflows, the staging and production deploy pipelines, Firebase deploy ordering, OIDC / Workload Identity Federation deploy auth, Fastlane lanes, match code signing, or TestFlight upload. Covers the required secrets, the deprecated ones, and the pipeline job order.
paths:
  - .github/workflows/**
  - fastlane/**
  - Gemfile
---

# Deploy

## Workflows
- `.github/workflows/ci.yml` runs on PRs to `main`. A `changes` job gates each verify job on the changed paths, so a functions-only PR skips the iOS jobs and an iOS-only PR skips the functions job:
  - `functions-verify` installs `functions/` and runs its test suite.
  - `ios-verify` builds the `AscendApp-Staging` scheme in the `Staging` configuration on an iPhone simulator with `ENABLE_TESTABILITY=YES` and runs the `AscendAppTests` suite. It picks the simulator at runtime from `xcodebuild -showdestinations`, preferring recent iPhone models and failing if none are available.
  - `ios-verify-release` builds the `AscendApp` scheme in the `Release` configuration against `-sdk iphoneos` with `CODE_SIGNING_ALLOWED=NO`. It only builds, and exists so Release-only and device-only compile errors surface on the PR instead of first appearing in the production deploy.
- CI is the only automated gate before `main`, so a workflow trigger that points at a branch which no longer exists silently disables it. When the branching model changes, change this trigger in the same PR.
- `.github/workflows/deploy-staging.yml` runs on manual dispatch only, and has three jobs:
  1. Build iOS app (Staging scheme, produce IPA)
  2. Deploy Firebase in one step (Functions, Firestore rules, Firestore indexes, Storage rules, Hosting). This runs in parallel with the IPA build: the backend deploy does not depend on the iOS binary, and staging tolerates the backend landing even when the app build fails.
  3. Upload to TestFlight. It needs both jobs above, so it runs last (hardest to reverse).
- Staging has no automatic trigger. It cannot simply run on pushes to `main`, because `deploy-production.yml` already does, and one push would deploy both. Giving staging its own non-colliding trigger is tracked in issue #203.
- `.github/workflows/deploy-production.yml` runs on pushes to `main` and manual dispatch. It deploys the same targets as staging, including Firestore indexes, with Release configuration. Unlike staging, it stays strictly sequential (stop on failure) - every job needs the one before it - and remains gated behind `PRODUCTION_READY=true` plus GitHub `production` environment protection.

## Deploy Authentication (OIDC)
- GitHub Actions deploys to Firebase must use OIDC + GCP Workload Identity Federation.
- Do not use long-lived Firebase/GCP JSON key secrets for deploy auth.
- Required staging secrets:
  - `GCP_WORKLOAD_IDENTITY_PROVIDER`
  - `GCP_SERVICE_ACCOUNT_EMAIL`
- Required production secrets:
  - `GCP_WORKLOAD_IDENTITY_PROVIDER_PRODUCTION`
  - `GCP_SERVICE_ACCOUNT_EMAIL_PRODUCTION`
- Deprecated for deploy auth:
  - `FIREBASE_SERVICE_ACCOUNT_STAGING`

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
