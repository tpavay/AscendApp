# Ascend — Project Guide

## What Is Ascend
Ascend is a comprehensive stairstepper workout tracker for iOS. It serves the full spectrum of users — from someone who's never used a stairstepper to advanced athletes doing progressive overload with weighted vests. Users log workouts, track progress, earn Best Efforts, create routines, and compete on leaderboards.

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
│   ├── Services/               # WorkoutImportCoordinator, WorkoutService, WorkoutMutationHandler
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

### Internal QA Sign-In
- Internal QA sign-in exists only for **dev** and **staging** builds and must stay unavailable in production.
- Internal QA sign-in must create a real Firebase-authenticated user session (email/password in dev/staging), not a fake authenticated client state.
- Gate the feature by both build configuration and Firebase project ID so the UI only appears for `ascend-f2e4f` and `ascend-staging-fa7d5`.
- Local simulator/automation credentials should come from user-local scheme environment variables or other non-committed secrets sources such as `ASC_INTERNAL_QA_EMAIL` and `ASC_INTERNAL_QA_PASSWORD`.
- XcodeBuildMCP simulator automation should inject `ASC_INTERNAL_QA_EMAIL` and `ASC_INTERNAL_QA_PASSWORD` through `session_set_defaults(env: ...)` or `launch_app_sim(env: ...)` instead of relying on user-local Xcode scheme environment inheritance.
- Do not persist Internal QA credentials in repo-local `.xcodebuildmcp/config.yaml`; keep them in user-local scheme settings or pass them into the MCP session at runtime.
- Never commit QA credentials, never bundle them into production builds, and never use the internal QA path to bypass Firestore/Storage/Auth server enforcement.

### Data Models (SwiftData)
Workout, WorkoutSourceLink, WorkoutParticipation, LeaderboardStats, Routine, RoutineFolder, ClimbAttempt, PendingMediaUpload, PendingWorkoutDeletion

### Best Efforts Architecture
- Best Efforts are the only workout achievement layer. Do not reintroduce a parallel Personal Records system.
- Workouts remain the source of truth. Best Efforts are derived from workout history for all-time and this-year scopes across all, bodyweight, weighted, and exact weight-loadout contexts.
- Weighted Best Efforts must distinguish exact loadouts using the full enabled equipment configuration, such as `20 lb Vest` versus `20 lb Vest + 5 lb each Ankle`.
- Best Effort metrics are stepper-specific and step-first: most steps, longest climb, highest average SPM, sampled time windows, and sampled fastest step targets. Do not add floors-based Best Efforts unless product explicitly changes direction.
- Timeline efforts require real sampled Live Climb progress data. Manual entries and total-only imports can contribute whole-workout efforts, but not rolling-window or fastest-segment efforts.
- Progress Best Efforts should default to a record-book overview, not a filter-heavy dashboard: show each available metric once with its current all-time best value and date, then open a dedicated metric detail screen on tap.
- Best Efforts overview rows should stay table-like and low-noise: no per-row trophy icons or chevrons, metric title/date on the left, compact unitless value on the right when the unit is already implied by the title.
- Metric detail screens should show the rank-1 laurel/wreath hero, a polished record progression chart, and record-setting history. The detail segmented control should only expose `Chart` and `History`; do not add a separate `Workout` tab. The chart card may use `Record Progression` plus a short metric-specific subtitle, but should avoid redundant generic titles like `Progression`; style it as a premium dark neon chart with a subtle accent area gradient, clean grid, no clutter from every point marker, a filled accent selected point, and a compact date/value callout on tap or drag. The history list should omit the current rank-1 record because it is already the hero, start at rank 2, use rank numbers without circular badges or trophy icons, avoid SPM subtitles, and navigate to the associated workout when a row is tapped. The detail hero should rely on the navigation title for metric context: keep the wreath area focused on the record value, centered inside the wreath, with comparison/date below, and do not repeat SPM or the metric title inside the wreath. Treat the detail hero as an integrated page header on the normal page background, without a heavy rounded card shell or gold gradient block. The segmented control and content cards should retain comfortable horizontal insets instead of spanning edge to edge.
- Progress surfaces that preview Best Efforts should use a single premium featured-record card, not a mini list. Feature the newest current Best Effort, keep the whole card tappable, put the record value directly under the `Best Efforts` title, and keep preview metadata sparse: record name plus date only. Do not add `View All`, chevrons, trophy buttons, or count-chip clutter unless product explicitly asks for them.
- Trends should answer whether training volume, pace, consistency, and time are changing compared with the previous matching period. Keep the surface insight-first: show a period pulse/summary and one selectable chart at a time, not a stack of every possible metric chart. Heart rate is contextual when available, not required for the core trend value.
- Reserve full achievement sentences, such as `2nd fastest 3,000 steps all-time`, for workout list, workout summary/detail, Live Climb completion, and share surfaces where the effort appears out of record-category context.
- Workout detail, Live Climb completion, share cards, and progress surfaces should display Best Efforts only.

