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
  The job is gated on changes to `scripts/**` or `SharedTestVectors/**`, plus the iOS paths the monetization build-configuration suite reads directly, `AscendWatch/**` because the watch target-configuration suite reads that bundle's `Info.plist` directly alongside the project file - and, since the empty-icon-set defect, every `.appiconset` the project names in an `ASSETCATALOG_COMPILER_APPICON_NAME`, which puts the asset catalogs in both the `AscendApp/**` and `AscendWatch/**` trees under this filter - the Firebase configuration files the structural-validation suite reads directly, the web, legal, and guidance paths the subscription launch-offer suite reads directly, and `fastlane/**` because the exported-IPA suite asserts both signed lanes still publish their artifact by exact name.
  It also gates on the whole `AscendApp/**` tree, for the same reason `swiftdata_schema` does: the Mixpanel build-configuration suite scans every Swift file to prove `import Mixpanel` reaches only the telemetry adapter and that session replay stays off, and either mistake can be made in any file.
  The narrower app paths stay listed alongside it - each is some suite's declared input, and several are asserted by name.
  A suite here that asserts against tracked non-`scripts/` files must add its inputs to this filter, or the assertion silently stops running on the PRs that break it.
- `swiftdata-schema-verify` - runs `node scripts/check-swiftdata-schema.mjs` against the Swift sources, on its own `swiftdata_schema` filter of `AscendApp/**` and `AscendWatchShared/**` plus `SharedTestVectors/**`. Those are the whole app tree on purpose: an `@Model` can be declared anywhere, so the filter is never narrowed to the folders models live in today - and `AscendWatchShared/**` is there because that folder compiles into the app target too, so a model declared in it reaches the same store. The check walks the same two roots; keep the filter and the check's roots in step, or the gate reports on a subset of the schema while reading as though it covered all of it. `ascend-data-migration` owns what the check enforces.
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
- `ios-verify` - gated on the iOS source/project paths plus `SharedTestVectors/**`, because the Swift halves of the cross-language parity suites read those vectors directly and would otherwise skip the PRs that break them, and plus `scripts/ci/**` and `scripts/lib/**`, because the iOS jobs run those scripts and the modules they import - #570 changed how the suite is split across host processes, was routed as "not iOS", and the one job that could prove it was skipped.
  That coverage is derived, not restated: `scripts/test/ci-workflow-contracts.test.mjs` scans every `scripts/...` path the required-check iOS jobs reference and fails on any one of them the `ios` filter does not match, so adding a step that runs a script the filter does not cover re-opens the hole as a red test rather than as a silently skipped job.
  It runs `scripts/ci/run-ios-test-passes.sh <simulator-udid>` with `-scheme "AscendApp-Staging" -configuration Staging ENABLE_TESTABILITY=YES` plus `SWIFT_OPTIMIZATION_LEVEL=-Onone SWIFT_COMPILATION_MODE=singlefile DEBUG_INFORMATION_FORMAT=dwarf ONLY_ACTIVE_ARCH=YES`, which compiles once with `build-for-testing` and then runs the suite as one `test-without-building` pass per isolated group plus one for the complement (two today), each in a fresh host process.
  Those four overrides are command-line only: the project's Staging configuration stays `wholemodule` at `-O` for the archive `deploy-staging.yml` produces, and a test build compiled that way was 17.7 of the job's 40 minutes (job 100376172708, 2026-09-02).
  The passes are named in `scripts/ci/plan-test-passes.mjs`, never enumerated: `ISOLATED_PASSES` (the movie-export suite, which needs a host to itself) runs as an `-only-testing:` list, and the last pass is `-skip-testing:` of exactly the same names, so a new suite lands in it by construction. What enumeration used to catch - a name matching no real suite - is caught after each pass instead: the script reads every pass's `.xcresult`, fails a pass that executed nothing or that missed a suite it was told to run, and fails the job when the executed total is under `EXECUTED_TEST_FLOOR`. The `-enumerate-tests` run it replaced executed zero tests and cost 4.5 minutes, four of them the runner's cold simulator boot; that boot now starts at the end of `Select simulator` and the first pass waits on `simctl bootstatus -b`.
  A hung pass goes red, not cancelled: the `Run tests` step carries its own `timeout-minutes` below the job's, the script's silence watchdog (`scripts/ci/run-with-silence-watchdog.sh`) kills a pass in which no Swift Testing event lands for five minutes while its host is alive (bytes are not liveness: a wedged host still logs network noise) - printing `vm_stat` and the tests still in flight first - and every pass runs with `-test-timeouts-enabled YES` and a 600 s per-test allowance so one hung test fails with its name attached. That allowance kills and restarts the host, and tests in flight at the kill are recorded nowhere, so it sits far above any queue wait a hosted test can legitimately report (189 s on the green run) and the watchdog is the first responder.
  The app still compiles exactly once per job. See "What threatens `ios-verify`" below for why the suite is split at all.
  Its `Select simulator` step provisions the simulator at runtime via `xcrun simctl` against the newest installed iOS runtime - downloading the runtime if the image ships none - then reuses a preferred iPhone model, falls back to any iPhone, and finally creates one, failing only when the runtime supports no iPhone device type. It does not pass `CODE_SIGNING_ALLOWED=NO`.
  Both iOS jobs run `scripts/ci/ensure-watchos-runtime.sh` before `xcodebuild`, and so does each deploy pipeline's `build-ios` job before its Fastlane archive.
  Neither iOS job passes `-derivedDataPath`, and neither may gain one, even though `CLAUDE.md` now documents it for every local build.
  Both jobs - and each deploy pipeline's `build-ios` - restore an `actions/cache` keyed on `~/Library/Developer/Xcode/DerivedData/**/SourcePackages`, so relocating DerivedData moves `SourcePackages` out from under that path and silently re-resolves every Swift package on every run.
  The local flag exists only because a developer machine reuses one DerivedData store across throwaway worktrees; a runner is discarded whole, so the leak it prevents cannot happen here.
  The watch target remains a build dependency for 1.1 even though the 1.0 phone app does not embed its product, so a scheme that builds that target **may** still need the runtime - whether it does is unverified.
  The refusal that proved this was a hard precondition (`This scheme builds an embedded Apple Watch app`) keyed off the embed phase, and 1.0 embeds nothing, so no evidence in the repository says a dependency-only build still demands an installed runtime - issue #496 records that verification.
  Until it lands the step is **best effort** end to end: every inability - an uninstalled watchOS platform, a `simctl`/`jq` failure, a failed download, no matching runtime afterwards - warns and exits 0.
  There is exactly one authority on whether a build can proceed and it is `xcodebuild`, so a runtime that genuinely is required surfaces as Xcode's own accurate error rather than as a guess made minutes earlier, and a runtime that is not required never fails four jobs for a condition the build would tolerate.
  Do not re-tighten it into a hard failure, and do not read a green step as proof a runtime was installed.
  When Xcode does want a runtime it wants the one matching the **SDK**, not the deployment target and regardless of the destination.
  The runner image's runtime set changes without notice and the jobs pin `xcode-version: latest-stable`, so the required version moves whenever the runner's Xcode does.
  The step provisions rather than assuming, in the same defensive style as `Select simulator`.
  It matches on the SDK's `major.minor` against the parsed `simctl` runtime list; a differing patch still satisfies the scheme, a differing minor does not, and the plain listing also reports unavailable runtimes as though they were installed.
