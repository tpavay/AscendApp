---
name: ascend-deploy
description: Use when working on Ascend CI/CD - GitHub Actions workflows, the staging and production deploy pipelines, Firebase deploy ordering, deploy authentication, Fastlane lanes, match code signing, or TestFlight upload. Covers the required secrets, the deprecated ones, the real job graph, and the open OIDC / Workload Identity Federation migration.
paths:
  - .github/workflows/**
  - scripts/ci/**
  - fastlane/**
  - Gemfile
---

# Deploy

## Workflows

Read the workflow file before changing it - the job graph below is the contract, and it is not the same on staging and production.

`.github/workflows/ci.yml` runs on PRs to `develop` and `main`, and is the only automated gate before either. Every verify job is gated on the changed paths, so a functions-only PR skips the iOS jobs and an iOS-only PR skips the functions job:
- `changes` - a `dorny/paths-filter` job that resolves the `ios`, `functions`, `scripts`, `web`, and `root_npm` outputs. Every other job declares `needs: changes` and an `if:` on one of those outputs, so a new verify job is skipped by default until you add it to the filter.
- `functions-verify` - installs `functions/`, then lints, tests, and audits (`npm --prefix functions ci`, `run lint`, `test`, `audit --audit-level=low`).
- `scripts-verify` - audits the `scripts/` lockfile (`--package-lock-only`) and runs the `scripts/test/*.test.mjs` suite with `node --test`. No dependency install from `scripts/package.json` - the migration-discipline libraries and the shared vector-pinned predicate/derivation are pure Node; the one install is a globally pinned `@sentry/cli`, because the dSYM-upload suite asserts the release script's flags against that exact CLI's help. Keep that pin identical to the one in both deploy workflows. Gated on changes to `scripts/**` or `SharedTestVectors/**`.
- `web-verify` - installs `web/`, builds the Astro site, then audits. Gated on changes to `web/**`.
- `root-npm-verify` - audits the committed root lockfile with `--package-lock-only` (no install). Gated on changes to `package.json` / `package-lock.json`.
- `ios-verify` - runs `test` only (no build step) with `-scheme "AscendApp-Staging" -configuration Staging ENABLE_TESTABILITY=YES`. It provisions the simulator at runtime via `xcrun simctl` against the newest installed iOS runtime - downloading the runtime if the image ships none - then reuses a preferred iPhone model, falls back to any iPhone, and finally creates one, failing only when the runtime supports no iPhone device type. It does not pass `CODE_SIGNING_ALLOWED=NO`.
- `ios-verify-release` - the only job that compiles Release and the only place `CODE_SIGNING_ALLOWED=NO` appears, paired with `-scheme "AscendApp" -configuration Release -sdk iphoneos -destination "generic/platform=iOS"`. It exists so Release-only build errors surface on the PR instead of on the production deploy.

`ios-verify` is the **only** job anywhere that compiles `AscendAppTests`. `ios-verify-release` builds the app target alone, and both deploy pipelines only build the IPA. So a test target that stops compiling shows up on exactly one check, and "Release passed" or "Deploy Staging on develop passed" is not evidence that the tree is healthy. That asymmetry is what made the 2026-07-20 `develop` breakage read as CI infrastructure flake.

Two PRs that are each green on their own base can still break `develop` together: #248 added a call site and #251 added a parameter to the callee, merging 13 seconds apart. Nothing in CI re-verifies the merged result, so the next PR to rebase inherits the break. When a job starts failing on several unrelated branches at once, suspect the shared base before suspecting the runner.

Both iOS jobs pipe `xcodebuild` through `tee`, then run `scripts/ci/summarize-xcodebuild-failure.sh` and upload `build-logs/` as an artifact. Only `ios-verify` passes `-resultBundlePath`, so only its artifact carries an `.xcresult` bundle alongside the raw log - `ios-verify-release` is a build with no test results to bundle.
Both steps carry the same guard: `always()` plus an `xcodebuild` step outcome that is not `success`, not `skipped`, and not empty.
`always()` is what covers a job killed by `timeout-minutes`, which reports `cancelled` rather than `failure` - the exact case the logs exist to explain.
The outcome checks keep green runs from paying the upload, and keep the summarizer from annotating a log that was never written when an earlier step (simulator provisioning) failed first. `xcodebuild` interleaves diagnostics with the build commands of every target still in flight, so a compiler error routinely lands ~900 lines before the end of a 16,000-line log; read from the tail, the job looks like it died mid-copy of an SPM dependency with no diagnostic at all. The summarizer re-emits compiler errors and test failures as annotations, prints a resource snapshot, and says so explicitly when there genuinely is no diagnostic. Run it locally against a log downloaded with `gh api .../logs` - it strips the API's timestamp prefix.

Every npm project is audit-gated at `--audit-level=low`, so any newly published advisory fails its verify job. In the jobs that install and prove code (`functions-verify`, `web-verify`) the audit runs last on purpose, so an advisory cannot hide the lint/test/build results that prove the code itself. Deliberate pins and overrides that keep those audits clean are documented in `docs/dependency-security.md`.

A trigger pointing at a branch that no longer exists silently disables the workflow rather than failing. When the branching model changes, change the trigger in the same PR.

`.github/workflows/deploy-staging.yml` runs on pushes to `develop` and on manual dispatch. Three jobs, **not** a sequential chain:
- `build-ios` - Staging scheme, produces the IPA.
- `deploy-firebase` - has **no `needs:`**, so it runs in parallel with `build-ios` and will deploy even if the app build fails. Steps 2-6 of the old "sequential" story are in fact one command: `--only functions,firestore:rules,firestore:indexes,storage,hosting`. The workflow comment frames this as tolerated, but it is a known CI safety gap tracked in issue #202 - treat it as a gap, not as settled design.
- `upload-testflight` - the only gated job here: `needs: [build-ios, deploy-firebase]`. Last because it is hardest to reverse.

`develop` is what makes the staging trigger safe: staging cannot run on pushes to `main`, because `deploy-production.yml` already does and one push would deploy both. Keep the two deploy workflows on disjoint branches - pointing either at the other's branch reintroduces the double-deploy.

`.github/workflows/deploy-production.yml` runs on pushes to `main` and manual dispatch. It is **stricter** than staging, not a mirror of it: every job is gated behind `PRODUCTION_READY=true` plus GitHub `production` environment protection, and `deploy-firebase` keeps `needs: [production-gate, build-ios]`, so a failed build stops the deploy. The Firebase job is an ordered rollout rather than one combined deploy: indexes deploy and every declaration must report `READY`, then Functions deploy and the gate-critical exports must report `ACTIVE`, then Firestore rules, Storage rules, and Hosting deploy. The TestFlight upload still depends on the whole Firebase job, so the backend is ahead of the binary. `docs/production-backend-rollout-runbook.md` is the production operator contract and rollback guide.

## Deploy Authentication

**Today (what the workflows actually do):** both pipelines authenticate to Firebase with a single long-lived `FIREBASE_TOKEN` repository secret, passed as `--token "$FIREBASE_TOKEN"` on every `firebase-tools` deploy step (`deploy-staging.yml`, and each step of the production ordered rollout in `deploy-production.yml`). Both deploy jobs declare only `permissions: contents: read`. Commit a3c4021 moved deploys to this token and removed the `google-github-actions/auth@v2` steps. If you are editing a deploy step now, this is the mechanism you are working with.

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
- `build_staging` and `build_production` upload the archive's dSYMs to Sentry right after `xcodebuild archive` and before the IPA export, so a build that cannot be symbolicated never reaches TestFlight. Both build jobs install the pinned Sentry CLI and fail early on a missing `SENTRY_AUTH_TOKEN`. Contract and environment variables: `docs/sentry-setup.md`.
- Required iOS signing secrets for CI:
  - `MATCH_GIT_URL`
  - `MATCH_PASSWORD`
  - `MATCH_GIT_PRIVATE_KEY`
- Also required by both build jobs: `SENTRY_AUTH_TOKEN`.

### Build numbers (CFBundleVersion allocator)
- `BUILD_NUMBER` is derived by `scripts/ci/derive-build-number.sh <slot>` in a pre-archive "Derive build number" step, not from `github.run_id`/`run_number`. The step assigns the result to a variable first so a non-zero exit propagates under `set -e` before anything is written to `$GITHUB_ENV`; a failed derivation stops the deploy instead of exporting an empty build number.
- Value: `(UTC epoch seconds - 2026-01-01T00:00:00Z) * 2 + slot`. Staging passes slot `0`, production slot `1`. Two slots consume two integers per second, giving `4294967296 / 2 = 2147483648` seconds of range - exhausting around 2094-01-19 UTC, where the script hard-fails rather than emitting a value above the 32-bit App Store ceiling.
- Uniqueness depends on two invariants, both enforced by `scripts/test/ci-workflow-contracts.test.mjs`: every uploadable workflow (one that runs a signed `build_*` lane or `upload_testflight`) declares a **fixed, non-ref-scoped** concurrency group (`deploy-staging`, `deploy-production`) so all of its runs - including manual `workflow_dispatch` from any ref - serialize; and each such workflow passes a **distinct** allocator slot. A new uploadable workflow, a duplicate slot, or a group that regains a `${{ github.ref }}` component fails that contract test.
- The script also refuses any value at or below the recorded `PREVIOUS_BUILD_NUMBER_FLOOR`. Do not raise `BUILD_NUMBER_EPOCH_SECONDS`: a larger epoch emits build numbers below already-uploaded builds, which TestFlight rejects irreversibly. If the range is ever exhausted, ship a new marketing version with a reset build-number scheme instead.
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