### Firebase Storage Pathing + Rules
- User-generated media must be stored under user-scoped prefixes:
  - `users/{uid}/photos/...`
  - `users/{uid}/videos/...`
  - `users/{uid}/profile_pictures/...`
  - `users/{uid}/workout_heart_rate/...`
- Never write user media to shared root paths (`photos/`, `videos/`, `profile_pictures/`) in production.
- Server-owned synthetic Live Replay avatar fixtures may live under `live-replay-avatars/{seedPackId}/...`; they are not user media, should be read-only to clients, and must be written only by admin/server tooling.
- Legacy share card template assets may still live under `share-card-templates/...`, but workout share cards in v1 must not fetch their backgrounds or layout config from Firebase.
- Account deletion and cleanup should target only the authenticated user's scoped prefixes, including durable workout heart-rate sidecars and private workout backup documents.

### Workout Durability Architecture
- Canonical private workout backups live at `users/{uid}/workouts/{workoutId}`. These documents are the durable backend record for private workout metadata, while `Workout` in SwiftData remains the local-first cache and editing surface.
- Workout document IDs should use the workout's stable UUID string. Heart-rate sidecars must use the matching Storage path `users/{uid}/workout_heart_rate/{workoutId}.json.gz` so cleanup and repair flows can derive both resources from the same identity.
- `WorkoutRemoteRepository` owns Firestore upserts/deletes for the canonical workout document, and `WorkoutHeartRateStorageRepository` owns the gzip-compressed heart-rate sidecar upload/delete path.
- Full heart-rate chart samples should not be embedded directly in Firestore workout documents. Store the full series as a Storage sidecar and keep only pointer/metadata fields in Firestore, alongside summary values like average and max heart rate.
- A workout that includes heart-rate series data is not fully synced until both the Storage sidecar upload and Firestore workout document upsert succeed.
- Local workout sync state lives on `Workout` itself (`ownerUserId`, last-modified timestamp, last-remote-sync timestamp, last remote heart-rate sidecar path, sync status, and last sync error) so the app can track pending remote backup work without changing the current local-first UX.
- Existing on-device workouts are backfilled once per signed-in user into that sync model. Phase 1 explicitly assumes one account per install for this backfill, so shared local workout history is not a supported multi-account scenario yet.
- Pending remote deletes are tracked locally in `PendingWorkoutDeletion` so delete/retry flows can become durable without overloading the canonical workout record.
- Workout backup is mutation-driven for create/edit/import flows. `WorkoutMutationHandler` persists the local sync-state changes and immediately kicks the remote coordinator after successful mutations instead of waiting for the user to relaunch the app.
- Background media uploads are part of the same durability contract. When `Workout.photos` or `highlightedPhotoId` changes after upload completion, the app should mark that workout pending and republish the private workout backup immediately.
- `WorkoutSyncCoordinator` is the single orchestrator for pending workout backup work. It currently runs both during authenticated bootstrap/foreground repair and from mutation-triggered flushes, processes pending workout deletions before pending upserts, uploads any required heart-rate sidecar before the Firestore upsert, and coalesces overlapping process requests so launch/auth/lifecycle hooks do not issue duplicate remote work for the same workout.
- Future public sharing or social features must not read directly from the private workout backup collection. Public posts/comments/likes should use separate public models.