- `ios-verify-release` - the only job that compiles Release and the only place `CODE_SIGNING_ALLOWED=NO` appears, paired with `-scheme "AscendApp" -configuration Release -destination "generic/platform=iOS"`. It exists so Release-only build errors surface on the PR instead of on the production deploy.
  **It passes no `-sdk` flag, and must not regain one.**
  `-sdk <platform>` overrides `SDKROOT` for every target in the build, including the retained `AscendWatch` dependency.
  `SUPPORTED_PLATFORMS = "watchos watchsimulator"` on the watch target refuses that override and keeps the target on watchOS.
  `scripts/test/watch-target-configuration.test.mjs` holds the source-side platform contract while 1.0 does not embed a watch binary to inspect. It also asserts the phone target keeps its `PBXTargetDependency` on `AscendWatch`, which is now the only edge that compiles and signs the watch target at all; lose it and every watch check goes quiet while CI stays green.
  `scripts/ci/assert-embedded-watch-platform.sh` is the matching artifact-level guard - it runs `vtool` over an *embedded* watch binary. With 1.0 embedding none it has no caller anywhere and is deliberately parked for reactivation when 1.1 restores embedding; do not delete it as dead, and do not read its presence as a guard that runs today.
  `-destination "generic/platform=iOS"` already pins the platform correctly and is what produces a valid watch binary, so the flag bought nothing even before the watch target existed.
  A `Resolve the Release build product paths` step reads `TARGET_BUILD_DIR` with `WRAPPER_NAME` and `INFOPLIST_PATH` out of one `-showBuildSettings -json` invocation and publishes them as step outputs; every later check that reads the build product consumes those. Resolve once: that call re-evaluates the whole project graph, and three copies of the same `jq` program drift.
  It also carries the export-compliance gate: a separate `Verify Release bundle export compliance` step requires the **processed** bundle `Info.plist` to declare `ITSAppUsesNonExemptEncryption` as boolean `false` (`plutil -extract ... -expect bool`).
  Ascend uses only standard TLS and Apple-provided cryptography, so that declaration is what keeps App Store and TestFlight uploads out of Missing Compliance; a missing key - or a string-typed `false`, which App Store Connect does not reliably accept - parks the upload.
  Keep it a distinct step rather than a tail on the build: `Summarize failure` is gated on the `build` step's outcome, so folding the check into that step would hand the summarizer the log of a build that actually succeeded.
  `ProcessInfoPlistFile` runs independently of compilation, which is why the check reads the built bundle plist instead of `AscendApp/Info.plist`.
  A second step hands the same processed plist to `scripts/ci/assert-mixpanel-bundle.mjs Release`, which proves the Release artifact resolves the production Mixpanel destination without printing a token. Both `ios-verify` and this job also run `scripts/ci/assert-mixpanel-build-settings.mjs`, which is why they now pin `actions/setup-node`.
  It runs `scripts/ci/assert-app-icon-present.mjs` against the shipped phone bundle.
  An `AppIcon.appiconset` whose `Contents.json` declares a size slot with no `filename` compiles clean, ships no rendition, and emits no icon key at all, so the build reports `** BUILD SUCCEEDED **` and the first symptom is Apple's server-side upload validation one full deploy cycle later - that empty placeholder in `AscendWatch` rejected three staging IPAs on 2026-08-13 with `Missing Icons` and `Missing Info.plist value ... CFBundleIconName` (#494).
  The script reads the icon name back out of each shipped bundle's processed `Info.plist`, accepting it at the top level *or* nested under `CFBundleIcons/CFBundlePrimaryIcon` because Xcode writes it in different places for different target types and Apple accepts both, then requires a matching 1024x1024 rendition in the compiled `Assets.car`.
  It asserts that rendition is `Opaque`, because Apple rejects an icon carrying alpha and that rejection is indistinguishable from this one at a glance; appearance variants (`UIAppearanceDark`, `ISAppearanceTintable`) are exempt, since the system composites its own background behind them.
  `scripts/test/watch-target-configuration.test.mjs` holds the source-side half: every set an `ASSETCATALOG_COMPILER_APPICON_NAME` names must exist and name at least one image file.

