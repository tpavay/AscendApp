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
│   └── Firebase/               # GoogleService-Info-{Dev,Staging}.plist
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
- Share card template assets live under `share-card-templates/...` and are read-only from client apps.
- Account deletion and cleanup should target only the authenticated user's scoped prefix.

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

### Onboarding V2 (Issue #63)
- Root routing uses onboarding completion before normal auth/home flow.
- Onboarding sequence is: welcome, HealthKit permission, measurement system, base level, personal details (DOB + gender), body metrics (height + bodyweight), location permission, notifications permission, then mandatory auth.
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
- User preference `weekStartDay` is stored in `SettingsManager` (`Sunday` or `Monday`) and surfaced in account settings.
- Goals and home summaries should respect this preference (or a goal's locked week settings when applicable).
- Weekly leaderboard period identifiers currently derive from app-configured week start + current timezone.
- Product direction:
  - Use user week-start preference for personal UX (goal/home summaries).
  - For competitive/global leaderboards, prefer a canonical week window (single app-wide standard) to avoid fairness drift between users.
  - If canonical windows are adopted, keep personal week views separate from ranking windows.

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
- **Integrations UI**: Keep integrations list cards as overview surfaces, not inline control panels. Shared card styling and structure should live under `Features/Integrations/Shared`, while provider-specific actions live in provider-owned manage sheets or detail surfaces.

---

## Coding Rules

### Core
- **Swift 6 / strict concurrency** — assume strict concurrency rules are being applied
- **SwiftUI** with `@Observable` classes for shared state
- No third-party frameworks without asking first
- Avoid UIKit unless requested
- Never commit API keys/secrets
- If SwiftLint is installed, ensure no warnings or errors before committing

### Swift Patterns

**Do ✅**
- Mark `@Observable` classes with `@MainActor`
- Use `async/await` for all concurrency
- Prefer Swift-native alternatives to Foundation methods: `replacing("a", with: "b")` not `replacingOccurrences(of:with:)`
- Prefer modern Foundation API: `URL.documentsDirectory`, `url.appending(path:)`
- Prefer static member lookup over struct instances: `.circle` not `Circle()`, `.borderedProminent` not `BorderedProminentButtonStyle()`, `.plain` not `PlainButtonStyle()`
- `Text(value, format: .number.precision(.fractionLength(2)))` — never C-style `String(format:)`
- `localizedStandardContains()` for filtering user input (not `contains()`)

**Don't ❌**
- `DispatchQueue` — use `@MainActor`, `MainActor.run`, or `Task.sleep(for:)`
- Force unwraps/try unless truly unrecoverable
- `String(format: "%.2f", value)` — use `.formatted()` or `Text` format
- Old FileManager document paths
- String concatenation for URLs

### SwiftUI Patterns

**Use ✅**
- `@Observable` (not `ObservableObject`), `@State` (not `@StateObject`), `@Environment(Foo.self)` (not `@EnvironmentObject`)
- `@Bindable var foo` when needing `$foo.property` bindings
- `NavigationStack` with `navigationDestination(for:)` for type-based navigation (not `NavigationView`)
- `Tab` API (not `tabItem()`)
- `foregroundStyle()` (not `foregroundColor()`)
- `clipShape(.rect(cornerRadius:))` (not `.cornerRadius()`)
- `Task.sleep(for:)` (not `Task.sleep(nanoseconds:)`)
- `Button` for taps (not `onTapGesture` — unless you need tap location or count)
- `bold()` (not `fontWeight(.bold)`) — only use `fontWeight()` with good reason
- `.scrollIndicators(.hidden)` (not `showsIndicators: false`)
- `onChange()` with 2 parameters or none (not 1-parameter variant)
- `containerRelativeFrame()` or `visualEffect()` over `GeometryReader` when possible
- `ImageRenderer` over `UIGraphicsImageRenderer` for rendering SwiftUI views
- `ForEach(x.enumerated(), id: \.element.id)` — don't wrap in `Array()` first
- `Button("Label", systemImage: "icon", action: fn)` — always include text with image buttons

**Avoid ❌**
- `UIScreen.main.bounds` for sizing
- Computed properties for sub-views — extract to separate `View` structs
- `AnyView` unless absolutely required
- UIKit colors in SwiftUI
- Hard-coded values for padding and stack spacing unless specifically requested
- Hard-coded font sizes — prefer Dynamic Type

### Testability
- Place view logic into view models or similar so it can be tested
- Write unit tests for core application logic
- Only write UI tests if unit tests are not possible

### SwiftData + CloudKit
If using CloudKit sync: never use `@Attribute(.unique)`, properties must have defaults or be optional, all relationships must be optional.

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
- `.github/workflows/ci.yml` runs on PRs to `develop` and verifies the iOS app builds with the `AscendApp-Staging` scheme using `CODE_SIGNING_ALLOWED=NO`.
- `.github/workflows/deploy-staging.yml` runs on pushes to `develop` and manual dispatch, and executes sequential jobs (stop on failure):
  1. Build iOS app (Staging scheme, produce IPA)
  2. Deploy Firebase Functions
  3. Deploy Firestore Rules
  4. Deploy Firestore Indexes
  5. Deploy Firebase Hosting
  6. Upload to TestFlight (last — hardest to reverse)
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

### Key Config Files
- `.firebaserc` — project aliases (dev, staging, prod)
- `firebase.json` — hosting, functions, firestore config
- `firestore.rules` — security rules
- `.github/workflows/ci.yml` — PR validation
- `.github/workflows/deploy-staging.yml` — staging deploy pipeline
- `.github/workflows/deploy-production.yml` — production deploy pipeline (gated)
- `Gemfile`, `fastlane/Appfile`, `fastlane/Fastfile`, `fastlane/Matchfile` — iOS build/signing/TestFlight automation