### Workout Source + Context Architecture
- `Workout` is the canonical activity: what the user actually did, including date, duration, steps, floors, health metrics, notes, media, and source.
- `WorkoutSource` is the capture method. `headphone_motion` is the brand-agnostic source for compatible headphone motion tracking and displays as `Headphone Tracking`; it is verified, but it is not a `WorkoutProvider` because there is no external provider record to dedupe against.
- Headphone motion tracking should stay behind reusable shared services under `Shared/Services/HeadphoneMotion`: Core Motion adapts `CMDeviceMotion` into app-owned `HeadphoneMotionSample` values, while `HeadphoneMotionStepDetector` remains pure compute so the step algorithm is unit-testable without headphones or simulator hardware. Core Motion callbacks must terminate inside a non-actor runner; UI-facing observable services should receive value updates on `MainActor` and must not be captured directly by Core Motion handlers.
- `WorkoutProvider` + `WorkoutSourceLink` remain only for external provenance and dedupe records such as Apple Health and Hevy.
- Feature attribution belongs in `WorkoutParticipation`, not as feature-specific nullable fields on `Workout`. Use participation records for intentional routine template, local routine, climb attempt, challenge, group challenge, program session, and future achievement contexts.
- Built-in routine leaderboards should use `routine_template` participation with the stable built-in template ID. User-created or copied routines may use local `routine` participation for history, but they are not public-leaderboard eligible until a future shared routine identity exists.
- Live Climb participation is live-only in v1: only `headphone_motion` workouts created from the Live Climb flow may create `climb_attempt` participation or affect climb leaderboard eligibility. Manual logs, imports, and routine completions must not progress or complete Live Climbs.
- Passive climb-equivalent badges, profile achievements, lifetime milestones, and collections are interpretations derived from workouts. They should not be modeled as leaderboard-eligible participation unless product explicitly turns them into intentional challenge contexts.

### Workout Share Card Architecture
- Workout share cards in v1 use bundled poster background assets so the share surface renders instantly and offline.
- All workout share cards should render inside a shared rounded-square surface component; card-specific layout views should sit on top of that surface rather than reimplementing clipping, borders, or background handling.
- `WorkoutShareCardPreset`, `ShareCardType`, and `WorkoutShareCardComposer` own the preset-driven stat priority, typography tokens, surface/background config, and layout inputs for the rendered card.
- Shared decorative share-card elements, such as stat dividers, should live in reusable parameterized components rather than being embedded inside one card layout.
- `WorkoutShareCarouselView` remains the container surface. The default workout flow keeps the bundled poster available, and Live Climb completions may prepend a climb-specific square card when the saved workout resolves to climb metadata.
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

### Connectivity UX
- `NetworkConnectivityService` is the app-wide source of truth for immediate connected-vs-offline UX using `NWPathMonitor`.
- App-wide offline and back-online messaging should be owned by `MainTabView` as a slim conditional status row inside the custom tab bar chrome, so connectivity state appears in one consistent bottom-of-screen location without covering feature content.
- When connectivity drops, the custom tab bar should briefly emphasize the offline transition by tinting the full tab-bar chrome blue before settling back to the normal tab-bar background with the compact offline status text still visible.
- Use connectivity state to fail fast for user-initiated refreshes or uploads when there is no network path, instead of waiting for request timeouts to tell the user they are offline.
- Request-level failures and timeouts are still a separate concern. Features should keep their own timeout/error handling for slow connections, backend failures, or partial cached-data fallbacks.