`.github/workflows/ci-required-check-fallback.yml` is the companion required-check router, and unlike `ci.yml` it is unfiltered: it runs on every PR targeting `develop` or `main`, whatever the changed paths.
Its `route` job lists the PR's changed files and hands them to `scripts/ci/classify-required-check-route.mjs`, which decides through `scripts/lib/required-check-routing.mjs`.
Its fallback matrix derives every required iOS context from the marked jobs in `ci.yml`, then claims those exact names only when the route job succeeded *and* returned `fallback_eligible=true`.
For anything else every matrix leg falls back to the one static `iOS Verify Fallback (Not Required)` name and is skipped, so none of them can ever satisfy branch protection in place of the real checks.
The derivation is positional: `scripts/ci/list-required-check-contexts.mjs` reads the `name:` of every job between the `# required-check-contexts:start` and `# required-check-contexts:end` comments in `ci.yml`.
A required iOS verify job declared outside that block is invisible to the matrix, so branch protection would demand a context the eligible fallback never publishes - which is the original defect.
`scripts/test/ci-workflow-contracts.test.mjs` fails on either mistake: an `iOS Verify` job outside the block, or a non-verify job inside it.

**The router is an allowlist, not the inverse of the CI trigger.** `classifyChangedPaths` answers "is every changed path positively known to need no verification?" - `VERIFICATION_IRRELEVANT_PATHS` is `docs/**`, `AppStoreAssets/**`, `data/ascend-support-page-and-product-page-package/**`, `README.md`, and `.gitignore`, and CI-relevance is evaluated first so the four gated `docs/*.md` files still route to real CI.
Anything unrecognised is blocked, which is the deliberate fail-closed default.
Two root files look like trivia and are deliberately CI-relevant: `.ruby-version` selects the Ruby that resolves the `Gemfile`, and `AGENTS.md` is a git-mode-120000 symlink to `CLAUDE.md`.
The Ruby path runs `ruby-verify` - which resolves the bundle under the pinned deploy Ruby, not the value in `.ruby-version` - while the project-guide path runs the same `scripts` filter as `CLAUDE.md`.
`.claude/skills/**` is deliberately CI-relevant on those same terms and through that same `scripts` filter, so a skills-only PR triggers `ci.yml` and runs `scripts-verify` rather than auto-greening through the fallback.
It earns that because `scripts/test/derived-data-path-contract.test.mjs` fails when a copyable `xcodebuild` command drops `-derivedDataPath`, which makes those files a verified input rather than prose.
That test discovers those commands by enumerating tracked Markdown and then filtering to the paths `CI_RELEVANT_PATHS` marks as CI-relevant, importing that list from the router rather than restating it.
Its scope is therefore exactly the set of files that can trigger it, and promoting a new path to CI-relevant widens the guard with no edit to the test: a file the guard cannot be triggered by must never be claimed as guarded, because the failure would land on an unrelated pull request.
`CLAUDE.md`, `AGENTS.md` and `.claude/skills/**` are where every copyable `xcodebuild` command lives today, and an `xcodebuild` command added under still-allowlisted `docs/**` is deliberately outside the guard.

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

`ios-verify` is the **only** job anywhere that compiles `AscendAppTests`. `ios-verify-release` builds the shipping app, the widget extension embedded in it, and the retained `AscendWatch` dependency no IPA before 1.1 embeds - but no test target, and both deploy pipelines only build the IPA. So a test target that stops compiling shows up on exactly one check, and "Release passed" or "Deploy Staging on develop passed" is not evidence that the tree is healthy. That asymmetry is what made the 2026-07-20 `develop` breakage read as CI infrastructure flake.

