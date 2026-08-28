# Ascend - Project Guide

This file is the always-on core. Domain detail lives in `.claude/skills/` - see the Skill Router below.

## What Is Ascend

Ascend is a **stair stepper racing app** for iOS, shipping as `Ascend: Stair Stepper Racing`. Racing is the product; measuring the session is a byproduct. The market framing, settled by the captain on 2026-08-08: tower running is already an organised sport, and entering one takes a skyscraper, an event date, a travel budget, and a place in a limited field - **Ascend is that sport, on a machine, on any day, from any gym.** Users race real towers, top per-climb leaderboards, claim First Ascents, and watch their progress compound. The leaderboard is the conversation. Outward copy derived from this: `docs/app-store-racing-repositioning-proposal.md`.

**Solo dev + AI assisted** (Tyler Pavay). Launch monetization is a hard paywall with no freemium tier: `$49.99/year` with a seven-day free trial, or `$9.99/month` charged immediately with no trial. Both unlock RevenueCat entitlement `app_access`; there is no weekly or separate launch-discount product. The paywall is a server-enforced lock, not just a screen: Firebase requires a server-owned grant projected from RevenueCat (`docs/revenuecat-server-entitlement-enforcement.md`).

## What Ascend Is NOT

The niche defined by exclusion. Check every feature, screen, and copy change against it:

- Not for users who don't care about the stair stepper.
- Not a social fitness network - no feed, no followers, no kudos. Interaction happens *on the climb*.
- Not a generic fitness tracker. Activity scope is stair stepper sessions.
- Not weight-lifting / strength-training focused.
- Not a passive tracker. Every session is competitive context.
- Not a logger or an importer. Every climb and record comes from a session performed in Ascend; manual entry and Apple Health workout import were removed on 2026-08-08 (#437).
  Apple Health stays only to enrich an Ascend-owned climb, and the read set is exactly two types: `heartRate` and `activeEnergyBurned`, read over that climb's own time window and attached to it.
  Ascend never requests `workoutType()`, never reads outside a climb's window, and never writes to Apple Health.
  Quote that set when writing any disclosure - the legal pages, the `Info.plist` usage string, and the App Store answers all have to agree, and `HealthKitAuthorizationClient.readTypes` is the authority.
  No outward surface may promise otherwise. Outward copy: `docs/app-store-racing-repositioning-proposal.md`.

Full rationale: `ascend-brand-voice`.

## Brand Voice

Niche-aggressive and declarative. The user already chose to be here; the copy doesn't beg.

- **Active verbs at the front.** *Climb. Race. Rank. Push.* Never "explore" / "discover" as openers.
- **Imperative over invitational.** *Be the first* beats *You could be the first*.
- **No hedging.** Cut "maybe," "perhaps," "feel free to."
- **Specific over abstract.** Name landmarks, verbs, and earned numbers.
- **The dare beats the invite.** Empty states use state-then-action: state the condition, then command.

Full playbook: `ascend-brand-voice`. Design patterns: `product-design-playbook`.

## Tech Stack

- **iOS 26.0+**, Swift 6, SwiftUI
- **Data**: Local-first with cloud sync - SwiftData on device, Firebase Firestore for backup/sync/sharing
- **Backend**: Firebase (Auth, Firestore, Storage, Cloud Functions, Hosting, Analytics, Crashlytics, Remote Config)
- **Subscriptions / Paywall**: RevenueCat for subscription management and entitlements; SuperWall for paywall presentation and onboarding/conversion analytics
- **Analytics / Diagnostics**: Firebase Analytics, Mixpanel, Sentry
- **Integrations**: Apple HealthKit, Hevy
- **Cloud Functions** (TypeScript): transactional email for server-owned notifications, plus server-derived leaderboard, achievement, and identity projections
- **Web**: Astro site in `web/`, built to `web/dist/`

## Project Structure

Organized by **features**, not file types. One type per file.

```
AscendApp/
├── App/                # Entry point, Firebase init, env plists, deep links
├── Features/           # Account · Authentication · Climbs · Debug · Home
│                       # Integrations · Leaderboards · Moderation · Monetization · Onboarding
│                       # Profile · Progress · Routines · ShareComposer · Workouts
└── Shared/             # Components · Extensions · Managers · Models · Repositories · Services · Views
AscendAppTests/         # Swift Testing suite
AscendLiveActivityWidgets/  # Live Activity / Dynamic Island extension
AscendWatch/            # watchOS companion target retained for the 1.1 release
AscendWatchShared/      # Compiled into BOTH binaries - platform-neutral value types only
.claude/skills/         # Project skills (see Skill Router)
AppStoreAssets/         # Shipped en-US iPhone screenshot set and its renderer
data/ascend-support-page-and-product-page-package/  # Durable en-US App Store product copy
docs/                   # Reference material - link to it, never duplicate it
functions/src/          # Cloud Functions (TypeScript)
scripts/                # Dev/staging DB, seeding, icon tooling
tests/firebase-rules/   # Emulator-backed Firestore/Storage rules tests
web/                    # Website source
```

**Tab architecture**: only the active tab should be mounted and running expensive work (SwiftData queries, refreshes, animations). Hidden tabs are deliberately inert. Switching tabs is allowed to lose per-tab navigation/scroll state - the lifecycle benefit outweighs that polish loss for now.

## Build, Test, Run

`AscendApp/App/Firebase/` needs the plist for the environment you're building - the Dev plist is committed, Staging and Production are gitignored and linked in locally; see the README there. CI decodes them from base64 secrets.

Both app schemes build the retained watch target as a dependency, but the 1.0 phone app does not embed it.
Whether a dependency-only build still demands an installed watchOS simulator runtime matching the watchOS **SDK** (not the deployment target, whatever the destination) is unverified now that nothing is embedded (#496), so `scripts/ci/ensure-watchos-runtime.sh` provisions one **best effort** - it warns and exits 0 on every failure, leaving `xcodebuild` the only authority on whether a build can proceed.
It runs locally too; CI runs it before both iOS jobs and before each deploy pipeline's archive.
`docs/heart-rate-zones-plan.md` owns the 1.0 and 1.1 packaging decision; `ascend-deploy` owns the CI side.

**Every local `xcodebuild` keeps `-derivedDataPath "$PWD/.build/dd"`, and CI keeps none.**
Xcode keys DerivedData to the project's *filesystem path* and never garbage-collects it, so a build run from a throwaway worktree - a no-mistakes ULID worktree, a treehouse lane - mints `~/Library/Developer/Xcode/DerivedData/AscendApp-<hash>` for a path deleted minutes later and orphans ~9 GiB forever; 197 recorded runs had accumulated 224 GB before this flag.
`.build/` is gitignored, so the output now dies with the directory that produced it and no sweep is needed.
That relocation puts the Firebase Crashlytics `run` binary inside `SRCROOT`, where `ENABLE_USER_SCRIPT_SANDBOXING` denies an undeclared read, so the Crashlytics phase declares it in `inputPaths` - delete that one line and every local build fails with `Sandbox: bash deny(1) file-read-data`, not with a missing file.
CI is the deliberate exception: its runners are discarded whole, and all three workflows restore an `actions/cache` keyed on `~/Library/Developer/Xcode/DerivedData/**/SourcePackages`, which relocating DerivedData would silently defeat (`ascend-deploy`).

```bash
# iOS tests (mirrors CI - .github/workflows/ci.yml; -derivedDataPath is local-only)
xcodebuild -project AscendApp.xcodeproj -scheme "AscendApp-Staging" \
  -configuration Staging -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
  -derivedDataPath "$PWD/.build/dd" \
  ENABLE_TESTABILITY=YES test

# iOS Release compile check (unsigned, device destination - catches Release-only
# errors). Never add -sdk iphoneos: it can override the retained watch target's
# SDK and still report success (`ascend-deploy`).
xcodebuild -project AscendApp.xcodeproj -scheme "AscendApp" \
  -configuration Release -destination "generic/platform=iOS" \
  -derivedDataPath "$PWD/.build/dd" \
  CODE_SIGNING_ALLOWED=NO build

npm run test:firebase-rules            # Firestore/Storage rules (emulator)
node --test scripts/test/*.test.mjs    # scripts + shared migration vectors (needs `npm --prefix scripts ci` first)
cd functions && npm run lint && npm test   # Cloud Functions
cd web && npm run build                    # Website -> web/dist/

# Deploy (aliases in .firebaserc: dev · staging · production)
# Pinned CLI - see docs/dependency-security.md before changing the version
# Order is load-bearing: the paid rules require a grant only the entitlement
# functions and their expiry index can produce, so they deploy last.
npx -y firebase-tools@15.22.1 deploy --project staging \
  --only firestore:indexes
npx -y firebase-tools@15.22.1 deploy --project staging \
  --only functions
npx -y firebase-tools@15.22.1 deploy --project staging \
  --only firestore:rules,storage,hosting
```

Deploys normally run from CI, not locally - see `ascend-deploy`.

## Environments

Three Firebase environments. App selects at compile time via `#if DEBUG / #elseif STAGING`:

| Environment | Firebase Project       | Build Config | Scheme              |
|-------------|------------------------|--------------|---------------------|
| Dev         | `ascend-f2e4f`         | Debug        | `AscendApp`         |
| Staging     | `ascend-staging-fa7d5` | Staging      | `AscendApp-Staging` |
| Production  | `ascend-prod-9c8f2`    | Release      | `AscendApp`         |

Environment plists live in `AscendApp/App/Firebase`, but the build must copy the selected one into the built app bundle as `GoogleService-Info.plist`. App startup should use `FirebaseApp.configure()` with the bundled default plist, not runtime `FirebaseOptions(contentsOfFile:)`, so Firebase Analytics resolves the correct app ID reliably.

**Environment-agnostic URLs**: Never hardcode Firebase project IDs. Derive from `FirebaseApp.app()?.options.projectID`:
```swift
let hostingURL = "https://\(projectId).web.app"
let functionsURL = "https://\(region)-\(projectId).cloudfunctions.net"
```

## Design System (tokens)

- **Fonts**: Montserrat (custom) - `montserratBold`, `montserratSemiBold`, `montserratMedium`, `montserratRegular`
- **Accent color**: `#86D30A`
- **Medal tokens**: Gold `#D4AF37`, Silver `#C0C0C0`, Bronze `#CD7F32`. Reserved for podium / rank-prestige moments. Apply sparingly, never as primary surface color.
- **Caution token**: `Color.ascendCaution` - a climber's own work that has not reached their account. Deliberately not lime (which means "earned") and not the destructive red. These and the medal tokens are the only sanctioned exceptions to lime-accent discipline.
- **Theming**: `ThemeManager` with dark/light mode, `effectiveColorScheme`, `.themedBackground()`
- **Icons**: SF Symbols

Component conventions, branding, and the spacing / radius / animation scales: `ascend-design-system`.

## Engineering Principles

Baseline for every change. If a loaded skill prescribes something more specific, follow the skill.

- **Single Responsibility.** If a type has two unrelated reasons to change, split it.
- **DRY.** Repeated three-line snippets are tolerable; repeated thirty-line patterns are debt.
- **YAGNI.** Build for what's needed now; refactor when a real second use case appears.
- **Layering.** Views render. View models hold UI state and orchestrate. Services own side effects. Models represent persistent data. A view that calls a network API directly is a smell.
- **Dependency injection over singletons in business logic.** Convenience singletons are fine for global state (theme, settings), not for testable logic.
- **Content-driven over rebuild.** Adding content (a climb, a routine, an email template) must never require shipping code. Writing a new code path per instance is a smell.
- **Business logic does not live in SwiftUI view bodies**, and **ViewModels do not import SwiftUI.** Anything decision-driving must be unit-testable without a view tree.
- **Pure functions where possible.**
- **Render path stays cheap.** No filter/reduce/sort over large arrays and no SwiftData queries inside `body`. Cache derived state.
- **Don't fight SwiftUI's diff.** Stable identities; don't pass freshly-recreated objects into deep children.
- **Clarity over cleverness.** If a future reader won't immediately understand a line, the code is wrong.
- **Delete before you defend.** Dead code, commented-out experiments, "just in case" abstractions - remove them; a deprecated path may only stay if it carries a written deprecation/removal date. Git history is the backup.
- **Comments explain WHY, not WHAT.** They earn space only for a non-obvious constraint, workaround, or invariant.
- **Backend contract compatibility.** Read `docs/backend-contract-compatibility.md` before changing Firestore shapes or rules, callable Function signatures, or Remote Config keys.

## Tripwires

Rules that fire from contexts that don't look like their own domain. Each names the skill with the full version.

- **Adding/renaming/removing a Firestore field requires a matching `firestore.rules` update, rules first** - strict `hasOnly`/`hasAll` means the server rejects unlisted fields. Fires while editing Swift. -> `ascend-firebase-data`
- **Bumping a `schemaVersion` constant is a Swift-only change; never re-pin the rule to it.** `firestore.rules` accepts a bounded range, because an exact pin locks stored documents and un-updated clients out the day the number moves. Fires while editing a `currentSchemaVersion`. -> `ascend-firebase-data`
- **Collecting a new data type, calling a required-reason API, or adding an SDK requires updating `AscendApp/PrivacyInfo.xcprivacy` in the same PR** - and the privacy policy, App Store questionnaire, and `Info.plist` strings must agree. Fires while adding a Firestore field or a HealthKit read. -> `ascend-privacy-manifest`
- **User media goes only under `users/{uid}/...` Storage prefixes**, never shared root paths. Fires while writing an upload path. -> `ascend-firebase-data`
- **A number the server awards from is a number the server must derive.** Validating a client-written document's shape and identity is not validating its evidence: `leaderboard_stats` passed both and still let one HTTPS request mint permanent achievements (#307). Any collection a scheduled job, a counter, or an award reads is server-write-only, derived from the canonical records. Fires while adding a public projection, a ranked field, or a job that reads one. -> `ascend-firebase-data`
- **Account-authored identity (displayName/photo) is public, so it may only be published through the validated write path and only rendered through the shared moderation resolver.** Views take `Moderated*` render models, never raw identity; public writes screen the name and bound the photo URL. Fires while writing any public projection - leaderboards, mirrors, functions, seeds - or any new surface showing another climber. -> `ascend-profile`
- **`firestore.rules` has an expression budget, and exceeding it is indistinguishable from a deliberate denial.** Firestore aborts at 1000 evaluated expressions and returns a bare `PERMISSION_DENIED`. The workout rule silently outgrew it and refused one climber's Live Climb for four days (ASCEND-IOS-1J: 88 denials; the other 499 events were ASCEND-IOS-1P cancellations charged to the same workout). Roughly 40-70 leaf comparisons fit, and one 28-key `hasOnly` alone costs ~9% of the budget - so rules enforce authorization and the trust boundary, not owner-private hygiene every Cloud Function re-derives anyway. Measure with `tests/firebase-rules/workout-expression-budget.test.mjs` before adding a check, and never let a declared cap exceed the client constant that enforces it (`WorkoutRemoteSyncLimits`). Fires while adding a field to any validated document. -> `ascend-firebase-data`
- **A retry budget without a clock is no budget.** Seven surfaces call `WorkoutSyncCoordinator`, so three triggers can consume three attempts in the same millisecond. Eligibility is a persisted absolute date (`WorkoutSyncOutboxEntry.nextEligibleAttemptAt`) that survives relaunch, never a bare counter, and any stop rule is conjunctive with elapsed time. `permissionDenied` is ambiguous, not permanent - a deployable rules defect emits the identical code - so it stops only after repeated refusals *and* 30 minutes, and stays re-openable by build change or the operator's `workout_sync_recovery_epoch` - and a series stopped by `authentication` re-opens when the climber signs back in. Fires while writing any sync coordinator's retry or catch path. -> `ascend-workout-model`
- **A climb that is not in the cloud says so until it lands.** Gate that surface on `Workout.isSyncedToCloud`, never on retry machinery (`== .rejected`, a view-local in-flight flag) - both made the warning vanish the moment a climber tapped retry. The vocabulary is sync, not backup: `Syncing`, `Couldn't sync this climb` + `TRY AGAIN`, and transient `Synced`. Fires while touching any cloud-failure surface. -> `ascend-brand-voice`, `ascend-workout-model`
- **If anything could possibly concern production or the data in it, query production.** Do not infer it, do not remember it, do not trust a document - including this one. Ascend has been live on the App Store since 2026-08-25, so "production is empty", "there is nothing to backfill", and "that collection has no rows" are measurements now, not recollections, and a stale one licenses shipping a change that damages real customers' data. `docs/production-backend-rollout-runbook.md` is the single owner of what production holds; a fresh read beats it. The trap is that Firebase tooling answers for whichever project is currently *active*, which is never production by default - `.firebaserc` makes `default` the dev project and an earlier task can leave staging selected - and staging is full of QA accounts that look exactly like real climbers, so the likeliest wrong answer is a plausible one from the wrong database. Confirm the active project first, name the environment on every read (`--env prod --confirm-production`), and name it in the answer: dev/default `ascend-f2e4f`, staging `ascend-staging-fa7d5`, production `ascend-prod-9c8f2`. Fires while writing a migration, a backfill, a contract document, or any sentence at all about what production contains. -> `ascend-data-investigation`, `ascend-firebase-data`
- **A query that failed and a query that found nothing both print nothing.** Six wrong answers in one session came from reporting an empty database off a read that never ran: a `firestore:query` subcommand that does not exist, an unquoted `(default)` breaking a URL inside a shell loop, a substring `grep -c` counting `users/<uid>/profile_pictures/` as the flat prefix. A production leaderboard holding 13 entries was reported as having none, and a bucket holding 264 objects as empty. Never claim data is absent until the same method has returned a positive result against a path known to be populated - `scripts/firestore-query.mjs` runs that control probe itself and keeps FOUND, EMPTY (verified), EMPTY (UNVERIFIED) and FAILED apart. Fires while answering a question about leftover data or whether a backfill landed, which does not look like Firebase work. -> `ascend-data-investigation`
- **A local script may not wait on a Firestore call without a deadline, and `db.bulkWriter()` is where that goes wrong.** BulkWriter strands its last few writes under load: reproduced 6/6 against staging, six processes each settling ~19,985 of 20,000 writes with every `close()` promise still pending 90 seconds later - parked in V8's microtask queue at 0% CPU with no open TCP connection, and nothing inside it to reject them. The Live Replay seed awaited that promise, so it printed nothing and ran past 20 minutes, and working could not be told from dead without sampling the process. `scripts/lib/firestore-bulk.mjs` is the one home for bulk reads and writes from `scripts/` - `db.batch()` commits through a worker pool, a deadline and retry budget on every call, a progress line on a two-second clock, a watchdog that calls a phase wedged, and about four times the throughput - and `scripts/lib/seed-step-runner.mjs` puts a wall clock on a spawned child so a wedged step is killed and named rather than blocking its parent. Fires while writing any backfill, migration, cleanup or seed script, none of which look like a concurrency problem until one hangs. -> `ascend-dev-fixtures`
- **A seed that reports success has only ever proved that documents were written.** The seed's own summary, the fixture audit and the content-ready contract all answer a question about Firestore, and staging was declared ready for two and a half days while a climb whose summary said 85 finishers rendered "4 completed" and whose rivals were absent from the bottom half of the building - because climb detail runs a `count()` over `splitBuckets/0/entries` and discards the counter beside it. Anything claiming an environment is ready has to read what the app reads: the same collections, the same aggregates, the same query shapes, through the client parsers mirrored in `scripts/lib/app-render-contract.mjs`. `node scripts/verify-filmable.mjs --project staging --email <account>` is that check, `seed-content-ready.mjs` runs it last and refuses to report success without it, and a read that FAILED is `ERROR` and exit 2, never an empty result. Fires while adding a seed step, a fixture, or any surface a capture session films. -> `ascend-dev-fixtures`, `docs/staging-content-capture.md`
- **Connectivity has one app-wide source of truth.** Never add feature-local offline detection or a second network-retry pattern. Fires when you're about to write the duplicate. -> `ascend-firebase-data`
- **Whether to prompt for notifications is one shared answer, not a per-surface reading.** Profile Achievements and the climbs collection each resolved iOS authorization on their own, so a climber who had already opted in was still told to `Turn on notifications` (#397). Every surface that prompts, requests, or changes the climb-drop preference - Settings and onboarding included - goes through `ClimbDropNotificationState`, which publishes each transition to all mounted surfaces and re-reads authorization on foreground, so a grant lands without a relaunch. The stored preference is the climber's standing intent: an iOS denial suppresses delivery and reports itself, it never rewrites the answer, and the send audience filters on each device's reported authorization instead. Fires while adding a notifications CTA or a permission check in feature code. -> `AscendApp/Features/Climbs/Services/ClimbDropNotificationState.swift`
- **A new route, tab, detail view or material sheet needs a `TelemetryScreenName` case and a `.trackOnce(screen:)`** - root routes and tabs fail to compile without one, but a view under `Features/*/Views/` fails silently and the screen is simply missing from the funnel. Fires while adding a screen, which does not look like analytics work. -> `AscendApp/Shared/Services/Telemetry/TelemetryScreenName.swift`
- **Every `Workout` comes from an in-app sensor flow.** Ascend is a racing app, not a tracker: manual logging and Apple Health workout import were deleted on 2026-08-08 (#437) and may not return behind a flag, a debug toggle, or a "just in case" path. `WorkoutSource.manual` and `.appleHealth` survive only because older stored rows carry those raw values. Apple Health's one remaining job is enrichment - `heartRate` and `activeEnergyBurned` read over an Ascend-recorded climb's own time window, never a foreign `HKWorkout`. Fires when wiring any new workout origin, or when copy is about to promise logging or tracking. -> `ascend-workout-model`, `ascend-apple-health-enrichment`
- **Heart-rate enrichment keeps looking on its bounded schedule even when celebratory surfaces stay silent.**
  Reading Apple Health once at save time races the wearable and loses (#438).
  The completion summary and Workout Detail are strict show-or-hide: the chart when a stored series exists, nothing at all when it does not - no heading, no card, no empty state - and Settings -> Integrations is the only surface that offers the connection or explains revoked access.
  Do not re-introduce a per-climb Health status enum for a view to render; the last one (`Phase`, `offersConnectionPrompt`, `fetchNow`) was deleted with its final consumer.
  The read is a `heartRate` / `activeEnergyBurned` query over the climb's own window, so Garmin, Whoop, Polar and Apple Watch all arrive through it: never branch on device, and never let copy name one wearable.
  Retries are a persisted absolute-date ledger on a bounded curve that stops, and a pass that cannot run (disconnected, killed) must not re-arm - re-arming off a pass that made no progress is a one-second spin wearing a schedule's clothes.
  Fires while adding any heart-rate surface or a second Health read. -> `AscendApp/Shared/Services/AppleHealthEnrichmentService.swift`, `AscendApp/Shared/Services/AppleHealthEnrichmentSchedule.swift`, `AscendApp/Shared/Services/AppleHealthEnrichmentAttemptStore.swift`
- **A climb's `totalSteps` is a height fact, not a race distance, so a distance correction never touches it.** It is `round(totalHeightMeters * 5.5)` on every climb in the catalogue - an antenna spire for a tower, elevation above sea level for a mountain. The verified count of the steps people actually climb goes in `realStairCount`, which `referenceStepCount` prefers and which `tier` must then be recomputed from; every populated number needs a citable primary source recorded in `docs/climb-real-stair-counts.md`, and no defensible figure means leaving it null rather than guessing. Changing it invalidates every recorded time on that climb. `calculatedFloors` renders beside it and follows the corrected number too - published storey count, else `round(referenceStepCount / 19.8)`, never height - because a corrected distance next to an uncorrected floor count contradicts itself on the one screen that exists to be honest. Fires while correcting catalogue data or writing copy about how tall a climb is - exactly where the field named "steps" looks like the right one. -> `live-climb-content`
- **Promoting a climb to `available` in the catalogue file *is* the announcement.** `announceClimbDrops` polls the hosted manifest every five minutes and pushes every newly available climb to every opted-in device, so a hosting deploy is a fleet-wide send with no confirmation step in front of it - and a climb is announced exactly once, for good, so a botched drop cannot be re-announced by toggling the state back. Fires while editing a JSON data file, which does not look like notification work. -> `live-climb-content`, `docs/climb-drop-notifications.md`
- **The climb-drop promise is an alert *at* the open, not advance notice.** Every shipped string says "when new climbs open"; the 24-hour advance claim that lived in the internal docs was never in the app, and nothing server-side can keep it - the catalogue is a static file with no unlock timestamp. Fires while writing notification copy or planning a drop schedule. -> `docs/climb-drop-notifications.md`, `scripts/test/climb-drop-promise-contract.test.mjs`
- **A chest strap always outranks an Apple Watch as the live heart-rate source.** Every live session type samples through the one shared recorder; never grow a second capture path. Fires while wiring any heart-rate source or new live session. -> `LiveHeartRateSourceKind.selectionPriority`, `LiveHeartRateRecorder`
- **No third-party frameworks without asking first.** Avoid UIKit unless requested. Fires at `import` time.
- **SwiftData + CloudKit**: never use `@Attribute(.unique)`; properties need defaults or must be optional; all relationships must be optional. Fires while writing an `@Model`.
- **Every change to an `@Model`'s persisted shape needs a new `VersionedSchema` and a stage in `AscendMigrationPlan`** - including moving an enum to a raw value - or lightweight migration silently defaults every existing row. Ascend has had both since the `Workout.source` move; do not re-derive that it has none. No store is exempt, and none ever was: dev, staging and TestFlight stores hold real rows, and production now holds real customers' - `docs/production-backend-rollout-runbook.md` is the single owner of what production contains, so nothing here restates it. Fires while editing an `@Model`, which is exactly where the reasoning goes wrong. -> `ascend-data-migration`, `swiftdata-pro`
- **A default value is only ever consulted when a property is NEW**, so a required property that already exists is not a defect and needs no sweep. Adding one that is non-optional with no default is, because existing rows have nothing to write: make it optional, give it a default if a single blanket value is honest, or write a custom stage that computes it per record. Deleting a model is silent and permanent. Fires while adding a property to an `@Model`. -> `ascend-data-migration`
- **Anything that must cover the *whole* local store reads `AscendLocalStore`, never its own list of `@Model` types.** Account deletion kept a hand-written list, it drifted behind the container, and one climber's climbs and in-progress session stayed on the device for the next account to publish (#348). A sweep, a row count, an export or a wipe that names types is already stale. Fires while adding a model, or while writing anything phrased as "all local data". -> `AscendApp/Shared/Models/AscendLocalStore.swift`, `ascend-data-migration`
- **Clearing the persistent store is not clearing the account.** Any operation that claims to clear or switch accounts - account switching, sign-out, reinstall, erasure - must also account for process-wide singletons and autonomous background writers, whose state outlives a store wipe and can repopulate the old owner's data behind it. Fires while adding a shared `@Observable` singleton or a self-scheduling background writer, long before anyone opens the deletion code; the procedure and ordering live in the skills. -> `ascend-firebase-data` (Account deletion), `ascend-apple-health-enrichment`
- **Store an `@Model` enum as a raw value if anything will ever filter on it.** `#Predicate` rejects a captured Codable enum (`unsupportedPredicate`) and *hard-crashes* on `array.contains(optional ?? "")`; `[String?].contains(optionalProperty)` is the working optional form. A non-filterable column is why a query becomes a whole-store scan. Fires while writing an `@Model` property, long before anyone writes the query. -> `swiftdata-pro`
- **Nothing on a screen's `.task` may run a store query whose cost grows with the user's history.** Home blocked for 182s answering a one-UUID question with `fetch(FetchDescriptor<Workout>())` (ASCEND-IOS-1K). Use the bounded queries in `Shared/Repositories/`; `Workout` carries its heart-rate series inline, so a full fetch is never cheap. Fires while writing a view's `.task` or a coordinator's `configure`. -> `ascend-apple-health-enrichment`
- **A new code path that writes or reshapes persisted data needs a Remote Config kill switch in front of it** - an iOS binary cannot be rolled back, so a shipped data-corrupting write has no other undo. Gate at the choke point that can *defer* the work (pending state survives untouched), never at the raw Firestore call. The one thing a switch cannot reach is a SwiftData schema migration: it runs inside `ModelContainer.init` before Remote Config has fetched anything. **Merging to `develop` publishes a new flag to dev and staging automatically, additively; production stays a publish by hand** (`scripts/publish-new-kill-switches.mjs`, and `scripts/deploy-remote-config.mjs` for a full replace). No automated path may change or re-enable an existing switch - it refuses while any switch is off - and the staging and production archives still fail when a flag the build reads is missing from the live backend. Fires while adding a repository write, a sync coordinator, or a backfill. -> `docs/remote-config-kill-switches.md`, `AscendApp/Shared/Services/RemoteConfig/`, `ascend-data-migration`
- **Ascend never asks a climber for their name, and there is no name step to re-add.** 1.0 was rejected under Guideline 4 on 2026-08-20 because the Apple request asked for `[.email]` only, so `fullName` was always nil and a mandatory name step ran for every Apple climber. The step was deleted from `PostAuthOnboardingStage` rather than hidden behind a condition, because a screen that asks for what Authentication Services already supplies is the rejection and a screen the climber cannot pass is the same rejection with extra steps - App Review's device has already spent its one first authorization, so it always arrives with nothing. `SuppliedNameAdoption` resolves a name instead, provider-agnostically (Google supplies one too) and always terminating: the profile Ascend already holds, then whatever this sign-in supplied, then `SignInNamePlaceholder` ("CHANGE ME", fixed in Settings -> Edit Profile). `ASAuthorizationAppleIDCredential.fullName` and `.email` are populated on the FIRST authorization for an Apple ID and app pair and never again, so the credential is captured before anything else can fail (`SignInIdentityStore`, which survives sign-out on purpose). Nothing is overwritten: a stored name wins, and a profile that could not be *read* defers to the next launch rather than guessing. A relay `@privaterelay.appleid.com` address is a real address. Fires while adding any onboarding stage, editing the auth request's scopes, or writing copy that asks for identity - none of which look like App Review work. -> `AscendApp/Features/Authentication/SignInSuppliedIdentity.swift`, `app-store-review`
- **Removing a `PostAuthOnboardingStage` case is an installed-base change, not a local one.** `markComplete` stores `Set(PostAuthOnboardingStage.allCases)`, so every finished climber's snapshot names every stage that existed when they finished. A synthesised `Codable` throws on the first unrecognised identifier, `PostAuthOnboardingStore` then falls back to a one-time legacy migration that resets `isComplete` and discards completed stages - which would drop the entire installed base back into onboarding on the update, with no rollback available to an iOS binary. `PostAuthOnboardingSnapshot.init(from:)` drops identifiers it does not recognise and remaps a vanished `currentStage` to `.first`; keep it that way, and keep `plannedStepCount`, `progressIndex` and `next` derived from `allCases`. `OnboardingAnalyticsContext.orderedStepIDs` is the one list that is NOT derived and must be edited by hand, or `step_index` silently develops a gap and `step_count` keeps counting a step nobody sees. Fires while adding or removing an onboarding stage. -> `AscendApp/Features/Onboarding/Models/PostAuthOnboardingSnapshot.swift`
- **The app-access gate is the whole app for an unentitled climber, so every route Apple requires unconditionally has to leave from it.** Guideline 5.1.1(v) grants no paid-status exception, and with billing grace off a declined card parks a real subscriber there for up to 60 days - which is why the gate carries an account-deletion link and why deletion copy has to say the App Store subscription keeps billing. Fires while redesigning or trimming the paywall gate, where the reasoning is about conversion rather than compliance. -> `AscendAppTests/LockedOutSubscriberRecoveryContractTests.swift`, `app-store-review`
- **A refusal that must not be escapable is a route, never a sheet, and the hard update lockout is resolved first - above authentication.** Superwall presents outside `RootView`'s hierarchy and a second sheet at the same modifier level defers the first, so the lockout sheet was invisible to exactly the climber most likely to be on a stale build: the unentitled one who cold-starts into the paywall (#429). Order is lockout -> auth -> entitlement -> onboarding -> main app, and `AppRootRouteResolver` stays synchronous and pure - the Remote Config and RevenueCat reads happen outside it, so cold start and foreground run the identical decision. The floor is the last one the device *received*, seeded from the persisted activation before any fetch: hitting the lockout online means hitting it offline, and only a device the backend never answered fails open. The soft nudge stays a dismissible sheet. Fires while adding any modal, redesigning the gate, or writing a "block the app" state. -> `AscendApp/App/AppRootRoute.swift`, `AscendApp/Shared/Services/RemoteConfig/AppVersionGateState.swift`
- **App Review buys in the sandbox from a binary the StoreKit layer reads as production, so no entitlement check may filter by StoreKit environment.** RevenueCat counts an entitlement in `activeInCurrentEnvironment` only when its own `isSandbox` equals `appStoreReceiptURL.path.contains("sandboxReceipt")`; a review install has a sandbox purchase and no sandbox receipt path, so the reviewer's entitlement vanished, a charged reviewer was told `Ascend couldn't confirm your subscription`, and 1.0 was rejected under Guideline 2.1(b) (#506). TestFlight cannot reproduce it - its receipt path says sandbox and the two flags agree - so an internal purchase test passing is not evidence. Every read of `CustomerInfo` goes through the one shared rule, never `activeInCurrentEnvironment`. Fires while touching any entitlement, paywall, or restore code, which does not look like App Review work. -> `AscendApp/Features/Monetization/Services/EntitlementInfos+AppAccess.swift`, `AscendApp/Features/Monetization/Services/StoreKitEnvironmentDiagnostics.swift`
- **A free grant only opens the paywall; only an allowlisted product id opens the app.** RevenueCat publishes a promotional entitlement as `rc_promo_{entitlement}_{duration}`, so every duration is a different product, and the webhook writes the server grant `users/{uid}/entitlements/app_access` only for a product in the deployed `REVENUECAT_SERVER_CONFIG.allowedProductIds`. Grant an unallowlisted duration and the person clears the paywall while every server-guarded screen fails - which is what "1 year" did on 2026-08-25, since only `lifetime` is allowlisted in production. The live allowlist is the secret version the *deployed* `revenueCatWebhook` is bound to, never the Keychain copy (a full version stale that same day) and never memory; an allowlist that cannot be read is a refusal, not a permission. Use `scripts/comp-access.mjs`, never two dashboards. Fires while triaging a climber who "has access" but sees `Leaderboard stalled`, and while editing `allowedProductIds` - neither looks like comp work. -> `ascend-comp-access`
- **A surface Ascend draws itself is invisible to Sentry's masking, so it reaches a crash screenshot legibly.** The SDK covers text, images, SF Symbols, web views and `AVPlayerView`; it does not cover Swift Charts marks *or their axis labels*, `Canvas`/`Shape` drawing that encodes a measurement, or `AVPlayerLayer`-backed video. A masked screenshot of Workout Detail still showed the whole heart-rate trace with real BPM values on the axis until `View.sentryMasked()` was applied. Apply it inside the view's own definition, never at call sites, and add the surface to **both** suites that hold the mask honest: `AscendAppTests/SentryMaskingEvidenceTests.swift` proves it is masked, and `AscendAppTests/SentryMaskInteractionTests.swift` proves the mask does not swallow the touches that surface still needs - neither list can notice an eighth surface nobody added. Masking is a gate on shipping that screenshot, not a follow-up, and the mask deliberately reaches a few points past the surface because a stroked chart mark paints outside its own layout frame. The crash screenshot is the whole capture surface, and it is taken only for a *severe* event - `SentryCrashContextPolicy` declines the synchronous main-thread render for ordinary non-fatal errors, because 22 `recordError` call sites paying 36-160ms each is the App Hang hazard again. **Session replay was built and then deliberately dropped**, because on-error mode records the entire session after the first error and any non-zero rate renders the screen on the main thread once a second in every session, which is unaffordable next to Fatal App Hangs being production's top signal - both sample rates are pinned to zero by test. Fires while adding a chart or a media player, which does not look like privacy work. -> `docs/sentry-setup.md`
- **Never commit API keys, secrets, or QA credentials**, and never bundle them into production builds.

## Ascend-Specific Overrides

- **Targeting**: iOS 26.0+, Swift 6, strict concurrency. If a newer iOS API meaningfully improves a feature, mention it and gate it with `@available` rather than silently raising the baseline.
- **State management**: SwiftUI with `@Observable` for shared state; mark shared `@Observable` classes with `@MainActor`.
- **Local style conventions**: prefer modern Swift idioms - `replacing("a", with: "b")`, `URL.documentsDirectory`, `url.appending(path:)`, `.formatted()` or `Text(..., format:)`, and `localizedStandardContains()` for user-facing filtering.

## Skill Router

Ascend domains - load before touching the area:

| Domain | Skill |
|---|---|
| Live Climbs, attempts, replay, globe, catalog | `ascend-live-climbs`, `live-climb-content` |
| Leaderboards, ranking, ties, week windows | `ascend-leaderboards` |
| Workout model, durability, sync, measurement | `ascend-workout-model` |
| `@Model` shape changes, schema versions, migration stages, backfills | `ascend-data-migration` |
| Apple Health connection and enrichment | `ascend-apple-health-enrichment` |
| Best Efforts, Progress, trends | `ascend-best-efforts` |
| Routines, intervals | `ascend-routines` |
| Profile, demographics, public mirrors, block/report moderation | `ascend-profile` |
| Onboarding, auth routing, paywall priming | `ascend-onboarding` |
| Analytics, telemetry, events | `ascend-analytics` |
| Sharing, stickers, export | `ascend-share-composer` |
| Firestore, Storage, rules, connectivity | `ascend-firebase-data` |
| Investigating what is actually in a database or bucket | `ascend-data-investigation` |
| Comping free app access, revoking it, seeing who holds one | `ascend-comp-access` |
| Privacy manifest, App Store data declarations | `ascend-privacy-manifest` |
| CI, release, TestFlight, fastlane | `ascend-deploy` |
| Web, email, Cloud Functions | `ascend-web-email` |
| Seeding, fixtures, debug tools, QA sign-in | `ascend-dev-fixtures` |
| UI conventions, branding, icons | `ascend-design-system`, `icon-workflow` |
| Copy, empty states, tone | `ascend-brand-voice` |
| Sentry issue triage | `sentry` |

Generic skills, mandatory in-domain: `swiftui-pro` · `swift-concurrency-pro` · `swiftdata-pro` · `swift-testing-pro` · `vibe-security` (any auth/authz/trust-boundary, secrets, payments, or user-data change) · `firebase-basics` · `firebase-auth-basics` · `firebase-firestore-standard` · `firebase-hosting-basics` · `healthkit` · `widgetkit` · `app-intents` · `storekit` · `ios-security` · `ios-networking` · `ios-accessibility` · `debugging-instruments` · `app-store-review` · `asc-xcode-build` · `asc-release-flow` · `asc-metadata-sync` · `asc-submission-health` · `asc-testflight-orchestration` · `product-design-playbook`

If a task spans domains, load every match. If a request is ambiguous but clearly adjacent to a domain, load the skill rather than skipping it. **This guide wins over any skill on conflict.**

## Branching & Issue-First Workflow

- `main` - production-ready. Only receives merges from `develop` when ready to ship.
- `develop` - long-lived staging integration branch. Contains everything `main` has plus in-progress work; pushes here auto-trigger staging builds.
- `feature/*`, `fix/*`, `chore/*` - branch off `develop`, PR into `develop`.

Resolve work to a GitHub issue before implementing:
- If the user provides an issue number, use it.
- Otherwise search open issues. One clear match -> confirm it with the user. No clear match -> propose creating one and get approval first.
- Don't start implementation until an issue is confirmed, unless the user explicitly says to proceed without one.
- Branch names include the issue number: `feature/issue-<number>-<short-slug>`.
- PRs target `develop` and include `Closes #<number>`.

## Key Config Files

- `.firebaserc` - project aliases (dev, staging, prod)
- `firebase.json` - hosting, functions, firestore config
- `firestore.rules`, `storage.rules`, `firestore.indexes.json` - security rules and indexes
- `.github/workflows/ci.yml` - PR validation; `ci-required-check-fallback.yml` routes the required checks for PRs that change no CI-relevant path (`ascend-deploy`)
- `.github/workflows/deploy-staging.yml`, `deploy-production.yml` - deploy pipelines (prod gated)
- `Gemfile`, `fastlane/Appfile`, `fastlane/Fastfile`, `fastlane/Matchfile` - build/signing/TestFlight
- `remoteconfig.template.json` - the kill-switch parameters, plus the captain-only version thresholds no automation publishes anywhere; CI publishes new switches additively to dev and staging only, full replaces stay manual via `scripts/deploy-remote-config.mjs` (`docs/remote-config-kill-switches.md`)
- `docs/dependency-security.md` - deliberate dependency pins and overrides; read before bumping any npm dependency

## Project Context File (All AI Providers)

`CLAUDE.md` is the canonical project context file. `AGENTS.md` is a symlink to it - editing one edits both. There is exactly one source of truth; do not break the symlink or duplicate content between them.

Skills live in `.claude/skills/<name>/SKILL.md`. Claude Code auto-discovers them; other providers (Codex, Cursor, Copilot) should read that directory directly - the files are plain markdown and harness-neutral.

## Maintaining this file

This file is the always-on core, loaded on every turn of every session. Keep it lean.

- Add here only what is true for **almost every** session: identity, scope, stack, structure, build/test, environments, tokens, engineering baseline, tripwires, routing.
- Domain detail belongs in a skill under `.claude/skills/`, with a `description` and (where it maps to files) `paths:` globs so it auto-activates. Add a Skill Router row.
- **`paths:` makes a skill conditional** - it stays out of the skill listing until a matching file is touched. So a skill named by a **tripwire** must have no `paths:` globs, or it won't be loadable from the context where its tripwire fires. Give those skills a `description` that names their real trigger contexts instead.
- Add a **tripwire** only for a rule that fires from a context that doesn't look like its own domain - the agent would violate it before thinking to load the skill. One line, pointing at the skill with the full version.
- Prefer a pointer to the authoritative file, command, or doc over copying detail that will drift. Never hand-maintain an index of code (component lists, file inventories) - it rots on the next commit.
- **Skills never share a reference file.** A skill may carry `references/*.md` for detail too long for its `SKILL.md`, but those belong to that skill alone. Knowledge two skills need is stated once - in whichever skill owns it, or in `docs/` when it outgrows a skill - and the other links to it in one line. Two copies of a rule become two different rules.