### Import UX
- Workout import supports individual import, selected-batch import, and import-all from the same sheet.
- Import architecture uses one canonical `Workout` plus local `WorkoutSourceLink` provenance records per provider. New import UI and state should flow through `WorkoutImportCoordinator`, not provider-specific views/services.
- Workout totals must pass the shared `WorkoutPlausibilityPolicy` before manual save, edit, import, remote backup, and Best Efforts ranking. Keep implausible average-step-rate records out of new data, and independently ignore any legacy implausible rows in Best Efforts.
- Apple Health is read-only. First connect may backfill historical workouts, but routine checks must stay incremental and sample-only until a workout is actually imported.
- Apple Health heart-rate chart samples must expand condensed `HKQuantitySample` records using `HKQuantitySeriesSampleQuery` and save the individual quantities. Parent heart-rate samples may represent aggregate blocks and should only be used as a fallback when no series children are returned.
- Apple Health auto-import is optional and user-controlled from the Apple Health manage sheet.
- Auto-import only applies to newly finished Apple Health workouts from the moment the user enables it; older pending history remains in the manual review/import flow.
- If older local settings have auto-import enabled but no stored activation timestamp, use the previous successful HealthKit check as the conservative activation fallback so newly discovered workouts can import without opening older pending history.
- Auto-imported Apple Health workouts should use a single latest-unseen review model, not a backlog queue:
  - Home may surface one quick-edit review sheet for only the latest unseen auto-imported workout
  - if a newer unseen auto-import arrives before review is completed, it replaces the older unresolved review candidate
  - completing or deleting that review should advance the review watermark so older auto-imported workouts never surface one-by-one later
- The Home header bell is the primary import entry point, but it should not show a pointer-style coach mark.
- Existing users who already have Apple Health connected but have auto-import off should see a dismissible auto-import banner inside `WorkoutImportSheet` the next time they open imports; dismissal is one-time per user and should not reappear.
- `WorkoutImportSheet` should own Apple Health setup regardless of entry path using inline setup states, not a setup sheet layered on top of the import page. The bell and other manual review entry points should always open the import page rather than jumping straight into the auto-import review flow.
- While Apple Health still needs setup, suppress the generic `No New Workouts` empty state so setup remains the only focus.
- After Apple Health access is granted, enable auto-import by default and show inline guidance for where to change that later in Settings > Edit Profile > Integrations > Apple Health.
- The auto-import review screen is a cleanup pass on an already-saved workout, so it should use `Done` instead of `Save`, omit `Not Now`, open as a quick-edit sheet (about 75% height with expansion to large) that cannot be swiped away, allow edits to `title`, `notes`, `media`, `duration`, and `steps`, keep the imported workout date visible but read-only, and keep the destructive `Delete Workout` action inside the sheet content while suppressing re-import of that same Apple Health sample.
- HealthKit auto-import freshness should use HealthKit observer/background delivery when available, while keeping the existing launch/foreground incremental refresh as a fallback.
- HealthKit observer callbacks should only wake the import pipeline; the coordinator must serialize refreshes and fetch changes with an anchored query before completing observer delivery.

### Analytics Architecture
- `TelemetryManager` remains the app-facing facade, while reusable telemetry types and sinks live under `Shared/Services/Telemetry`.
- Feature analytics definitions should live in feature-owned `Analytics/` folders (for example `Features/Workouts/Analytics`) as typed `TelemetryEvent` / `TelemetryScreen` definitions.
- Feature code must not import Firebase directly for analytics or breadcrumbs. Route analytics through `TelemetryManager` and shared sinks only.
- Log product events from the owning view model, coordinator, manager, or service instead of scattering calls through leaf views. The main exception is SwiftUI screen tracking, which should use the shared `.analyticsScreen(...)` modifier.
- Keep analytics parameters low-cardinality and privacy-safe. Do not log raw user-entered text, email, DOB, exact location, exact health samples, or other high-sensitivity payloads.
- New analytics work should include focused tests using `InMemoryTelemetrySink` so event contracts can be verified without a Firebase runtime.
- DEBUG builds expose a Telemetry Console inside Debug Tools so recent events and screen views can be inspected locally when running with telemetry enabled.