**What threatens `ios-verify` is memory, not minutes, and the cap is a symptom rather than the constraint.**
`scripts/ci/run-ios-test-passes.sh` owns the measurements. The whole suite in one host process peaked at 4,228 MB RSS against a `macos-15` runner holding ~7 GB with ~2.4 GB already wired, reached the tail of the run with 65-83 MB free and ~2.7 GB compressed, and stopped completing tests entirely; the job then died on its cap and reported `cancelled`.
**Memory here is concentrated in a few tests, not spread across many**, and that is the fact to act on.
One benchmark, `addTimeLayoutScalesLinearlyAsHeaviestClustersPileUp`, ran 108 `ImageRenderer` passes and peaked at 2,008 MB by itself against 630 MB for a sibling; deleting it took its suite from 2,311 MB to 1,026 MB and the whole suite from 4,228 MB to 3,122 MB, and turned the first pass green after four straight failures.
One suite genuinely needs the memory and keeps it: `ShareComposerBackgroundFillEvidenceTests` peaks at 2,205 MB across five tests, three of which each cost ~1.1 GB above baseline because each exports a real movie through the app's AVFoundation pipeline at the 1080x2340 story frame. That cost *is* the assertion - the fixture is already 12 frames at 12fps and a smaller export would delete what is checked - so the suite is named in `ISOLATED_PASSES` in `scripts/ci/plan-test-passes.mjs` and gets a host process to itself. That list is fail-loud on purpose: a name matching no real suite fails its pass from the `.xcresult` rather than quietly sending the suite back into a shared host that exhausts the runner.
The screen-render evidence suites were the other shape until 2026-09-03: each held 896-1,434 MB and kept it, because a rendered 3x screen was retained for the life of the host, so a balanced pass that held enough of them died at its tail - pass 2 completed 928 of 997 tests in four minutes, then went silent for 27 minutes with 13 render suites in flight and 67 MB free. Twenty of them briefly shared a serial isolated host of their own; `RenderedScreen` (below) is what retired that group.
So measure the suites before reaching for the runner. Splitting four ways measured a *higher* peak than two (2,881 MB against 2,020 MB) because balancing by test count collects the heavy suites into one pass; isolating one five-test suite costs ~90 seconds where a general three-way split costs every run ~4 minutes; and neither a higher pass count nor a longer cap is a memory fix - a killed run reached 1,814 completions in 6m44s where a green run took 8m30s for 1,846.
The job runs the suite as one `test-without-building` pass per isolated group and one for everything not named, all off one build - two passes today, and each pass beyond that costs ~2 minutes of host launch, so a third one is a measurement to justify, never a default.
Read a failure by its signature, not its colour: a job-level `timeout-minutes` kill reports as `cancelled`, while the step-level cap and the script's silence watchdog report `failure` and name the tests still in flight; an exhausted host reports "Test crashed with signal trap" for every test queued on the hosted-window gate at once, and its crash report says `EXC_BREAKPOINT` with `ktriageinfo` reading "mach_vm_allocate_kernel failed within call to vm_map_enter" - an allocation failure, so it lands on a different test each run and names none of them.
The script collects that crash report and prints free/compressor counts either side of each pass; both exist because three earlier theories (hosted-test runtime, a stale branch, build residue held into the first pass) each survived only until something measured them.
A `.hostsAWindow` test's reported duration is likewise mostly queue time on the single shared gate rather than render cost - ~47 suites serialize on it, so "passed after 282 seconds" is not 282 seconds of work.
Budget hosted coverage per suite anyway and prefer a non-hosting suite where a live screen is not genuinely needed: the gate serializes them, so they set the length of the run's tail.
**The render suites read screens through `AscendAppTests/RenderedScreen.swift`, and that is what made the remainder fit one host (2026-09-03).**
Before it, every evidence file hosted a screen in its own `UIWindow`, captured it with `drawHierarchy` at scale 3 (12 MB a bitmap), PNG-encoded it and OCR'd the bitmap with Vision to prove copy was on screen, holding the image for the length of the test: 14 suites peaked at 1,000-2,355 MB alone and 52 more at 545-996 MB.
The helper reads copy presence and absence off the accessibility tree - and only copy that is actually painted, so a label pushed off screen, hidden, clipped or mid-animation is not there - reads pixels at 1x inside a closure that releases them, keeps OCR only for legibility contracts, and writes the 3x photograph only when `ASCEND_EVIDENCE_DIR` is set, which CI never does.
Measured with the same 10 Hz `ps -o rss` sampler on the same machine, isolated per suite: every OCR suite dropped 25-55% (`EmailPreferencesScreenSnapshotTests` 1,412 -> 831 MB, `AppAccessPaywallPlaceholderSnapshotTests` 1,357 -> 715 MB now that it hosts every gate phase on both the compact and the accessibility-text-size surface on CI, 613 MB while it hosted one; `LeaderboardWindowLabelEvidenceTests` 611 -> 656 MB hosting the shipping board on CI, 551 MB while it hosted nothing), and the untouched `SentryMaskingEvidenceTests` mask proof stayed at ~1,100 MB.
The whole remainder in one serial host - every suite but `ShareComposerBackgroundFillEvidenceTests`, 1,995 tests, all passed - took 291 s and peaked at 2,041 MB on 2026-09-04 at 9d2cbcb5, against 2,929 MB before the helper in a run that had never finished; the earlier 2,090 MB parallel and 1,708-2,109 MB serial peaks were measured on 2026-09-03 before those nine hosts were restored.
Two hazards that run exposed are not memory: a wheel `DatePicker` walked with the accessibility runtime on materialises every drum row (634 -> 2,560 MB on one screen, so the shared walker stops at `UIPickerView`/`UIDatePicker`), and a hosted screen carrying a `@Query` keeps observing SwiftData after its window is gone, so a container that died with its test leaves that observer to trap on the next `ModelContext.save()` from any suite - `EXC_BREAKPOINT` on the main thread charged to whoever was saving, and when Xcode's crash interception parks the trapped host instead of letting it die, the silent-hang signature. Every container a hosted screen reads therefore comes from `AscendAppTests/RetainedModelContainer.swift` and lives for the process; `-test-timeouts-enabled` is what turns a hang that still slips through into a named failure instead of a cancelled job.

