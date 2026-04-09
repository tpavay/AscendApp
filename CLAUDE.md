# Ascend — Project Guide

## What Is Ascend
Ascend is a comprehensive stairstepper workout tracker for iOS. It serves the full spectrum of users — from someone who's never used a stairstepper to advanced athletes doing progressive overload with weighted vests. Users log workouts, track progress, set personal records, create routines, and compete on leaderboards.

**Solo dev + AI assisted** (Tyler Pavay). Monetization plan: freemium with subscription (free core features at launch, premium tier for future advanced features). Near-term focus: polish, widgets, landing page, custom illustrations/animations, then App Store launch.

---

## Instruction File Sync Rule (All AI Providers)
- `AGENTS.md` and `CLAUDE.md` must stay synchronized for shared project context.
- When introducing or changing features, shared patterns, architecture decisions, or design conventions, update both files in the same change.
- This rule applies to all AI providers used on this repo (Codex, Claude, Cursor, Copilot, etc.).

---

## Tech Stack
- **iOS 17.0+**, Swift 6, SwiftUI (when a newer iOS API would meaningfully improve a feature being discussed, mention it so the developer can decide whether to use an `@available` check — don't silently use only the older API)
- **Data**: Local-first with cloud sync — SwiftData on device, Firebase Firestore for backup/sync/sharing
- **Backend**: Firebase (Auth, Firestore, Storage, Cloud Functions, Hosting)
- **Integrations**: Apple HealthKit, Strava, Hevy
- **Cloud Functions** (TypeScript): Strava OAuth + sync, waitlist signup endpoint with dedupe, transactional email job queue

---

## Architecture

### Project Structure
Organized by **features**, not file types. One type per file.

```
AscendApp/
├── App/                        # App entry point, Firebase config
│   ├── AscendApp.swift         # Firebase init, environment selection, deep links
│   └── Firebase/               # Environment-specific GoogleService-Info plists
├── Features/
│   ├── Workouts/               # Logging, detail, editing, sharing, import
│   ├── Routines/               # Workout routines and folders
│   ├── Progress/               # Best efforts, trends, charts
│   ├── Leaderboards/           # Rankings
│   ├── Home/                   # Home screen
│   ├── Account/                # Settings, profile, privacy policy, integrations
│   └── Debug/                  # Debug tools (DEBUG builds only)
├── Shared/
│   ├── Models/                 # SwiftData models, TabRouter
│   ├── Views/                  # MainTabView, shared UI
│   ├── Components/             # Reusable: FormTextField, FormButton, FormSection
│   ├── Services/               # WorkoutImportCoordinator, WorkoutService, PersonalRecordService
│   └── Managers/               # StravaManager, ThemeManager, SettingsManager
web/public/                     # Firebase-hosted website (landing page, privacy policy)
functions/src/                  # Cloud Functions (TypeScript)
```

### Environments
Three Firebase environments. App selects at compile time via `#if DEBUG / #elseif STAGING`:

| Environment | Firebase Project | Build Config | Scheme |
|---|---|---|---|
| Dev | `ascend-f2e4f` | Debug | `AscendApp` |
| Staging | `ascend-staging-fa7d5` | Staging | `AscendApp-Staging` |
| Production | `ascend-prod-9c8f2` | Release | `AscendApp` |

Environment plists live in `AscendApp/App/Firebase`, but the build must copy the selected one into the built app bundle as `GoogleService-Info.plist`. App startup should use `FirebaseApp.configure()` with the bundled default plist, not runtime `FirebaseOptions(contentsOfFile:)`, so Firebase Analytics resolves the correct app ID reliably.

**Environment-agnostic URLs**: Never hardcode Firebase project IDs. Derive from `FirebaseApp.app()?.options.projectID`:
```swift
let hostingURL = "https://\(projectId).web.app"
let functionsURL = "https://\(region)-\(projectId).cloudfunctions.net"
```

### Data Models (SwiftData)
Workout, LeaderboardStats, PersonalRecord, Goal, Routine, RoutineFolder, WeightPersonalRecord, AggregateWeightRecord, PendingMediaUpload

### Firebase Storage Pathing + Rules
- User-generated media must be stored under user-scoped prefixes:
  - `users/{uid}/photos/...`
  - `users/{uid}/videos/...`
  - `users/{uid}/profile_pictures/...`
- Never write user media to shared root paths (`photos/`, `videos/`, `profile_pictures/`) in production.
- Legacy share card template assets may still live under `share-card-templates/...`, but workout share cards in v1 must not fetch their backgrounds or layout config from Firebase.
- Account deletion and cleanup should target only the authenticated user's scoped prefix.

### Workout Share Card Architecture
- Workout share cards in v1 use bundled poster background assets so the share surface renders instantly and offline.
- All workout share cards should render inside a shared rounded-square surface component; card-specific layout views should sit on top of that surface rather than reimplementing clipping, borders, or background handling.
- `WorkoutShareCardPreset`, `ShareCardType`, and `WorkoutShareCardComposer` own the preset-driven stat priority, typography tokens, surface/background config, and layout inputs for the rendered card.
- Shared decorative share-card elements, such as stat dividers, should live in reusable parameterized components rather than being embedded inside one card layout.
- `WorkoutShareCarouselView` remains the container surface, but the shipped card set is currently a single square poster until more bundled presets are added.
- When adding a new share card, prefer a new card type + preset + layout view instead of branching inside an existing card view so current card layouts stay isolated.
- Do not reintroduce backend-driven workout share backgrounds or Firestore-configured stat layouts unless product explicitly chooses that direction again.

### Privacy Manifest Maintenance Rule
- `AscendApp/PrivacyInfo.xcprivacy` is a machine-readable Apple privacy manifest that ships inside the app bundle. It is REQUIRED for App Store submission and must stay in sync with reality.
- Update `AscendApp/PrivacyInfo.xcprivacy` in the SAME PR whenever you:
  1. **Collect a new data type** — any new field written to Firestore, Firebase Storage, Crashlytics, Analytics, a new HealthKit metric read, or a new profile/onboarding field captured from the user. Add or extend an entry under `NSPrivacyCollectedDataTypes` with the right Apple data type, `Linked` flag, and purpose(s).
  2. **Call a new "required reason" API category** — `UserDefaults`, file timestamp APIs (`.contentModificationDateKey`, `stat`, `getattrlist`, etc.), system boot time (`mach_absolute_time`, `systemUptime`), disk space (`volumeAvailableCapacity`, `statfs`), or active keyboards (`UITextInputMode.activeInputModes`). Add an entry under `NSPrivacyAccessedAPITypes` with an Apple-approved reason code from https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api.
  3. **Add or upgrade a third-party SDK** — open the SDK's bundled `PrivacyInfo.xcprivacy` and add any new data type / API reason it forces on the host app.
  4. **Start performing tracking** in the ATT sense (cross-app or cross-site identifiers, ad networks, IDFA collection) — flip `NSPrivacyTracking` to `true`, populate `NSPrivacyTrackingDomains`, implement the ATT prompt via `ATTrackingManager`, and add `NSUserTrackingUsageDescription` to `Info.plist`.
- The privacy manifest, the user-facing Privacy Policy at `ascendstepper.com/privacy`, the App Store Connect "App Privacy" questionnaire (nutrition labels), and the `NS*UsageDescription` strings in `Info.plist` must all describe the SAME set of data practices. If you change one, change all four.
- The current manifest declares NO tracking and NO ads. Firebase Analytics is enabled in Release/TestFlight only, with `IS_ADS_ENABLED=false`. Do not enable ad SDKs or IDFA collection without flipping `NSPrivacyTracking` and adding ATT.
- When in doubt about whether something needs to be declared, declare it. Under-declaring is a rejection risk; over-declaring is not.

### Firestore Schema-Change Rule
- `firestore.rules` uses strict `hasOnly` + `hasAll` field validation on every collection. Adding, removing, or renaming a field in the app **requires a matching update to `firestore.rules`** — otherwise writes will be rejected at the server.
- The same `firestore.rules` file must be deployed to all environments (dev, staging, production) to catch schema mismatches early. Never test against loose rules in dev while production has strict ones.
- When changing Firestore document schemas, always update in this order:
  1. Update `firestore.rules` to allow the new/changed fields
  2. Update Swift model + write logic
  3. Deploy rules to all environments before or alongside the app update

### Import UX
- Workout import supports individual import, selected-batch import, and import-all from the same sheet.
- Import architecture uses one canonical `Workout` plus local `WorkoutSourceLink` provenance records per provider. New import UI and state should flow through `WorkoutImportCoordinator`, not provider-specific views/services.
- Apple Health is read-only. First connect may backfill historical workouts, but routine checks must stay incremental and sample-only until a workout is actually imported.

### Analytics Architecture
- `TelemetryManager` remains the app-facing facade, while reusable telemetry types and sinks live under `Shared/Services/Telemetry`.
- Feature analytics definitions should live in feature-owned `Analytics/` folders (for example `Features/Workouts/Analytics`) as typed `TelemetryEvent` / `TelemetryScreen` definitions.
- Feature code must not import Firebase directly for analytics or breadcrumbs. Route analytics through `TelemetryManager` and shared sinks only.
- Log product events from the owning view model, coordinator, manager, or service instead of scattering calls through leaf views. The main exception is SwiftUI screen tracking, which should use the shared `.analyticsScreen(...)` modifier.
- Keep analytics parameters low-cardinality and privacy-safe. Do not log raw user-entered text, email, DOB, exact location, exact health samples, or other high-sensitivity payloads.
- New analytics work should include focused tests using `InMemoryTelemetrySink` so event contracts can be verified without a Firebase runtime.
- DEBUG builds expose a Telemetry Console inside Debug Tools so recent events and screen views can be inspected locally when running with telemetry enabled.

### Climb Anything V1 Architecture
- `Climb Anything` is a 3-screen loop:
- `Home` is a stateful entry card and does **not** show the globe
- `Browse` owns the searchable globe experience
- `Climb Detail` is the primary climb destination
- Entering `Browse` from another surface should reset the globe to the default overview state and clear any stale preview card/search state from a previous visit.
- Dismissing a browse preview card should clear the card and restore the overview zoom while preserving the user's current globe center.
- Browse pin focus should derive camera zoom from climb metadata (category + climb size signals) so compact landmarks can zoom tighter than large natural climbs without per-climb camera overrides.
- Globe pins should use state-driven location-pin styling instead of colored dots:
  - available climbs use a hollow outlined pin
  - the active climb uses a filled pin with a static double-pin glow treatment
  - completed climbs use a filled circular check badge instead of a pin
- Home climb states are:
  - never climbed
  - inactive with completion history
  - active climb in progress
- `ClimbAttempt` is the source of truth for climb progress and history. It replaces the earlier completion-only model.
- Only one climb attempt may be `active` at a time. Starting another climb should confirm replacement and mark the old attempt `abandoned`.
- New workouts should auto-advance the active climb only when the workout's actual session start time is on or after the climb activation time. Import time or insertion time must never qualify an older workout for climb progress.
- Non-`multiSession` climbs are one-workout challenges. The first eligible workout must fully complete the climb or the attempt becomes `failed`, stops being active immediately, and remains visible in climb history as an attempt rather than a completion.
- Active climb progress application should flow through the shared workout mutation pipeline so manual logging and imports behave consistently.
- Climb detail has 3 swipe pages:
  - `Overview` (real)
  - `Your History` (real)
  - `Leaderboard` (present but clearly coming soon in v1)
- Per-climb rank and total-climber counts must stay hidden until real backend data exists.
- Climb content uses a remote-first catalog and remote-only climb images:
  - a tiny hosted manifest at `/climbs/manifest.json`
  - a versioned hosted catalog at `/climbs/catalog-v{N}.json`
  - Storage-backed image assets at `climb-images/{climbId}/v{imageSetVersion}/{hero|card|thumb}.heic`
- The app should keep a tiny bundled/bootstrap fallback for climb metadata only, so Home and Browse can still render if the remote catalog has never been fetched and there is no disk-cached catalog yet.
- Once the hosted catalog has been fetched successfully, subsequent launches should prefer the disk-cached catalog before falling back to the bundled bootstrap catalog.
- Climb images should not ship inside the iOS app bundle. Artwork is remote-only, and image misses should render the climb artwork placeholder until the remote image is cached locally.
- Remote climb catalog and remote climb images should use shared disk-backed cache infrastructure under `Shared/Services/Caching`, while climb-specific fetch/decode logic stays inside climb repositories.
- Home, Browse, and Detail should render from cached/local state first, then refresh remote climb content in the background instead of blocking the UI on network fetches.
- Reusable climb card surfaces should share `ClimbSplitCardSurface`, `ClimbLeadingArtworkPanel`, and `AnimatedClimbCardBorder` instead of reimplementing split layouts, image clipping, or tier-border animation per screen.
- All climb tiers should use the shared rotating border treatment from `AnimatedClimbCardBorder`, with each tier driven by its own color tokens; mythic remains the emphasized tier with the purple-forward prismatic palette and strongest glow.

### Onboarding V2 (Issue #63)
- Root routing uses onboarding completion before normal auth/home flow.
- Onboarding sequence is: welcome, HealthKit permission, measurement system, base level, personal details (DOB + gender), body metrics (height + bodyweight), notifications permission, then mandatory auth.
- Auth is the final onboarding step with Apple/Google only (no "sign in later").
- Onboarding draft/progress persists locally across app restarts; uninstall/reinstall resets via app data removal.
- Bodyweight is a single profile-level value (set in onboarding, editable in settings) and is intended to be the app-wide source for body mass usage.

### Base Level + Intensity Architecture
- User-facing workout personalization now centers on a `base level`, defined as the StairMaster level a user can comfortably sustain for about 10 minutes.
- `SettingsManager` is the source of truth for base-level state:
  - `seededBaseLevel` from onboarding or migration
  - `autoCalculatedBaseLevel` from workout history
  - `manualBaseLevelOverride` when the user explicitly adjusts it in settings
- Legacy `fitnessLevel` remains only as migration/bootstrap input. New UX should use `Base Level`, not `Fitness Level`.
- `SPMMappingService` owns the exact 1-25 level-to-SPM mapping and nearest-level reverse lookup.
- Unified workout intensity is derived from:
  1. `steps + duration -> stepsPerMinute`
  2. `stepsPerMinute -> equivalent level`
  3. `equivalent level` relative to `effectiveBaseLevel`
  4. duration plus supporting signals (RPE, HR, METs, added weight) to produce the final effort score
- Historical percentile remains a ranking layer over the unified effort score and other raw workout metrics. It should not become a separate competing definition of intensity.
- All create/edit/delete/import flows that change workouts should run through `WorkoutDerivedDataService.recalculateAll(...)` so base level, effort values, percentile snapshots, personal records, and local leaderboard aggregates stay in sync.

### Routine Template Personalization
- Built-in routines are now authored as relative templates, not fixed absolute levels.
- `ClimbZone` defines the shared routine effort offsets from the user's `effectiveBaseLevel`:
  - `recovery -5`
  - `warmup -3`
  - `easy -2`
  - `steady 0`
  - `tempo +2`
  - `threshold +4`
  - `sprint +7`
  - `allOut +10`
- `RelativeRoutineInterval` + `BuiltInRoutineTemplateDefinition` are the source format for built-in templates, and `RoutineTemplateResolver` converts them into absolute `RoutineInterval` values for a specific base level.
- Built-in template definitions can also declare browse metadata:
  - `browseSections` for curated rails like `Getting Started`
  - `isFeatured` for the separate `Popular` rail
- `RoutineService.ensureBuiltInRoutinesExist()` is responsible for resolving the current built-in routines against `SettingsManager.shared.effectiveBaseLevel`, updating existing built-ins in place, inserting missing templates, and deleting obsolete built-ins.
- User copies of built-in routines stay frozen at the absolute levels from the moment they are copied. Only routines with `source == .builtin` should be re-resolved when base level changes.
- When workout-derived data recalculation changes the effective base level, the app should refresh built-in routines and broadcast `.routineTemplatesDidChange` so routines surfaces reload with the new resolved levels.

### Routine Live Player Architecture
- `ActiveRoutineViewModel` is the source of truth for an in-progress routine session. `ActiveRoutineView` should render from the view model instead of owning workout progression in ad hoc `@State`.
- Timer updates should flow through the view model using `Timer.publish(...).autoconnect()` and Date-delta math rather than `Task.sleep` loops, so pauses and foregrounding do not distort elapsed time.
- The live player UI is composed from focused components:
  - `SegmentedProgressBar` for the thin full-width routine timeline
  - `LiveIntervalLevelPill` for the current level and optional non-standard step type
  - `StaircaseView` for the right-edge routine progress visualization
  - `LiveWorkoutControlButton` for skip, pause/resume, and stop controls
  - `WorkoutCompleteView` for the completion surface instead of embedding that UI directly in `ActiveRoutineView`
- The staircase is decorative only. It should stay accessibility-hidden, use app-defined colors (`.accent`, heatmap colors, named asset colors), and avoid ad hoc hex values inside feature views.

### Week Start + Leaderboard Windowing
- Ascend now uses a single app-wide Monday week start. The old user-configurable week-start preference and selection UI are removed.
- Goals and home summaries should use Monday-based weeks in the relevant local timezone.
- Competitive/global leaderboards use canonical Monday-based weeks in `UTC`.
- Leaderboard documents are current-period-only, not historical archives:
  - one weekly document per user
  - one monthly document per user
  - one yearly document per user
  - one all-time document per user
- Leaderboard docs must store:
  - `schemaVersion`
  - `timeFrame`
  - `periodKey`
  - `periodStartAt`
  - `totalSteps`
  - `totalFloors`
  - `totalWorkouts`
  - `totalDuration`
  - `stepsPerMinute`
- `steps` is the canonical climb leaderboard metric. `floors` remains supporting/display data only and must never change rank order.
- Pace leaderboards remain in product scope, but they rank by canonical `stepsPerMinute`, not viewer-preference floors-per-minute.
- Leaderboard publication is mutation-driven:
  - workout create/import/delete always affects leaderboard publication
  - workout edits only affect leaderboard publication when `date`, `duration`, `steps`, or `floors` change
  - photo-only, notes-only, METs, heart-rate, calories, and other non-leaderboard edits must not trigger leaderboard publication
- Leaderboard refresh UI should never own the only Firestore publication path. Users must appear remotely even if they never open the leaderboard tab.
- Local leaderboard state should update incrementally for the current periods only. Full-history rebuilds are for migration, repair, or schema backfill only.

### Leaderboard Seeding Policy (Debug / CI)
- Firestore client rules only allow writes to `leaderboard_stats` where `userId == request.auth.uid`.
- Multi-user seed data should not be written from client debug tools in shared environments.
- Use server-side seeding (Admin SDK / Cloud Function / CI job) for deterministic multi-user leaderboard fixtures.
- For local-only iteration, use Firestore emulator or seed only the authenticated user.

### Workout Seeding Policy (Debug)
- Debug Tools includes local SwiftData workout seeding presets for Simulator workflows (`App Store Screenshots`, `Quick Demo`).
- Seeded workout metadata is stored in `Workout.sourceMetadata` with `isTestData=true`, `seedSource="debug-tools"`, and `preset` for targeted cleanup.
- Workout seeding is idempotent for debug usage: seeding replaces existing debug-seeded workouts before inserting the new preset.
- Clearing seeded workouts must recalculate personal records and local leaderboard aggregates to keep derived data consistent.
- Weighted vest debug data should use an intended pounds range and convert to kilograms when measurement system is metric.

### Leaderboard UX Flow
- The leaderboard tab root should be a category hub with per-metric preview cards (`Climb`, `Workouts`, `Duration`, `Pace`) and a `See all` action on each card.
- `See all` opens a metric-specific leaderboard detail screen.
- On the metric-specific detail screen, keep the metric locked to the selected category and allow filtering by time frame (`Weekly`, `Monthly`, `All Time`).
- The metric-specific detail screen should be composed from focused subviews:
  - `LeaderboardPickerView` (time frame chips)
  - `LeaderboardPodiumView` (top 3 only)
  - `LeaderboardUserRowView` (pinned current user row when needed)
  - `LeaderboardRowListView` (rank list)
- `LeaderboardPodiumView` should always render a 3-slot podium; empty slots use a motivational waiting-for-challengers treatment.
- The current user row must never be duplicated: when pinned under podium, remove that user from the list rows.

### Design System
- **Fonts**: Montserrat (custom) — `montserratBold`, `montserratSemiBold`, `montserratMedium`, `montserratRegular`
- **Accent color**: `#B4CC00`
- **Theming**: `ThemeManager` with dark/light mode, `effectiveColorScheme`, `.themedBackground()`
- **Icons**: SF Symbols (considering migrating to a custom icon set for consistency)
- **Icon consistency**: Use the same icon for the same action across screens (for example, overflow menus should use one consistent `ellipsis` style app-wide unless product design explicitly says otherwise)
- **Level sliders**: Reuse the shared `SegmentedHeatmapSlider` for 1-25 heatmap-based level selection (base level onboarding/settings and routine interval builder) instead of creating screen-specific segmented sliders
- **Sheets**: Use `AppSheetPreset` with `.appSheetStyle(...)` for sheet sizing, drag indicator behavior, and sheet surface background instead of raw `presentationDetents` arrays at call sites. Use `AppSheetScaffold` for reusable sheet layouts, `AppSheetOptionRow` for menu-style options, and `appSheetButtonStyle(...)` for consistent sheet button semantics. Prefer a dedicated preset/layout pair for dense action sheets when they need tighter row density than general compact dialogs, and avoid root-level `Spacer()`-driven layouts in compact sheets.
- **Keyboard dismissal**: Reuse the shared `keyboardDoneToolbar(...)` helper with `KeyboardDismissButton` for text-entry keyboards that need an explicit Done action instead of re-creating keyboard toolbar buttons per screen.
- **Integrations UI**: Keep integrations list cards as overview surfaces, not inline control panels. Shared card styling and structure should live under `Features/Integrations/Shared`, while provider-specific actions live in provider-owned manage sheets or detail surfaces.

---

## Coding Rules

### Specialized Skills
- `swiftui-pro` is required for SwiftUI code, layout, navigation, accessibility, animation, performance work, and SwiftUI-focused reviews.
- `swift-concurrency-pro` is required for actors, async/await, `Task`, cancellation, `Sendable`, isolation, and strict-concurrency fixes or reviews.
- `swiftdata-pro` is required for SwiftData models, relationships, predicates, queries, CloudKit sync constraints, and persistence reviews.
- `swift-testing-pro` is required for Swift Testing, async test patterns, unit/integration test work, and XCTest migration.
- `vibe-security` is required for Firebase Auth, Firestore rules, Cloud Functions, waitlist/signup endpoints, Strava OAuth, user data, secrets, tokens, privacy, subscriptions/payments, or any auth/authz/trust-boundary change.
- `firebase-basics` is required for Firebase project setup, CLI/configuration, emulator/local-environment work, and cross-product Firebase tasks.
- `firebase-auth-basics` is required for Firebase Authentication flows, providers, session handling, and auth-dependent access design.
- `firebase-firestore-standard` is required for Firestore collections, queries, indexes, sync design, and security rules.
- `firebase-hosting-basics` is required for `web/public`, hosting rewrites, preview channels, and Firebase Hosting deploy/configuration work.
- `healthkit` is required for Apple Health integration and workout or metrics import/export work.
- `widgetkit` is required for widgets, Live Activities, Dynamic Island, StandBy, and related extension/configuration work.
- `app-intents` is required for Shortcuts, Siri, Spotlight, widget intents, and Control Center actions.
- `ios-accessibility` is required for dedicated accessibility audits or remediation, alongside `swiftui-pro` when the UI is SwiftUI.
- `ios-security` is required for Keychain, biometrics, ATS, CryptoKit, privacy manifests, and device-side secret handling.
- `ios-networking` is required for `URLSession`, API clients, uploads/downloads, retry/caching, and network architecture.
- `storekit` is required for subscriptions, in-app purchases, paywalls, restore flows, and entitlement handling.
- `app-store-review` is required for App Store submission prep, ATT/privacy manifest work, IAP review readiness, and rejection-risk audits.
- `debugging-instruments` is required for crash triage, leak detection, hang diagnosis, and performance profiling.
- `asc-xcode-build` is required for archive/export/IPA build automation.
- `asc-release-flow`, `asc-metadata-sync`, `asc-submission-health`, and `asc-testflight-orchestration` are required for App Store Connect release, metadata, submission, and TestFlight tasks.
- If a task spans multiple domains, use every matching skill.
- If a request is ambiguous but clearly adjacent to one of these domains, load the relevant skill rather than skipping it.
- Keep this file focused on Ascend-specific rules. If a skill conflicts with this guide, follow this guide.

### Ascend-Specific Overrides
- **Targeting**: iOS 17.0+, Swift 6, strict concurrency. If a newer iOS API meaningfully improves a feature, mention it and gate it with `@available` rather than silently raising the baseline.
- **State management**: SwiftUI with `@Observable` for shared state, and mark shared `@Observable` classes with `@MainActor`.
- **Dependencies**: No third-party frameworks without asking first. Avoid UIKit unless requested.
- **Code hygiene**: Never commit API keys/secrets. If SwiftLint is installed, ensure no warnings or errors before committing.
- **Local style conventions**: Prefer `replacing("a", with: "b")`, `URL.documentsDirectory`, `url.appending(path:)`, `.formatted()` or `Text(..., format:)`, and `localizedStandardContains()` for user-facing filtering.
- **Testing approach**: Place view logic into view models or similar so it can be tested. Prefer unit tests for core logic; use UI tests only when unit tests are not possible.
- **SwiftData + CloudKit**: Never use `@Attribute(.unique)`, properties must have defaults or be optional, and all relationships must be optional.

---

## CI/CD & Deployment

### Branching Strategy
- `main` — production-ready code
- `develop` — integration branch and default base branch for feature/fix work
- `feature/*`, `fix/*`, `chore/*` — individual work, branch off `develop`, PR into `develop`

### Issue-First Workflow
- Resolve work to a GitHub issue before implementing code.
- If the user provides an issue number, use it.
- If no issue number is provided:
  - Search open issues for the best match.
  - If exactly one clear match exists, confirm it with the user.
  - If no clear match exists, propose creating a new issue and get approval before creating it.
- Do not start implementation until an issue is confirmed, unless the user explicitly asks to proceed without one.
- Branch naming should include the issue number:
  - `feature/issue-<number>-<short-slug>`
  - `fix/issue-<number>-<short-slug>`
  - `chore/issue-<number>-<short-slug>`
- PRs should target `develop` by default and include `Closes #<number>` in the PR body.

### Workflows
- `.github/workflows/ci.yml` runs on PRs to `develop`, verifies the iOS app builds with the `AscendApp-Staging` scheme using `CODE_SIGNING_ALLOWED=NO`, and runs the `AscendAppTests` suite on an iPhone simulator with `ENABLE_TESTABILITY=YES`.
- `.github/workflows/deploy-staging.yml` runs on pushes to `develop` and manual dispatch, and executes sequential jobs (stop on failure):
  1. Build iOS app (Staging scheme, produce IPA)
  2. Deploy Firebase Functions
  3. Deploy Firestore Rules
  4. Deploy Firestore Indexes
  5. Deploy Storage Rules
  6. Deploy Firebase Hosting
  7. Upload to TestFlight (last — hardest to reverse)
- `.github/workflows/deploy-production.yml` runs on pushes to `main` and manual dispatch. It mirrors the staging pipeline, including Firestore index deploys, with Release configuration and remains gated behind `PRODUCTION_READY=true` plus GitHub `production` environment protection.

### Deploy Authentication (OIDC)
- GitHub Actions deploys to Firebase must use OIDC + GCP Workload Identity Federation.
- Do not use long-lived Firebase/GCP JSON key secrets for CI deploy auth.
- Required staging secrets:
  - `GCP_WORKLOAD_IDENTITY_PROVIDER`
  - `GCP_SERVICE_ACCOUNT_EMAIL`
- Required production secrets:
  - `GCP_WORKLOAD_IDENTITY_PROVIDER_PRODUCTION`
  - `GCP_SERVICE_ACCOUNT_EMAIL_PRODUCTION`
- Deprecated for deploy auth:
  - `FIREBASE_SERVICE_ACCOUNT_STAGING`

### Fastlane
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

### Firebase Hosting
Website source lives in `web/` and is built to `web/dist/` before deploy.
- Waitlist form submissions must use `POST /api/join-waitlist` (Hosting rewrite to `joinWaitlist` Cloud Function), not direct Firestore client writes.
- Transactional emails for waitlist and future product triggers must be sent server-side from Cloud Functions, never directly from the website or iOS client.
- Cloud Functions email provider config lives in the `TRANSACTIONAL_EMAIL_CONFIG` Secret Manager JSON secret, with `functions/.secret.local` used only for local emulator overrides.
- `joinWaitlist` is idempotent by normalized email hash, enqueues the `waitlist_welcome` job into `email_jobs`, and rate limits public submissions using hashed requester IPs stored in `email_rate_limits`.
- Transactional emails are delivered in the background by the scheduled `processEmailJobs` worker; retries and failure state live on `email_jobs`, not on `waitlist`.
- In-app feedback submissions (`feedback` collection) trigger `onFeedbackCreated`, which sends an admin notification email directly via Resend (not queued). The recipient is `feedbackNotificationEmail` from the secret config (falls back to `replyTo` → `fromEmail`). Reply-to is set to the submitting user's email. Notification delivery metadata is written back onto the feedback document.

### Key Config Files
- `.firebaserc` — project aliases (dev, staging, prod)
- `firebase.json` — hosting, functions, firestore config
- `firestore.rules` — security rules
- `.github/workflows/ci.yml` — PR validation
- `.github/workflows/deploy-staging.yml` — staging deploy pipeline
- `.github/workflows/deploy-production.yml` — production deploy pipeline (gated)
- `Gemfile`, `fastlane/Appfile`, `fastlane/Fastfile`, `fastlane/Matchfile` — iOS build/signing/TestFlight automation