### Live Climbs V1 Architecture
- `Live Climbs` is a 3-screen loop:
- `Home` is a stateful entry card and does **not** show the globe
- `Browse` owns the searchable globe experience
- `Climb Detail` is the primary climb destination
- Live Climb funnel analytics should use typed `LiveClimbAnalyticsEvent` values through `TelemetryManager`, not direct Firebase calls. Keep event parameters low-cardinality and privacy-safe, focusing on entry point, climb tier/category, coarse buckets, action state, completion outcome, and share surface.
- Browse should treat the globe and drawer as distinct navigation modes: tapping a globe pin opens a compact preview card, while tapping a search result, section card, or list row opens Climb Detail directly.
- Browse search lives inside the bottom drawer. Focusing search should expand the drawer above the keyboard, and collapsing the drawer should leave the globe available for visual exploration.
- Home should always show a concrete daily recommended Live Climb so the feature feels active and discoverable. Tapping the Home card opens that climb's detail screen.
- The recommended Home Live Climb should be persisted by local calendar day so it stays the same for the full day even if climb completion state changes.
- The Home daily climb card is fully tappable and should not include redundant in-card CTA text, chevrons, or browse-all copy.
- Hardware capability should not be surfaced as a warning on Home or Browse. Live Climb attempts still require compatible headphones with motion tracking, but that gate belongs at the actual start-live-attempt point.
- `Just Climb` is the open-ended live-tracked mode for users who want headphone-motion tracking without choosing a catalog climb. It should be reachable from the Add Workout flow, save a normal `headphone_motion` workout with `trackingMode=just_climb`, and must not create or progress a `ClimbAttempt`.
- Climb Detail should use a flippable climb card: the front shows the landmark image/name/location, and the back shows tier plus the fun fact. The tier step range belongs directly under the tier label; do not repeat climb steps/floors on the back because those already live below the card.
- Climb Detail should provide a compact top-right Phosphor `globe-hemisphere-west` action for browsing other climbs. Keep this icon standalone with an invisible tap target, not inside a visible circular/chip background. Do not put browse copy or browse buttons on the Home daily card.
- Climb Detail should explain headphone requirements through a compact persistent help icon, not an inline text box. Help copy should include a `Compatible Headphones` list, a subtle link to Apple's current compatibility page, and avoid extra "why" paragraphs or "preview the route" phrasing.
- Climb Detail should show Live Climb community state as one avatar/caption row, but the caption should only report the completed count (`0 completed`, `1 completed`, `{N} completed`). Do not show attempted/climber totals in the caption because completions are the meaningful public stat.
- In the Climb Detail community row, show up to 3 visible avatars without an overflow-count pill. If the current user has completed the climb, pin them first with an accent ring/glow; if they attempted but did not complete, pin them first with a dashed accent ring and subtle pulse.
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
- Manual entries, Apple Health imports, and routines must not complete or progress Live Climbs. Live Climb completions should come from the dedicated headphone-motion live attempt flow.
- Live Climb attempts should create a `headphone_motion` workout only after a live headphone-motion session stops with recorded steps. The workout should use the live session start time as `Workout.date`, store compact algorithm/session metadata in `sourceMetadata`, and flow through `ClimbService.apply(...)` plus `WorkoutMutationHandler` so climb progress, participations, leaderboards, Best Efforts, and remote backup stay on the normal mutation path.
- Apple Health can enrich a saved Live Climb workout with wearable metrics, but it must not become the canonical Live Climb source. Enrichment is automatic only for confident one-to-one matches between one unlinked `headphone_motion` Live Climb workout and one unlinked Apple Health stair/step workout; ambiguous matches must be skipped rather than guessed. Enrichment may add heart rate, calories, device metadata, `healthKitUUID`, and an Apple Health `WorkoutSourceLink`, while preserving the Live Climb workout's source, steps, floors, duration, rank/replay metadata, and attempt participation.
- Live Climb sessions should start a best-effort background execution helper alongside headphone motion: use iOS 26+ `HKWorkoutSession` with `UIBackgroundModes` `processing` when available, do not save HealthKit workouts or request new Health write permissions for this helper, and fall back to a short `UIApplication` background task on older OS versions.
- Saved Live Climb attempts are immutable competitive history in the app UI. Use the in-session discard action before saving if an attempt should not count; once saved, workout-log delete affordances should not remove the underlying attempt history.
- Completed Live Climb sessions should transition to a post-save summary before dismissal. The summary should use saved Live Climb step timeline metadata for adaptive pace-split rows, show workout vertical gain using the same step-height calculation as workout detail, and launch the existing workout share carousel with a Live Climb-specific card when climb metadata is available.
- Live replay leaderboards are context-agnostic under `Shared/Services/LiveReplayLeaderboard`. Live Climbs and future routine race views should use `LiveReplayLeaderboardContext`, `LiveReplaySplitSampler`, and `LiveReplayLeaderboardService` instead of cloning climb-specific comparison logic.
- Live replay leaderboard rank compares the live user's current steps against completed leaderboard-eligible attempts at the same elapsed-time bucket. Failed, abandoned, partial, or otherwise ineligible attempts must not publish into replay indexes, and tied completed attempts rank ahead of the current live user so a new attempt starts at the bottom of the completed field.
- Per-climb public replay contexts should contain at most one completed row per user. If a user has multiple completed attempts for the same climb, publish only that user's best eligible attempt into the replay index.
- The global Just Climb replay context is `just_climb__global`. It should be server-published from all completed leaderboard-eligible Live Climb attempts plus saved Just Climb sessions, keyed by workout ID so users can race against all completed attempts rather than one best row per user. Because Just Climb has no target, completed competitors should remain visible at their final step total in later replay buckets instead of disappearing after their own finish time.
- Post-completion summary and Live Climb share-card rank should be based on completion duration against completed bucket-zero replay entries, with `completedCount` as the denominator. Do not reuse the in-session time-window rank or total-climber count for completed share surfaces.
- Future demographic or peer-group insights for Live Climbs should be modeled intentionally from declared profile fields, such as age range, gender, weight range, or region, and should stay opt-in/privacy-safe rather than inferred from sensitive data.
- Live sessions should record compact source-neutral step timeline checkpoints locally at fixed intervals and store them with the saved source metadata. Hardware-specific producers, such as headphone motion or future wearable integrations, should emit cumulative step samples into the shared Live Climb recorder instead of making result/replay UI depend on one sensor source. The app should not write leaderboard split indexes from the client during a session; public replay windows are read-only client data and should be server-published from saved attempts.
- The server publisher should normalize saved replay split curves before writing public buckets. If a saved curve is degenerate, such as all zero progress until the final bucket, reconstruct a conservative monotonic curve from the final duration and steps rather than publishing a stationary-until-finish replay row.
- Replay leaderboard rows may denormalize public display fields (`displayName`, `avatarToken`, optional `photoURL`) so clients do not read private `users/{uid}` documents for profile data during live sessions.
- `functions/src/liveReplayLeaderboard.ts` owns the server publisher from private workout backups to `live_replay_leaderboards/{contextKey}/splitBuckets/{bucketIndex}/entries/{entryId}` plus the per-context `userBestAttempts` guard collection. Keep that index denormalized and small; do not make live-session client code write directly to it.
- During a live session, time, steps, progress, SPM, and other sensor stats must update locally every second without waiting on Firestore. The replay leaderboard may refresh a tiny window around the user every 5-10 seconds or on bucket changes, and stale/failed backend reads must not interrupt tracking. Clients should project fetched replay rows forward between backend reads using denormalized `finalSteps` plus completion duration or fallback pace so visible competitors do not appear frozen.
- The live attempt screen should make the replay leaderboard the primary surface: keep elapsed time in compact top chrome, show the climb's total target steps inline with the leaderboard heading, use the current user's row as the horizontal accent progress indicator with their profile photo when available, and keep pause/resume plus end-attempt controls compact at the bottom. Pre-start countdown should fully obscure the live UI until recording begins. Pausing should suspend headphone-motion updates and active duration until resumed.
- Live Climb sessions should publish a Live Activity/Dynamic Island through `LiveClimbActivityManager` while `LiveClimbSessionViewModel` remains the source of truth. Compact island surfaces should show current steps and live rank; expanded/long-press surfaces should show the climb name, location, remote climb image when available, rank, duration, steps, and AppIntent-driven pause/resume/stop controls. The widget extension must not read Firestore or write replay indexes directly.
- Non-`multiSession` climbs are one-live-attempt challenges. The live attempt must fully complete the climb or it becomes `failed`, stops being active immediately, and remains visible in climb history as an attempt rather than a completion.
- General workout entry surfaces should stay separate from Live Climbs because manual entries, imports, and routines cannot progress Live Climb attempts.
- General workout launcher copy should use `Add Workout` for the top-level action, then name the creation method inside the sheet (`Manual Entry`, `Start Routine`, `Import`) instead of mixing `start` and `log` verbs at multiple levels.
- Climb detail has 3 swipe pages:
  - `Overview` (real)
  - `Your History` (real)
  - `Leaderboard` (real; shows fastest completed attempts from the server-published replay index)