Two PRs that are each green on their own base can still break `develop` together: #248 added a call site and #251 added a parameter to the callee, merging 13 seconds apart. Nothing in CI re-verifies the merged result, so the next PR to rebase inherits the break. When a job starts failing on several unrelated branches at once, suspect the shared base before suspecting the runner.

Both iOS jobs pipe `xcodebuild` through `tee`, then run `scripts/ci/summarize-xcodebuild-failure.sh` and upload `build-logs/` as an artifact. Only `ios-verify` passes `-resultBundlePath`, so only its artifact carries `.xcresult` bundles alongside the raw log - one per test pass, because `xcodebuild` refuses to write over an existing bundle. `ios-verify-release` is a build with no test results to bundle.
Both steps carry the same guard: `always()` plus an `xcodebuild` step outcome that is not `success`, not `skipped`, and not empty.
`always()` is what covers a job killed by the job-level `timeout-minutes`, which reports `cancelled` rather than `failure` - the exact case the logs exist to explain. The `xcodebuild` steps in both iOS jobs also carry their own `timeout-minutes` below the job's, because a step killed by its own cap fails and the job concludes `failure`; keep the step cap under the job cap or the job-level kill wins and the run is `cancelled` again.
The outcome checks keep green runs from paying the upload, and keep the summarizer from annotating a log that was never written when an earlier step (simulator provisioning) failed first. `xcodebuild` interleaves diagnostics with the build commands of every target still in flight, so a compiler error routinely lands ~900 lines before the end of a 16,000-line log; read from the tail, the job looks like it died mid-copy of an SPM dependency with no diagnostic at all. The summarizer re-emits compiler errors and test failures as annotations, prints a resource snapshot, and says so explicitly when there genuinely is no diagnostic. Run it locally against a log downloaded with `gh api .../logs` - it strips the API's timestamp prefix.

Every npm project is audit-gated at `--audit-level=low`, so any newly published advisory fails its verify job. In the jobs that install and prove code (`functions-verify`, `web-verify`) the audit runs last on purpose, so an advisory cannot hide the lint/test/build results that prove the code itself. Deliberate pins and overrides that keep those audits clean are documented in `docs/dependency-security.md`.

A trigger pointing at a branch that no longer exists silently disables the workflow rather than failing. When the branching model changes, change the trigger in the same PR.

`.github/workflows/deploy-staging.yml` runs on pushes to `develop` and on manual dispatch. Four jobs, and still **not** a sequential chain:
- `publish-kill-switches` - additively publishes any newly declared *automatically published* Remote Config parameter, kill switch or operator setting, to dev then staging, ahead of the archive that checks them. The captain-only version thresholds are excluded from its plan entirely, so a merge to `develop` never puts them into any project while the archive preflight still demands them - `docs/remote-config-kill-switches.md` owns that split. The dev step is `continue-on-error` on purpose; nothing archives against dev, so a dev-only failure must not hold the staging release train. See "Phased release and the remote kill switches" below.
- `build-ios` - Staging scheme, produces the IPA. `needs: publish-kill-switches`, so the archive preflight cannot read the backend before the publish it depends on.
- `deploy-firebase` - has **no `needs:`**, so it runs in parallel with `build-ios` and will deploy even if the app build fails. The workflow comment frames that parallelism as tolerated, but it is a known CI safety gap tracked in issue #202 - treat it as a gap, not as settled design.
  The Firebase deploy itself is not one combined command; it is the same ordered rollout production runs - indexes, then the `wait-for-firestore-indexes.mjs` gate, then Functions, then Firestore rules, then Storage rules, then Hosting. **Rules deploy last on purpose.** They require a server-owned paid-access grant that only the entitlement Functions and their expiry index can produce, so a missing RevenueCat secret must stop the job before rules land rather than lock every subscriber out of the backend (`docs/revenuecat-server-entitlement-enforcement.md`).
  Between Functions and rules it runs `scripts/verify-deployed-functions.mjs` against `ascend-staging-fa7d5`, so a functions drift fails staging rather than waiting to be discovered in production.
