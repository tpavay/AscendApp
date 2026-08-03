---
name: ascend-deploy
description: Use when working on Ascend CI/CD - GitHub Actions workflows, the staging and production deploy pipelines, Firebase deploy ordering, deploy authentication, Fastlane lanes, match code signing, or TestFlight upload. Covers the required secrets, the deprecated ones, the real job graph, and the open OIDC / Workload Identity Federation migration.
paths:
  - .github/workflows/**
  - scripts/ci/**
  - fastlane/**
  - Gemfile
  - Gemfile.lock
  - .ruby-version
  - firebase.json
  - .firebaserc
  - firestore.rules
  - firestore.indexes.json
  - storage.rules
  - remoteconfig.template.json
---

# Deploy

## Workflows

Read the workflow file before changing it - the job graph below is the contract, and it is not the same on staging and production.

`.github/workflows/ci.yml` runs on CI-relevant PR changes targeting `develop` and `main`.
Every verify job is gated on the changed paths, so a functions-only PR skips the iOS jobs and an iOS-only PR skips the functions job:
- `changes` - a `dorny/paths-filter` job that resolves the `ios`, `functions`, `scripts`, `web`, `root_npm`, `firebase`, `ruby`, `swiftdata_schema`, and `remote_config` outputs. Every other job declares `needs: changes` and an `if:` on one of those outputs, so a new verify job is skipped by default until you add it to the filter.
- `functions-verify` - installs `functions/`, then lints, unit-tests, runs the emulator-backed suite, and audits (`npm --prefix functions ci`, `run lint`, `test`, `run test:emulator`, `audit --audit-level=low`).
  `test:emulator` runs `functions/test/emulator/*` against a real Firestore through `emulators:exec`, because the unit suites inject a store and so never exercise the Admin adapters that actually write the world-readable leaderboard and drain the email queue.
  It runs one file at a time (`--test-concurrency=1`): every suite in that directory shares the single emulator database and wipes it between tests, so two files running concurrently would clear each other's seed data mid-test.
  It asserts `FIRESTORE_EMULATOR_HOST` is set rather than skipping, so it cannot pass by doing nothing.
  It therefore pins the same Temurin JDK 21 `actions/setup-java` step `firebase-verify` does, for the same reason.
- `scripts-verify` - installs `scripts/` (`npm --prefix scripts ci`), runs the `scripts/test/*.test.mjs` suite with `node --test`, then audits the `scripts/` lockfile (`--package-lock-only`).
  The install is required: the public-identity contract suite imports and spawns `dev-db.mjs`, which imports `firebase-admin`, so a suite that exercises a real script rather than a pure library needs the same dependencies an operator has.
  It also installs a globally pinned `@sentry/cli`, because the dSYM-upload suite asserts the release script's flags against that exact CLI's help.
  Keep that pin identical to the one in both deploy workflows.
  The job is gated on changes to `scripts/**` or `SharedTestVectors/**`, plus the iOS paths the monetization build-configuration suite reads directly, the Firebase configuration files the structural-validation suite reads directly, and the web, legal, and guidance paths the subscription launch-offer suite reads directly.
  A suite here that asserts against tracked non-`scripts/` files must add its inputs to this filter, or the assertion silently stops running on the PRs that break it.
- `swiftdata-schema-verify` - runs `node scripts/check-swiftdata-schema.mjs` against the Swift sources, on its own `swiftdata_schema` filter of `AscendApp/**` plus `SharedTestVectors/**`. That filter is the whole app tree on purpose: an `@Model` can be declared anywhere, so it is never narrowed to the folders models live in today. `ascend-data-migration` owns what the check enforces.
  Deliberately dependency-free - no `npm ci`, no `npm audit` - so a Swift-only PR cannot be blocked by an advisory against a `scripts/`-only Node dependency. Keep it out of `scripts-verify` for that reason, even though the check ships under `scripts/`.
- `remote-config-verify` - runs `node scripts/ci/report-kill-switch-changes.mjs --base-ref <PR base sha>` on its own `remote_config` filter, and checks out with `fetch-depth: 0` so the base commit is present for the added/removed comparison. Dependency-free for the same reason as the SwiftData gate. It asserts only the half a pull request can prove - a flag added on a branch is by definition not published yet, so the live-backend check is the archive preflight's job, not this one. `docs/remote-config-kill-switches.md` owns what it asserts and reports.
- `web-verify` - installs `web/`, builds the Astro site, then audits. Gated on changes to `web/**`.
- `root-npm-verify` - audits the committed root lockfile with `--package-lock-only` (no install). Gated on changes to `package.json` / `package-lock.json`.
- `firebase-verify` - structurally validates `firebase.json`, `.firebaserc`, and `firestore.indexes.json`, then starts the Firestore and Storage emulators and runs `tests/firebase-rules/*.test.mjs`. The emulators load both rules files before the suite, so syntax failures stop the job.
  `npm run test:firebase-rules` pins `firebase-tools` to the same version the deploy steps run, so the CLI that validates the rules is the CLI that ships them. `docs/dependency-security.md` owns that pin and lists every place it is repeated; bump them together.
  It runs no `npm audit` - `root-npm-verify` owns that signal for the root tree.
  It pins a Temurin JDK 21 with `actions/setup-java` before the emulator step: the emulators are JVM processes and `firebase-tools` refuses to start them on a JDK older than 21, which is what the runner image defaults to.
  Keep that step whenever the `firebase-tools` pin moves - a newer CLI raises the floor, it never lowers it.
- `ruby-verify` - pins `ruby-version: "3.1"`, runs `bundle install --deployment`, and loads the lane DSL with `bundle exec fastlane lanes`. Gated on the Ruby version, Gem bundle, and `fastlane/**`.
  That pin deliberately ignores `.ruby-version` (3.2.2, the local development Ruby) and matches the `3.1` every deploy job pins, so the gate resolves the `Gemfile` under the Ruby that actually builds and signs releases.
  Keep it identical to the deploy pins.
  It runs on `ubuntu-latest`: the lockfile's `PLATFORMS` is generic `ruby` and nothing here touches a macOS-only toolchain, so keep any macOS-only step out of it rather than moving the job.
- `ios-verify` - gated on the iOS source/project paths plus `SharedTestVectors/**`, because the Swift halves of the cross-language parity suites read those vectors directly and would otherwise skip the PRs that break them.
  It runs `test` only (no build step) with `-scheme "AscendApp-Staging" -configuration Staging ENABLE_TESTABILITY=YES`. It provisions the simulator at runtime via `xcrun simctl` against the newest installed iOS runtime - downloading the runtime if the image ships none - then reuses a preferred iPhone model, falls back to any iPhone, and finally creates one, failing only when the runtime supports no iPhone device type. It does not pass `CODE_SIGNING_ALLOWED=NO`.
- `ios-verify-release` - the only job that compiles Release and the only place `CODE_SIGNING_ALLOWED=NO` appears, paired with `-scheme "AscendApp" -configuration Release -sdk iphoneos -destination "generic/platform=iOS"`. It exists so Release-only build errors surface on the PR instead of on the production deploy.
  It also carries the export-compliance gate: a separate `Verify Release bundle export compliance` step resolves `TARGET_BUILD_DIR`/`INFOPLIST_PATH` from `-showBuildSettings -json` and requires the **processed** bundle `Info.plist` to declare `ITSAppUsesNonExemptEncryption` as boolean `false` (`plutil -extract ... -expect bool`).
  Ascend uses only standard TLS and Apple-provided cryptography, so that declaration is what keeps App Store and TestFlight uploads out of Missing Compliance; a missing key - or a string-typed `false`, which App Store Connect does not reliably accept - parks the upload.
  Keep it a distinct step rather than a tail on the build: `Summarize failure` is gated on the `build` step's outcome, so folding the check into that step would hand the summarizer the log of a build that actually succeeded.
  `ProcessInfoPlistFile` runs independently of compilation, which is why the check reads the built bundle plist instead of `AscendApp/Info.plist`.

`.github/workflows/ci-required-check-fallback.yml` is the companion required-check router, and unlike `ci.yml` it is unfiltered: it runs on every PR targeting `develop` or `main`, whatever the changed paths.
Its `route` job lists the PR's changed files and hands them to `scripts/ci/classify-required-check-route.mjs`, which decides through `scripts/lib/required-check-routing.mjs`.
Its fallback matrix derives every required iOS context from the marked jobs in `ci.yml`, then claims those exact names only when the route job succeeded *and* returned `fallback_eligible=true`.
For anything else the fallback jobs take distinct `Fallback (Not Required)` display names and are skipped, so they can never satisfy branch protection in place of the real checks.

**The router is an allowlist, not the inverse of the CI trigger.** `classifyChangedPaths` answers "is every changed path positively known to need no verification?" - `VERIFICATION_IRRELEVANT_PATHS` is `docs/**`, `AppStoreAssets/**`, `data/ascend-support-page-and-product-page-package/**`, `.claude/skills/**`, `README.md`, and `.gitignore`, and CI-relevance is evaluated first so the four gated `docs/*.md` files still route to real CI.
Anything unrecognised is blocked, which is the deliberate fail-closed default.
Two root files look like trivia and are deliberately CI-relevant: `.ruby-version` selects the Ruby that resolves the `Gemfile`, and `AGENTS.md` is a git-mode-120000 symlink to `CLAUDE.md`.
The Ruby path runs `ruby-verify` - which resolves the bundle under the pinned deploy Ruby, not the value in `.ruby-version` - while the project-guide path runs the same `scripts` filter as `CLAUDE.md`.

Firebase rules, Firebase configuration, the root rules-test package, Ruby dependencies, and `fastlane/**` are all in the CI-relevant contract.
Do not add any of them to the fallback allowlist.
Their dedicated jobs are the verification that makes routing them to real CI safe.
`iOS Verify (Staging)` and `iOS Verify (Release)` are the names branch protection requires: `firebase-verify` and `ruby-verify` run and report, but they are advisory until someone adds their names to branch protection.

The contract lives once, in `CI_RELEVANT_PATHS`, and `scripts/test/ci-required-check-routing.test.mjs` asserts it byte-identical to the `required-check-paths` block in `ci.yml`.
That contract must stay a superset of every job-level `dorny/paths-filter` path in `ci.yml`; the test derives the filters itself and fails on any path a verify job gates on that the trigger omits - so adding a path to the `scripts` or `ios` filter without adding it to the contract is a build failure, not a silent coverage hole.
That is why `CLAUDE.md` and the four gated `docs/*.md` files appear in the trigger: the `scripts` filter already declares them, and `scripts/test/subscription-launch-offer.test.mjs` asserts against them.
They cost nothing on the iOS side - the `ios` filter excludes them, so `ios-verify` is skipped rather than built.

Two shapes the router deliberately avoids.
Do not replace it with an inverse `paths-ignore` trigger: GitHub runs `paths-ignore` workflows when any changed file is outside the ignored set, so a mixed code-and-docs PR would run both workflows.
Do not express the allowlist as `dorny/paths-filter` negation rules: dorny ORs its rules per file, so `!docs/**` reads as "any file that is not under docs", which inverts the decision instead of excluding anything.

`ios-verify` is the **only** job anywhere that compiles `AscendAppTests`. `ios-verify-release` builds the app target alone, and both deploy pipelines only build the IPA. So a test target that stops compiling shows up on exactly one check, and "Release passed" or "Deploy Staging on develop passed" is not evidence that the tree is healthy. That asymmetry is what made the 2026-07-20 `develop` breakage read as CI infrastructure flake.

Two PRs that are each green on their own base can still break `develop` together: #248 added a call site and #251 added a parameter to the callee, merging 13 seconds apart. Nothing in CI re-verifies the merged result, so the next PR to rebase inherits the break. When a job starts failing on several unrelated branches at once, suspect the shared base before suspecting the runner.

Both iOS jobs pipe `xcodebuild` through `tee`, then run `scripts/ci/summarize-xcodebuild-failure.sh` and upload `build-logs/` as an artifact. Only `ios-verify` passes `-resultBundlePath`, so only its artifact carries an `.xcresult` bundle alongside the raw log - `ios-verify-release` is a build with no test results to bundle.
Both steps carry the same guard: `always()` plus an `xcodebuild` step outcome that is not `success`, not `skipped`, and not empty.
`always()` is what covers a job killed by `timeout-minutes`, which reports `cancelled` rather than `failure` - the exact case the logs exist to explain.
The outcome checks keep green runs from paying the upload, and keep the summarizer from annotating a log that was never written when an earlier step (simulator provisioning) failed first. `xcodebuild` interleaves diagnostics with the build commands of every target still in flight, so a compiler error routinely lands ~900 lines before the end of a 16,000-line log; read from the tail, the job looks like it died mid-copy of an SPM dependency with no diagnostic at all. The summarizer re-emits compiler errors and test failures as annotations, prints a resource snapshot, and says so explicitly when there genuinely is no diagnostic. Run it locally against a log downloaded with `gh api .../logs` - it strips the API's timestamp prefix.

Every npm project is audit-gated at `--audit-level=low`, so any newly published advisory fails its verify job. In the jobs that install and prove code (`functions-verify`, `web-verify`) the audit runs last on purpose, so an advisory cannot hide the lint/test/build results that prove the code itself. Deliberate pins and overrides that keep those audits clean are documented in `docs/dependency-security.md`.

A trigger pointing at a branch that no longer exists silently disables the workflow rather than failing. When the branching model changes, change the trigger in the same PR.

`.github/workflows/deploy-staging.yml` runs on pushes to `develop` and on manual dispatch. Four jobs, and still **not** a sequential chain:
- `publish-kill-switches` - additively publishes any newly declared Remote Config kill switch to dev then staging, ahead of the archive that checks them. The dev step is `continue-on-error` on purpose; nothing archives against dev, so a dev-only failure must not hold the staging release train. See "Phased release and the remote kill switches" below.
- `build-ios` - Staging scheme, produces the IPA. `needs: publish-kill-switches`, so the archive preflight cannot read the backend before the publish it depends on.
- `deploy-firebase` - has **no `needs:`**, so it runs in parallel with `build-ios` and will deploy even if the app build fails. Steps 2-6 of the old "sequential" story are in fact one command: `--only functions,firestore:rules,firestore:indexes,storage,hosting`. The workflow comment frames this as tolerated, but it is a known CI safety gap tracked in issue #202 - treat it as a gap, not as settled design.
  It then runs `scripts/verify-deployed-functions.mjs` against `ascend-staging-fa7d5`, so a functions drift fails staging rather than waiting to be discovered in production.
- `upload-testflight` - the only gated job here: `needs: [build-ios, deploy-firebase]`. Last because it is hardest to reverse.

`develop` is what makes the staging trigger safe: staging cannot run on pushes to `main`, because `deploy-production.yml` already does and one push would deploy both. Keep the two deploy workflows on disjoint branches - pointing either at the other's branch reintroduces the double-deploy.

`.github/workflows/deploy-production.yml` runs on pushes to `main` and manual dispatch. It is **stricter** than staging, not a mirror of it: every deploy job is gated behind `PRODUCTION_READY=true`, the chain is strictly sequential so a failed build stops the deploy, and it ends with a `Deploy Status` job. The Firebase job is an ordered rollout rather than one combined deploy: indexes deploy and every declaration must report `READY`, then Functions deploy and the gate-critical exports must report `ACTIVE`, then Firestore rules, Storage rules, and Hosting deploy. The TestFlight upload still depends on the whole Firebase job, so the backend is ahead of the binary. `docs/production-backend-rollout-runbook.md` is the production operator contract and rollback guide.
- `production-gate` - reads `vars.PRODUCTION_READY`, publishes it as the `ready` output, and exits non-zero when it is not `true`. Every other job keys off that output, not off `vars` directly, so the gate's decision is visible in the run and testable in one place.
- `production-approval` - **the only job anywhere that may carry `environment: production`.** It does nothing but exist. See "One approval, or none" below; adding `environment:` to a second job reintroduces the outage.
- `build-ios` -> `deploy-firebase` -> `upload-testflight` - sequential, each `needs:` the approval.
- `deploy-firebase` runs two different function checks after the Functions deploy, and they answer different questions. `scripts/ci/assert-firebase-functions-active.mjs` takes a curated list of gate-critical exports and proves each is `ACTIVE`; the runbook drives it by hand during a manual rollout. `scripts/verify-deployed-functions.mjs` proves the project holds **exactly** what the checked-out `functions/src/index.ts` exports - missing, orphaned, and deployed-but-not-`ACTIVE` are all hard failures. A curated list cannot catch a function nobody thought to add to it, or one deleted from source but still serving; that is the gap the second check closes. It is ref-relative, so run it from the ref that project is supposed to be running.
- `deploy-status` - `if: always()`, calls `scripts/ci/assert-deploy-outcome.sh`. It converts a run that deployed **nothing** into a `failure`; it does not and cannot convert a `cancelled` run - see below. Covered by `scripts/test/assert-deploy-outcome.test.mjs`.

Both `build-ios` jobs run `scripts/ci/assert-monetization-keys-configured.mjs <Staging|Release>` before the archive: a placeholder RevenueCat or Superwall key, a Release build with the hard paywall bypassed, or a build pointed at either vendor test surface all build and upload cleanly, so the gate has to fire before Fastlane rather than after. `docs/superwall-paywall-setup.md` owns the per-environment key split and the build settings this gate pins; Staging and Release both carry real publishable client keys today, so neither is placeholder-blocked.

Both `build-ios` jobs then run `scripts/ci/assert-remote-config-published.mjs <staging|prod>`, which reads the live Remote Config template with `FIREBASE_TOKEN` and refuses the archive when a kill switch the binary reads is unreachable on that project's backend - missing, published as "use in-app default", carrying only conditional values, or not declared `BOOLEAN`. It reports on template *shape*, never on values, so a switch an operator has deliberately turned off never blocks a release; and it exits `2` rather than passing when it cannot reach the backend, because "could not look" reading as "looks fine" is exactly how #318 stayed invisible. `docs/remote-config-kill-switches.md` owns the rest.

`.github/workflows/deploy-production-watchdog.yml` runs on `workflow_run` completion of Deploy Production, on a 3-hourly cron, and on dispatch. It runs `scripts/check-deploy-production-health.mjs`, which opens/updates/closes a single marker-identified issue labelled `deploy-health` and exits non-zero when unhealthy. It is deliberately outside the pipeline it watches - see below.

`.github/workflows/remote-config-drift.yml` runs on a weekly cron and on `workflow_dispatch`, and is strictly read-only across dev, staging and production - see "Phased release and the remote kill switches" below, and `docs/remote-config-kill-switches.md` for what it reports.

## A cancelled run is silent - the 2026-07 production outage

Production ran the code from `6341ad6` for 13 days while eight consecutive `Deploy Production` runs concluded `cancelled`. Nobody knew, because **GitHub emails on `failure` and says nothing about `cancelled`.** The full chain, all of it reconstructible from the API:

1. The `production` environment carries a `required_reviewers` protection rule. **Each job with `environment:` opens its own deployment that starts in `waiting`** - approval is per job, not per run. Three protected jobs meant three separate approval clicks.
2. Run `29540507247` took two attempts, so it opened five deployments in all; three reached `queued` and were approved. The last one - `upload-testflight`, deployment `5481609169` - was created three minutes *after* the re-run Firebase deploy had already reported success, and sat in `waiting` from 2026-07-16T23:22:38Z until it errored on 2026-07-29T17:18:48Z. Check `GET /repos/:o/:r/deployments/:id/statuses` - a deployment that never leaves `waiting` was never approved; one that reached `queued` was.
3. A run with a job waiting for approval is still `in_progress`, so it held the `deploy-production` concurrency group. That group is deliberately fixed and non-ref-scoped (`ci-workflow-contracts.test.mjs` fails any group containing `${{ github.ref }}`), so *every* run serializes on it. `cancel-in-progress: false` is correct and must stay - it is what stops a second push aborting a Firebase deploy mid-flight - but it means a stalled run holds the group indefinitely.
4. **GitHub keeps at most one *pending* run per concurrency group and cancels the one a new run displaces.** Runs `29550242067`, `29571233623`, `29571478050`, `29571604789` and `29577969423` each have `total_count: 0` jobs - they never created a single job - and each one's `updated_at` equals the next run's `created_at` to within two seconds.
5. Nothing notified, and production silently kept missing `cleanupDeletedUserData`, `onWorkoutWritten` and `unsubscribeFromEmails`.

Four rules fall out of this, and each one is load-bearing:

- **One approval, or none.** Keep `environment: production` on `production-approval` alone. Approval is requested before any work starts, so it cannot arrive after the operator has stopped watching. The deploy jobs lose nothing by dropping the environment because it carries **zero environment-scoped secrets and zero environment-scoped variables** - `FIREBASE_TOKEN`, `PRODUCTION_READY` and `FIREBASE_PROJECT_ID_PRODUCTION` are all repository-scoped. That is the invariant this rests on: scope a new value to the `production` environment and it resolves empty in every job except the approval.
- **Nothing inside the pipeline can make a cancelled run notify. The watchdog is the only channel.** Two separate reasons, and both are measured rather than assumed. A run cancelled while still queued never creates a job, so no step - not even one guarded by `always()` - can run. And even when a job *does* run, cancellation outranks it: on throwaway run `30676439255` a two-job workflow was cancelled mid-flight, its `always()` status job ran and concluded `failure`, and the run still concluded `cancelled`, so no email fired. `deploy-status` does not rescue a cancelled run. `deploy-production-watchdog.yml` is the sole notification path for one.
- **`deploy-status` is for the silently *empty* run, not the cancelled one.** Its real job is turning a run that deployed nothing into a `failure` - above all a stage reporting `skipped` because an upstream job was skipped, which GitHub would otherwise roll up into a green run. That conversion does email.
- **A green deploy log is not evidence that a project is deployed.** `firebase deploy` reports on the work it was asked to do, never on the work a cancelled pipeline never asked for. Only the reconciliation step proves the project's state.

`always()` on a job (as on `deploy-status`, and on the xcodebuild summarizer steps) is what lets it run when upstream jobs did not succeed. Preserve it in both places.

The watchdog's drift check only alerts when the undeployed commits touch paths in `deploy-production.yml`'s own `on.push.paths` allowlist, which `scripts/lib/deploy-health.mjs` parses out of the workflow rather than duplicating. A docs-only or `.claude/**`-only commit never triggers a deploy, so treating it as drift would fire an unclearable alert every three hours. Edit the workflow's allowlist and the watchdog follows it; do not add a second copy of that list anywhere.

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
- Also required by both build jobs: `SENTRY_AUTH_TOKEN`, plus `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID` and `APP_STORE_CONNECT_API_KEY`.
  The build-number allocator reads App Store Connect before the archive, so those three credentials now reach the archive job as well as the upload job - widening their blast radius to every step that runs on the build runner.

### Build numbers (CFBundleVersion allocator)
- `BUILD_NUMBER` is derived by `scripts/ci/derive-build-number.sh <app-store-connect-app-id> <bundle-id>` in a pre-archive "Derive build number" step, not from `github.run_id` or `github.run_number`.
  The step assigns the result to a variable first so a non-zero exit propagates under `set -e` before anything is written to `$GITHUB_ENV`, and rejects an empty value explicitly - a zero-exit-no-output derivation would otherwise archive an empty `CFBundleVersion`.
  A failed derivation stops the deploy instead of exporting an empty build number.
- The value uses `YYYYMMDDNN`: the UTC date plus the next two-digit sequence for that app on that day.
  The allocator asks App Store Connect for every uploaded build on the configured app, validates that the app owns the expected bundle ID, and derives `01` or one more than today's highest suffix.
  An unreachable API, unexpected bundle, non-numeric historical build, future build, or exhausted `99` suffix fails closed.
- Staging app `6759919365` (`com.TylerPavay.AscendApp.staging`) and production app `6757202987` (`com.TylerPavay.AscendApp`) have independent App Store Connect build-number spaces.
  Their workflows deliberately can emit the same date sequence because the signed IPAs upload to separate apps.
  The workflow-level app ID and bundle ID are also passed explicitly to Fastlane so allocation and upload cannot silently target different apps.
- Uniqueness depends on each uploadable workflow declaring a **fixed, non-ref-scoped** per-app concurrency group (`deploy-staging`, `deploy-production`).
  Cancelled runs and reruns consume no sequence value because App Store Connect, not workflow history, owns the state.
  `scripts/test/ci-workflow-contracts.test.mjs` enforces the fixed groups, the distinct app mappings, and the post-upload wait below.
- **The concurrency group alone is not enough, and the reason is not obvious.** It serializes workflow *runs*, not Apple's ingestion.
  `upload_to_testflight` keeps `skip_waiting_for_build_processing: true`, so the lane returns when the transporter accepts the binary - minutes before the Build record is queryable through `/v1/builds`, which is the allocator's only sequence state.
  Left there, the next queued run would derive against the pre-upload maximum and mint the same `YYYYMMDDNN`, and Apple would reject it at the end of a full archive cycle.
  `scripts/ci/await-build-visible.mjs` closes that window: the upload job polls `/v1/builds` for the exact build it just uploaded and does not exit - does not release the group - until the record is listed.
  It waits for *visibility*, not for processing to finish, and fails loudly after a bounded 15 minutes rather than hanging or proceeding.
  The derived number reaches that job as the `build-ios` job output `build-number`; an empty one is a hard failure, not a skipped wait.
  Two properties of that poll are load-bearing and easy to regress: it mints a **fresh JWT per attempt**, because the token lifetime and the poll budget are both 900s and a once-minted token 401s exactly when a slow build finally appears; and it treats a per-attempt 429/5xx as **transient**, retrying for the remaining budget, because the binary is already accepted by the transporter and failing early only discards budget that might still have confirmed visibility.
  Credential loading and the app-to-bundle ownership check stay fatal - the latter is what proves the poll is watching the right app.
- The allocator refuses a number at or below the legacy cutover floor, at or below the highest uploaded build, or above the App Store's 32-bit ceiling.
  `YYYYMMDDNN` remains below the ceiling through 4294 and fails rather than wrapping after that.
- Legacy manual-signing CI secrets are deprecated:
  - `BUILD_CERTIFICATE_BASE64`
  - `BUILD_PROVISION_PROFILE_BASE64`
  - `P12_PASSWORD`
  - `KEYCHAIN_PASSWORD`
  - production-specific `*_PRODUCTION` variants of the above

## Phased release and the remote kill switches

An iOS binary cannot be rolled back, so a shipped release has exactly two undo levers. Full detail, including the fetch-failure posture and verified Remote Config pricing: `docs/remote-config-kill-switches.md`.

- **Remote Config kill switches** in front of every data-shape-touching path. Flipping one in the Firebase console reaches every install without a submission, including ones that already updated. Catalog: `AscendApp/Shared/Services/RemoteConfig/RemoteFeatureFlag.swift`; template: `remoteconfig.template.json`.
  - Publishing the template is a full replace, so **no workflow may full-replace it by any route** - not a `--only` list naming `remoteconfig`, not an unscoped `firebase deploy` (`firebase.json` wires the template in), and not `scripts/deploy-remote-config.mjs` or any npm alias that runs it. `scripts/test/remote-config-template.test.mjs` closes all three across every file in `.github/workflows/`. *Reading* the live template from CI is deliberately allowed - that is what the `build-ios` archive preflight does.
  - `scripts/deploy-remote-config.mjs` refuses to publish over a switch that is currently off unless you name it.
  - What CI *does* publish is `scripts/publish-new-kill-switches.mjs`, in `deploy-staging.yml`'s `publish-kill-switches` job, to **dev and staging only**. It builds its payload from the live template so it can only add a parameter the project has never held, refuses to write at all while any switch is off, and verifies afterwards that exactly one publish - its own - separates the version it read from the version now live. `scripts/test/remote-config-publish.test.mjs` pins that, and fails if any workflow aims it at production.
  - `build-ios` **needs** that job. Putting the publish in `deploy-firebase` would not work: in `deploy-staging.yml` that job runs in parallel with the archive, and in `deploy-production.yml` it runs after it.
  - `remote-config-drift.yml` reads all three projects weekly and on demand. Read-only, production included.
- **App Store phased release** - 1/2/5/10/20/50/100% over seven days. It does **not** apply to an app's first release, so 1.0 goes to everyone at once and only the kill switches cover launch day.
  - Arm and halt with `scripts/appstore-phased-release.mjs` (`status`, `enable`, `pause`, `resume`, `release-to-all`), using the same `APP_STORE_CONNECT_API_*` credentials as `upload_testflight`.
  - Pausing stops further users being moved onto a build; it does not remove it from anyone who already updated. For a data-corrupting bug, flip the kill switch first, then pause.

## CI Firebase plists

The Staging and Production plists are gitignored; the Dev plist is committed (see `AscendApp/App/Firebase/README.md`). CI decodes all three from base64 secrets into `AscendApp/App/Firebase/` before building:
`GOOGLE_SERVICE_INFO_DEV_BASE64`, `GOOGLE_SERVICE_INFO_STAGING_BASE64`, `GOOGLE_SERVICE_INFO_PRODUCTION_BASE64`.

## Related
- For archive/export/IPA automation, load `asc-xcode-build`.
- For App Store Connect release, metadata, submission, and TestFlight tasks, load `asc-release-flow`, `asc-metadata-sync`, `asc-submission-health`, `asc-testflight-orchestration`.