- Per-climb rank and total-climber counts must stay hidden until real backend data exists; do not show placeholder public stats.
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
- Persistent idle climb surfaces, such as the Home daily climb card, may use a lighter ambient `AnimatedClimbCardBorder` treatment with an unblurred moving highlight to reduce SwiftUI animation work while preserving visible rotating motion.

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
- All create/edit/delete/import flows that change workouts should run through `WorkoutDerivedDataService.recalculateAll(...)` so base level, effort values, percentile snapshots, Best Efforts inputs, and local leaderboard aggregates stay in sync.

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
  - `LiveSessionCountdownOverlay` and `LiveSessionTimelineView` for shared countdown and top timeline chrome used by routines and Live Climbs
  - `SegmentedProgressBar` for the thin full-width routine timeline
  - `LiveIntervalLevelPill` for the current level and optional non-standard step type
  - `StaircaseView` for the right-edge routine progress visualization
  - `LiveWorkoutControlButton` for skip, pause/resume, and stop controls
  - `WorkoutCompleteView` for the completion surface instead of embedding that UI directly in `ActiveRoutineView`
- The staircase is decorative only. It should stay accessibility-hidden, use app-defined colors (`.accent`, heatmap colors, named asset colors), and avoid ad hoc hex values inside feature views.

### Week Start + Leaderboard Windowing
- Ascend now uses a single app-wide Monday week start. The old user-configurable week-start preference and selection UI are removed.
- Per-week user-configurable numeric targets are intentionally out of scope. Do not reintroduce target cards, setup prompts, or CRUD unless product explicitly chooses that direction again.
- Home summaries should use Monday-based weeks in the relevant local timezone.
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
- Live replay leaderboard seed data must be Admin SDK/server-written into the read-only `live_replay_leaderboards` index, never client-written during a live session.
- `scripts/seed-live-replay-leaderboards.mjs` may write only to dev (`ascend-f2e4f`) or staging (`ascend-staging-fa7d5`) and must hard-refuse production or any unknown project; use environment-specific seed packs for repeatable active/warm Live Climb replay fixtures.
- Live replay seed entries must carry `isSynthetic`, `source`, and `seedPackId` so synthetic replay data can be filtered, cleared, or phased out later. Do not claim seeded replay rows are users climbing right now.
- Live replay seed data must not reuse the same synthetic profile name or photo within a climb. Duplicate profiles make the replay look like one person appears multiple times.
- Seeded replay curves should be calibrated from historical workout pace distributions when available. Apple Health-derived step counts should be conservatively reduced before shaping synthetic attempts because imported stair-stepper data can overestimate steps.

### Workout Seeding Policy (Debug)
- Debug Tools includes local SwiftData workout seeding presets for Simulator workflows (`App Store Screenshots`, `Quick Demo`).
- Seeded workout metadata is stored in `Workout.sourceMetadata` with `isTestData=true`, `seedSource="debug-tools"`, and `preset` for targeted cleanup.
- Workout seeding is idempotent for debug usage: seeding replaces existing debug-seeded workouts before inserting the new preset.
- Clearing seeded workouts must recalculate derived workout data and local leaderboard aggregates to keep derived data consistent.
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