- `upload-testflight` - the only gated job here: `needs: [build-ios, deploy-firebase]`. Last because it is hardest to reverse.

`develop` is what makes the staging trigger safe: staging cannot run on pushes to `main`, because `deploy-production.yml` already does and one push would deploy both. Keep the two deploy workflows on disjoint branches - pointing either at the other's branch reintroduces the double-deploy.

`.github/workflows/deploy-production.yml` runs on pushes to `main` and manual dispatch. It is **stricter** than staging, not a mirror of it: every deploy job is gated behind `PRODUCTION_READY=true`, the chain is strictly sequential so a failed build stops the deploy, and it ends with a `Deploy Status` job. The Firebase job is an ordered rollout rather than one combined deploy: indexes deploy and every declaration must report `READY`, then Functions deploy and the gate-critical exports must report `ACTIVE`, then Firestore rules, Storage rules, and Hosting deploy. The TestFlight upload still depends on the whole Firebase job, so the backend is ahead of the binary. `docs/production-backend-rollout-runbook.md` is the production operator contract and rollback guide.
- `production-gate` - reads `vars.PRODUCTION_READY`, publishes it as the `ready` output, and exits non-zero when it is not `true`. Every other job keys off that output, not off `vars` directly, so the gate's decision is visible in the run and testable in one place.
- `production-approval` - **the only job anywhere that may carry `environment: production`.** It does nothing but exist. See "One approval, or none" below; adding `environment:` to a second job reintroduces the outage.
- `build-ios` -> `deploy-firebase` -> `upload-testflight` - sequential, each `needs:` the approval.
- `deploy-firebase` runs two different function checks after the Functions deploy, and they answer different questions. `scripts/ci/assert-firebase-functions-active.mjs` takes a curated list of gate-critical exports and proves each is `ACTIVE`; the runbook drives it by hand during a manual rollout. `scripts/verify-deployed-functions.mjs` proves the project holds **exactly** what the checked-out `functions/src/index.ts` exports - missing, orphaned, and deployed-but-not-`ACTIVE` are all hard failures. A curated list cannot catch a function nobody thought to add to it, or one deleted from source but still serving; that is the gap the second check closes. It is ref-relative, so run it from the ref that project is supposed to be running. Only the reconciliation is strict; the `functions:list` read in front of it is retried three times across ~20s with a two-minute timeout on each attempt, because a read that could not run is not evidence the deploy was wrong - one refusal seconds after a clean 22-function staging deploy failed the job and skipped the TestFlight upload that `needs:` it. The budget buys tolerance for the Cloud Functions API and none for the deploy: a read that returns a payload is reconciled exactly as before, an exhausted budget still fails the job, and a failure quotes the CLI's own words because `--json` writes its error envelope to stdout and leaves stderr empty. `scripts/test/deploy-health.test.mjs` pins both halves.
- The Firestore index gate reads current composite and field-override serving states through the authenticated client in `scripts/ci/wait-for-firestore-indexes.mjs`. Do not use `firebase firestore:operations:list --token` for this gate while CLI 15.22.1 is pinned: that command omits the authentication hook, ignores `--token` on a clean runner, and can spend the whole timeout retrying a poll that never reached Firestore. A timeout must retain the last exact index signatures and states. It takes a literal project ID, so `vars.FIREBASE_PROJECT_ID_PRODUCTION` must hold one: a `.firebaserc` alias is refused before any Firestore call rather than resolved, because a stale mapping would verify the wrong project.
- `deploy-status` - `if: always()`, calls `scripts/ci/assert-deploy-outcome.sh`. It converts a run that deployed **nothing** into a `failure`; it does not and cannot convert a `cancelled` run - see below. Covered by `scripts/test/assert-deploy-outcome.test.mjs`.

Both `build-ios` jobs run `scripts/ci/assert-monetization-keys-configured.mjs <Staging|Release>` before the archive: a placeholder RevenueCat or Superwall key, a Release build with the hard paywall bypassed, or a build pointed at either vendor test surface all build and upload cleanly, so the gate has to fire before Fastlane rather than after. `docs/superwall-paywall-setup.md` owns the per-environment key split and the build settings this gate pins; Staging and Release both carry real publishable client keys today, so neither is placeholder-blocked.

Both `build-ios` jobs then run `scripts/ci/assert-remote-config-published.mjs <staging|prod>`, which reads the live Remote Config template with `FIREBASE_TOKEN` and refuses the archive when a Remote Config parameter the binary reads - every catalog enum, listed once in `APP_PARAMETER_SOURCE_PATHS` so no caller has to remember them - is unreachable on that project's backend: missing, published as "use in-app default", carrying only conditional values, or not declared at the type the template gives it (`BOOLEAN` for a switch, its own for a setting). It reports on template *shape*, never on values, so a switch an operator has deliberately turned off never blocks a release; and it exits `2` rather than passing when it cannot reach the backend, because "could not look" reading as "looks fine" is exactly how #318 stayed invisible. `docs/remote-config-kill-switches.md` owns the rest.

Both `build-ios` jobs also run `scripts/ci/assert-mixpanel-build-settings.mjs` before the archive and `scripts/ci/assert-mixpanel-bundle.mjs <Staging|Release> <ipa>` after it, so a build that would report analytics into another environment's Mixpanel project fails before the upload rather than after ingest. Neither script prints a token. `.claude/skills/ascend-analytics/SKILL.md` owns the per-environment destinations and what the app does with them.

Both `build-ios` jobs then run `scripts/ci/assert-app-icon-present.mjs <ipa>` after the archive, in addition to the `ios-verify-release` run described above.
The IPA is the artifact Apple's upload validation actually rejects, and it is the only place the per-configuration phone icon sets (`AppIconDev`, `AppIconStaging`) are resolved at all - the Release compile check only ever resolves `AppIcon`.
Given an IPA the script always checks the installable phone app and checks a watch app nested under `Payload/<app>.app/Watch/` when one is present.
It selects each `Info.plist` exactly rather than by wildcard for the reason in the Fastlane section.
An IPA carrying **no** watch app passes, with a `::warning::` annotation on the run summary: this guard's job is that the icon Apple rejects is present, not that the watch app ships.
The watch app ships in 1.1 and every release before it is submitted without it, a decision owned by `docs/heart-rate-zones-plan.md`, so zero embedded watch bundles is the **normal** case for every build before 1.1 rather than an edge case or an act of leniency - do not tighten this branch into a hard requirement, which would fail the deploy after the archive is already built.
More than one nested watch bundle stays fatal, because that is a defect however the scope question lands.

`.github/workflows/deploy-production-watchdog.yml` runs on `workflow_run` completion of Deploy Production, on a 3-hourly cron, and on dispatch. It runs `scripts/check-deploy-production-health.mjs`, which opens/updates/closes a single marker-identified issue labelled `deploy-health` and exits non-zero when unhealthy. It is deliberately outside the pipeline it watches - see below.

`.github/workflows/prepare-app-store-version.yml` runs on `workflow_run` completion of Deploy Production - only when it concluded `success` - and on dispatch with optional `version` and `build` inputs. It runs `scripts/appstore-prepare-version.mjs`, which waits for Apple to finish processing the build, creates the App Store version record for the archived `MARKETING_VERSION` (with `releaseType: MANUAL`), attaches the build, and stops. It is a separate workflow rather than a final job in `deploy-production.yml` because build processing outlasts the upload by far, and waiting inside the `deploy-production` concurrency group would displace a queued production deploy - the exact silent cancellation the watchdog exists to catch.
**Nothing in this repository submits for review, releases automatically, or steers a phased rollout unattended, and nothing may be extended to.** The captain presses Submit himself. `scripts/test/app-store-submission-guard.test.mjs` fails the build if any workflow, Fastlane lane, or pipeline script gains that power. Procedure, including the closed-version-train trap: `docs/release-procedure.md`.

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
- The automation past TestFlight is **not** a Fastlane lane. `deliver` / `upload_to_app_store` is one boolean (`submit_for_review`) away from crossing the boundary above, and every other App Store Connect read in this repository already goes through `scripts/lib/app-store-connect-client.mjs`. Version-record preparation follows that convention: `scripts/appstore-prepare-version.mjs`.
- iOS deploy lanes use `fastlane match` for signing material sync (CI runs in `readonly` mode).
- The retained watch target is built and signed as a dependency for 1.1, but no phone app before 1.1 embeds its product.
  Its identifier reaches `match_options_for`, `AscendWatch` is listed in `update_code_signing_settings`, and the export plist's `provisioningProfiles` map keeps the 1.1 signing configuration ready.
  `AscendWatch` pins `PROVISIONING_PROFILE_SPECIFIER[sdk=watchos*]` to `match AppStore com.TylerPavay.AscendApp.staging.watch` (Staging) and `match AppStore com.TylerPavay.AscendApp.watch` (Release); both profiles exist in the signing repository.
  `docs/heart-rate-zones-plan.md` owns the release split.
  The conditional is `[sdk=watchos*]` on purpose - the widget's `[sdk=iphoneos*]` copied verbatim leaves the watch target unsigned in the archive.
  The Debug identifier `com.TylerPavay.AscendApp.dev.watch` is deliberately not registered by hand; Debug signs automatically and Xcode creates it on the first device build.
- **Neither lane may identify an artifact by wildcard - not the exported IPA, not the app bundle inside it.**
  `-exportArchive` names the IPA after the scheme, so a first-match glob over the output directory can rename a *previous* run's IPA onto the published name and hand every downstream check a stale build.
  Both lanes therefore export into `build/export`, emptied first, and publish through `scripts/ci/publish-exported-ipa.mjs`, which moves the single candidate to `build/AscendApp-{Staging,Production}.ipa` and fails loudly on none or on more than one.
  Inside the IPA the same rule applies for the same reason: a nested watch bundle carries its own `Info.plist`, so `assert-mixpanel-bundle.mjs` and `verify-ipa-build-number.sh` each select `Payload/<app>.app/Info.plist` exactly and refuse anything but one match, rather than reading the first `Payload/*.app/Info.plist` - that wildcard is what broke the Mixpanel check the day the watch app was embedded.
  No IPA before 1.1 nests anything, so the wildcard would read correctly today and go on doing so until the 1.1 build that re-embeds; the exact selection stays.
  `scripts/lib/exported-ipa.mjs`, `scripts/lib/ipa-bundle.mjs`, and `scripts/test/exported-ipa-publication.test.mjs` hold the contract.
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
- After Fastlane exports the signed IPA, `scripts/ci/verify-ipa-build-number.sh` reads its main app `CFBundleVersion` and proves it matches the allocator.
  The build job publishes that verified artifact value as its job output, and the upload job verifies the downloaded IPA against the same output before contacting TestFlight.
  Missing and mismatched handoffs therefore fail before upload with distinct `BUILD_NUMBER_HANDOFF_*` diagnostics.
- The value uses `YYYYMMDDNN`: the UTC date plus the next two-digit sequence for that app on that day.
  The allocator asks App Store Connect for every processed build and non-failed upload reservation on the configured app, validates that the app owns the expected bundle ID, and derives `01` or one more than today's highest suffix.
  An unreachable API, unexpected bundle, non-numeric historical build, future build, or exhausted `99` suffix fails closed.
- Staging app `6759919365` (`com.TylerPavay.AscendApp.staging`) and production app `6757202987` (`com.TylerPavay.AscendApp`) have independent App Store Connect build-number spaces.
  Their workflows deliberately can emit the same date sequence because the signed IPAs upload to separate apps.
  The workflow-level app ID and bundle ID are also passed explicitly to Fastlane so allocation and upload cannot silently target different apps.
- Uniqueness depends on each uploadable workflow declaring a **fixed, non-ref-scoped** per-app concurrency group (`deploy-staging`, `deploy-production`).
  Runs cancelled before Apple creates an upload reservation consume no sequence value.
  Once Apple creates a non-failed reservation, that number remains consumed even if the workflow is later cancelled, because App Store Connect rather than workflow history owns the state.
  `scripts/test/ci-workflow-contracts.test.mjs` enforces the fixed groups, the distinct app mappings, and the post-upload wait below.
- **The concurrency group alone is not enough, and the reason is not obvious.** It serializes workflow *runs*, not Apple's ingestion.
  `upload_to_testflight` keeps `skip_waiting_for_build_processing: true`, so the lane returns when Transporter accepts the binary, before the processed Build is queryable through `/v1/builds`.
  The allocator therefore reads both processed Builds and the earlier `/v1/apps/{id}/buildUploads` ledger.
  Every upload state except `FAILED` reserves its build number; Apple explicitly permits reusing the number of a failed upload.
  `scripts/ci/await-build-upload-recorded.mjs` holds the group until the exact upload is `PROCESSING` or `COMPLETE`, which is sufficient for the next allocator without blocking on build processing.
  Its 900-second budget covers upload-ledger visibility and transient API failures, not processing.
  The 20 staging uploads inspected when this gate was introduced took at most 86 seconds from upload-record creation to `uploadedDate`, and the motivating upload record existed before the old post-upload waiter began.
  A `FAILED` upload, an absent upload record, and a credential or app-ownership failure have distinct diagnostics.
  The poll mints a fresh JWT per attempt and treats per-attempt 429/5xx responses as transient while the budget remains.
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

- **Remote Config kill switches** in front of every data-shape-touching path. Flipping one in the Firebase console reaches every install without a submission, including ones that already updated. Catalog: `AscendApp/Shared/Services/RemoteConfig/RemoteFeatureFlag.swift`, plus the operator settings in `RemoteConfigSetting.swift` and the captain-only version thresholds in `RemoteAppVersionParameter.swift` - values rather than switches, preflighted identically, but the thresholds are published by hand only; template: `remoteconfig.template.json`.
  - Publishing the template is a full replace, so **no workflow may full-replace it by any route** - not a `--only` list naming `remoteconfig`, not an unscoped `firebase deploy` (`firebase.json` wires the template in), and not `scripts/deploy-remote-config.mjs` or any npm alias that runs it. `scripts/test/remote-config-template.test.mjs` closes all three across every file in `.github/workflows/`. *Reading* the live template from CI is deliberately allowed - that is what the `build-ios` archive preflight does.
  - `scripts/deploy-remote-config.mjs` refuses to publish over any lever in use - a switch currently off, or a setting moved away from its checked-in baseline, which is how an armed version threshold and a bumped `workout_sync_recovery_epoch` are caught - unless you name each one.
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
- For the end-to-end release procedure - version trains, what is automatic, and what stays the captain's - read `docs/release-procedure.md`.
- For App Store Connect release, metadata, submission, and TestFlight tasks, load `asc-release-flow`, `asc-metadata-sync`, `asc-submission-health`, `asc-testflight-orchestration`.
