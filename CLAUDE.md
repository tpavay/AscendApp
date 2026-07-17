# Ascend — Project Guide

## What Is Ascend
Ascend is a competitive stair stepper companion for iOS. It's built for people who already use the stair stepper (or are about to start) and want their work to count. Users race the world up real landmarks, top per-climb leaderboards, log every session, and watch their progress compound over time. The leaderboard is the conversation.

**Solo dev + AI assisted** (Tyler Pavay). Planned monetization (not yet built): hard paywall, no freemium tier. Two subscription paths — a yearly plan (discounted, includes a free trial that extends as the user completes climbs) and a shorter recurring plan (monthly or weekly — TBD) for users who want to pay as they go.

---

## What Ascend Is NOT

Defining the niche by exclusion. Use this as a check when adding features, screens, or copy:

- **Not for users who don't care about the stair stepper.** If a feature serves "any fitness user," it probably doesn't belong here.
- **Not a social fitness network.** No social feed, no follower model, no kudos. Interaction with other users happens *on the climb* (leaderboards, racing against past attempts), not on a social timeline.
- **Not a generic fitness tracker.** Don't drift toward "every workout, any activity." Activity scope is stair stepper sessions.
- **Not weight-lifting / strength-training focused.** Weighted-vest tracking exists to honor stair-stepper users who add load, not to become a strength app.
- **Not a passive tracker.** Every session is competitive context — pushing for PRs, climbing leaderboards, chasing First Ascents.

---

## Brand Voice

Voice is niche-aggressive and declarative — confident about who Ascend is for, willing to lose readers who aren't the target. The user already chose to be here; the copy doesn't beg.

Principles:
- **Active verbs at the front.** *Climb. Race. Rank. Push. Track.* Avoid "explore" / "discover" / "learn" as openers — too passive.
- **Imperative over invitational.** *Be the first* beats *You could be the first*. *Climb past them* beats *You may want to try*.
- **No hedging.** Cut "maybe," "perhaps," "if you'd like," "feel free to."
- **Specific over abstract.** Name landmarks, name verbs, name numbers when they're earned. Concrete words land harder than generic ones.
- **Assume the user is serious.** Don't explain stair stepping. Don't soften "race." Don't add tutorial scaffolding to copy that should land in one read.
- **The dare beats the invite.** Empty states, first-action prompts, and first-time experiences should *dare* the user, not coax them.

**Empty-state copy pattern: state-then-action.** State the current condition, then issue an imperative call to action. Two short sentences. The state contextualizes the action; the action drives behavior. Don't ship empty states that are descriptive-only — every empty state is an activation moment. When designing or writing an empty state, consult the `product-design-playbook` skill's Empty States play for the underlying framework.

---

## Project Context File (All AI Providers)
- `CLAUDE.md` is the canonical project context file. `AGENTS.md` is a symlink to `CLAUDE.md` — editing one edits both. There is exactly one source of truth.
- All AI providers used on this repo (Codex, Claude, Cursor, Copilot, etc.) should read from this file. Do not break the symlink by replacing `AGENTS.md` with a separate file or duplicating content between them.

---

## Tech Stack
- **iOS 17.0+**, Swift 6, SwiftUI (when a newer iOS API would meaningfully improve a feature being discussed, mention it so the developer can decide whether to use an `@available` check — don't silently use only the older API)
- **Data**: Local-first with cloud sync — SwiftData on device, Firebase Firestore for backup/sync/sharing
- **Backend**: Firebase (Auth, Firestore, Storage, Cloud Functions, Hosting, Analytics, Crashlytics)
- **Subscriptions / Paywall**: RevenueCat for subscription management and entitlements; SuperWall for paywall presentation and onboarding/conversion analytics
- **Integrations**: Apple HealthKit, Hevy
- **Cloud Functions** (TypeScript): Beehiiv-backed waitlist signup endpoint with dedupe, transactional email for server-owned notifications

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
│   └── Managers/               # ThemeManager, SettingsManager
web/public/                     # Firebase-hosted website (landing page, privacy policy)
functions/src/                  # Cloud Functions (TypeScript)
```

### Tab Architecture
- Only the active tab should be mounted and running expensive work (SwiftData queries, refreshes, animations). Hidden tabs are deliberately inert. Switching tabs is allowed to lose per-tab navigation/scroll state — the lifecycle benefit outweighs that polish loss for now.

### Branding
- Use the angular Ascend `A` mark for in-app and launch-screen branding. The internal logo asset is `AppIconInternalAccent`; do not reintroduce the legacy stair-stepper logo for app branding surfaces.
- When displaying the word "Ascend" as part of app UI branding (top chrome, splash, onboarding, auth), use the integrated wordmark where the angular A mark serves as the letter A — not the A icon placed next to a separate "ASCEND" text label. The shared `AscendWordmark` component is the canonical implementation; reuse it rather than reinstating logo + text combos.
- The unauthenticated landing screen uses the bundled `OnboardingWelcomeBackground` asset with readability overlays. Keep a bundled image as the primary background — do not replace it with a generated gradient.
- Shared onboarding screens should use `OnboardingScaffold` for consistent top-left chevron-only back-button placement and bottom action layout.
- The unauthenticated auth screen should stay background-first, using `AuthStaircaseBackground`, the angular Ascend `A` mark, Apple/Google provider buttons, and inline links to `https://ascendstepper.com/terms` and `https://ascendstepper.com/privacy`.

### Onboarding
- Post-auth onboarding must collect the required profile fields before the user reaches the main app: display name plus declared demographics when that stage is enabled. Age stays bounded from 13 through 120, and gender uses the `ProfileGender` raw values.
- Smart-default first-climb recommendations should come from the user's declared behavioral baseline: easier starters for new stair-stepper users, larger landmarks for regulars and serious athletes. Defaults route to the climb detail screen, not directly into a live attempt.
- Notifications opt-in should be anchored to a concrete value prop: never miss a climb drop. Do not ask for notification permission as generic setup housekeeping.
- Notifications opt-in is the gateway to First Ascent opportunity. Climbers with notifications enabled receive 24-hour advance notice of new climb drops, giving them a fair shot to claim the FA at unlock.

### Environments
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

### Internal QA Sign-In
- Internal QA sign-in exists only for **dev** and **staging** builds and must stay unavailable in production.
- Internal QA sign-in must create a real Firebase-authenticated user session (email/password in dev/staging), not a fake authenticated client state.
- Gate the feature by both build configuration and Firebase project ID so the UI only appears for `ascend-f2e4f` and `ascend-staging-fa7d5`.
- Local simulator/automation credentials should come from user-local scheme environment variables or other non-committed secrets sources such as `ASC_INTERNAL_QA_EMAIL` and `ASC_INTERNAL_QA_PASSWORD`.
- XcodeBuildMCP simulator automation should inject `ASC_INTERNAL_QA_EMAIL` and `ASC_INTERNAL_QA_PASSWORD` through `session_set_defaults(env: ...)` or `launch_app_sim(env: ...)` instead of relying on user-local Xcode scheme environment inheritance.
- Do not persist Internal QA credentials in repo-local `.xcodebuildmcp/config.yaml`; keep them in user-local scheme settings or pass them into the MCP session at runtime.
- Never commit QA credentials, never bundle them into production builds, and never use the internal QA path to bypass Firestore/Storage/Auth server enforcement.

### Best Efforts Architecture

**Achievement model**
- Workouts are the source of truth. Best Efforts are *derived* data — recomputed from workout history, never authored directly.
- Best Effort metrics are stepper-specific and step-first: most steps, longest climb, highest average SPM, sampled time windows, fastest step targets. Don't add floors-based Best Efforts unless product explicitly changes direction.
- Weighted Best Efforts split by exact loadout (e.g. `20 lb Vest` is a different record than `20 lb Vest + 5 lb each Ankle`). Different load configurations = different records.
- Timeline-segment efforts (rolling-window, fastest-segment) require real sampled progress data from Live Climbs. Manual entries and total-only imports contribute *whole-workout* efforts but never segment efforts.

**Caching**
- Best Effort rankings are persisted as a derived cache. Views read cheap cache lookups; they don't recompute rankings from raw workouts inside `body`. The cache is rebuilt after workout mutations (create / edit / delete / import) and during startup if the persisted signature is stale.

**Display direction**
- Progress surfaces show Best Efforts as a **record book**, not a dashboard. Each metric appears once with its current best; depth (progression chart, history) lives on the per-metric detail screen. Don't ship filter-heavy comparison surfaces as the default.
- Trend surfaces are insight-first: compare volume / pace / consistency / time against the previous matching period. Show one chart at a time, not a stack of every possible metric.
- Reserve full achievement sentences (e.g. *"2nd fastest 3,000 steps all-time"*) for surfaces where the effort appears out of record-category context — workout list, workout summary, Live Climb completion, share cards.

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

Local-first with cloud backup. SwiftData is the editing surface and source of truth for in-flight UX; Firestore + Storage carry durable backups so a user's history survives reinstalls and crosses devices.

**Identity and storage**
- Each workout has *one* durable identity — a stable UUID shared across the local `Workout`, its Firestore document at `users/{uid}/workouts/{workoutId}`, its heart-rate sidecar in Storage, and any associated media. One identity = cleanup and repair flows can act on all resources at once.
- Firestore stores the workout's metadata and summary fields (averages, max HR, totals). Large time-series data (heart-rate samples) goes to Storage as a compressed sidecar — never embedded in Firestore documents. Firestore holds only pointers and summaries.
- A workout is *fully synced* only when every component (Firestore document + Storage sidecar + media uploads) has succeeded. Partial success is not success.

**Sync state**
- Per-workout sync state (owner, last-modified, last-synced, status, last error) lives *on the local `Workout` itself*, not in a separate sync queue. This preserves the local-first UX while keeping pending remote work tracked.
- Pending remote deletes are tracked on a separate model so the canonical workout record isn't burdened with retry / deletion state.

**Orchestration**
- A single sync coordinator owns all pending remote work. Mutations don't write to Firestore directly — they update local sync state and kick the coordinator.
- Backup is mutation-driven (immediate after each mutation), not deferred to next launch. The coordinator also runs on authenticated bootstrap and foreground repair to recover missed or failed work.
- Ordering: deletes before upserts; Storage sidecars before the Firestore document that references them; overlapping requests coalesced so launch / auth / lifecycle hooks don't produce duplicate remote work.
- Media uploads are part of the durability contract. When media changes after upload completion, the workout is re-marked pending and the backup is republished.

**Boundaries**
- Private workout backups are *private*. Future public sharing, posts, comments, or likes must use *separate public data models* — they don't read private workout documents directly. The privacy boundary is data-model separation, not just security rules.
- Multi-account-on-same-device is not yet supported. Local workout history assumes one user per install; shared local history across accounts is out of scope until intentionally designed.

### Workout Source + Context Architecture

Three distinct concepts. Keep them cleanly separated — don't fold feature-specific data onto the canonical `Workout`.

**`Workout` is the canonical activity** — what the user actually did (date, duration, steps, floors, health metrics, notes, media). It carries enough to describe the session itself, but no feature-specific attribution.

**Source = how the data was captured.** In-app sensor capture (headphone motion, future wearables), external provider imports (Apple Health, future third parties), and manual entry are each their own source kind. Verified-sensor sources are first-class; they aren't external providers because there's no external record to dedupe against. External-provider dedupe + provenance metadata lives on a separate provenance type, never on `Workout` itself.

**Participation = why the workout exists / what it counts toward.** Feature-specific attribution (climb attempt, routine, challenge, future contexts) lives on a separate participation type, never as nullable fields on `Workout`. New features add new participation kinds; they don't add nullable columns to the canonical type. This is the open/closed principle applied to the workout schema.

**Integrity rules**
- Sensor capture (headphone motion, future wearables) lives behind a shared service layer. The step / progress algorithm is pure compute — unit-testable without hardware. Sensor callbacks must run safely off the main thread; UI updates marshal back to main explicitly.
- Live Climb completions require *live* sensor data from the live attempt flow. Manual entries, external imports, and routine completions cannot progress or complete a Live Climb. Live Climb eligibility is a quality gate, not a backfill.
- Passive interpretations of workout history (lifetime step milestones, climb-equivalent badges, collection counts) are *derived* readings — never participation records. They don't make a workout retroactively eligible for any leaderboard.

### Share Composer Architecture

Sharing in Ascend is a **user-composed canvas**, not a gallery of pre-designed cards. The user picks a background (their own photo/video or a preset), then drops stat "stickers" onto it and arranges them freely — the Instagram Story editor model. This replaces the older "carousel of fixed share-card variants" approach. Every share surface in the app (workout detail, Live Climb completion summary, manual log, Apple Health import) routes into the same composer.

**The two composable inputs — keep them independent**
- **Background** = what fills the canvas. Sources: the user's Camera Roll (photo or video) or a bundled/known **preset**. For a Live Climb, the climb's bespoke share card becomes one of the presets — it's no longer a parallel share path. Backgrounds and stats are decoupled: a background is just a backing layer, never bundled with baked-in stats.
- **Stat stickers** = draggable overlays the user adds on top. Each sticker is one stat (Steps, Duration, Calories, Avg SPM, Heart Rate, Climb Rank/"Nth finisher", Climb Name, Date, etc.) rendered in a chosen visual style. The user adds as many as they want, in any arrangement.

**Composer interaction model**
- Each sticker supports simultaneous pan / pinch-scale / rotate via composed SwiftUI gestures. Drag-to-bottom reveals a trash zone; release over it deletes the sticker.
- Alignment: center + edge snap guides (V1). Full Instagram-grade snapping (third-lines, between-sticker magnetism) is deferred.
- **Editing is SwiftUI-over-player; export is the only AVFoundation work.** While composing, the canvas is a SwiftUI `ZStack` of the background (an `Image` or an `AVPlayer`-backed video) with draggable sticker views on top — no composition happens during editing. Composition runs ONCE at save/share time.

**Stat sticker discipline (content-driven, mirrors the rest of the app)**
- Stat stickers are typed, parameterized values — NOT per-stat bespoke layouts. A sticker is `(stat kind, visual style, transform)`. Adding a new stat is data (a new kind + how to read it from the workout/climb), not a new code path. Adding a new visual style is one reusable styled view that any stat can use.
- Stat values are read from the canonical `Workout` (and, for climbs, the attempt/leaderboard data) — never recomputed or stored on a share model. The composer reads derived values it trusts to be current.
- Low-cardinality, privacy-safe: stickers display the same measured/derived metrics the rest of the app shows. No raw PII, no exact location.

**Export pipeline**
- **Photo background**: composite background + rendered sticker views into a single image (`ImageRenderer` for the stickers, drawn onto the background) → save to Photos / share.
- **Video background**: burn the rendered sticker layers onto the video via `AVVideoCompositionCoreAnimationTool` + `AVAssetExportSession`. This is the hard, isolated piece — it only runs at export, and the editing UI is shared with the photo path. Build photo export first; video export slots in as a branch at the export step.
- Export targets: Save to Photos and a dedicated Instagram Story share (`instagram-stories://` URL scheme) with a generic share-sheet fallback.

**Boundaries**
- Photos library permission is requested at first share (point of use), never in onboarding.
- Backgrounds/presets/sticker styles are bundled or locally composed — NOT server-rendered. Don't reintroduce backend-driven share backgrounds or remote-configured stat layouts.
- The Live Climb completion summary stays as the emotional payoff; its Share button opens the composer (with the climb's card available as a preset). The composer never replaces the summary screen itself.

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

### Profile Demographics
- Post-auth onboarding captures display name and declared demographics on `users/{uid}`. Age must stay a bounded integer from 13 through 120, and gender must use the `ProfileGender` raw values: `woman`, `man`, `non_binary`, or `prefer_not_to_say`.
- Profile demographics for V1 are public by default with no per-field opt-out: age, gender, body weight, country/region, and joined date may appear on profiles and leaderboard-adjacent surfaces. Email and authentication/provider data remain private.
- Firestore does not support field-level read masking on a document. Keep `users/{uid}` owner-readable because it contains private account fields, and mirror only public-safe profile fields into public profile documents/subcollections for other-user profile reads.

### Profile Architecture
- Profile has two display modes: `OwnProfileView` and `OtherUserProfileView`. Own profile keeps empty sections visible as activation moments; other-user profile hides empty sections entirely unless a comparison state needs to explain why comparison is unavailable.
- The profile tab entry point remains `ProfileView`, but it should delegate to the own-profile surface rather than owning all profile layout and business logic directly.
- Profile sections render in this order: identity hero, other-user comparison, Active Standings, Activity + Streak, Collection, Achievements, First Ascents, Records, Trends, Recent Workouts.
- Active Standings stays above Activity because active competition is more urgent than long-arc history. First Ascents stay above Records because permanent competitive prestige is more aspirational than personal records. Trends sit between Records and Recent Workouts.
- Collection on Profile is a 3-card preview, never the full Pokedex. Card composition adapts to claimed climbs: 0 claimed shows 3 recommended unclaimed; 1 claimed shows 1 claimed + 2 recommended unclaimed; 2 claimed shows 2 claimed + 1 recommended unclaimed; 3+ claimed shows the 3 most recent claimed.
- Claimed climbs retain the Climb action. A small checkmark badge overlay on the thumbnail signals claimed state; the action button is never replaced or hidden by completion.
- Recommended unclaimed Collection cards sort by tier ascending, then step count ascending, and exclude climbs the user has already claimed. The full collection grid lives behind the `View all` link as a separate page.
- Public profile reads must use public-safe documents/subcollections such as public profile, cached profile stats, achievements, and public workout summaries. Never read private workout backups to render another user's profile.
- Business logic for profile section visibility, achievement counting, ranking subtitles, comparison state, and stat derivation belongs in models/services that can be unit tested without a SwiftUI view tree.

### Firestore Schema-Change Rule
- `firestore.rules` uses strict `hasOnly` + `hasAll` field validation on every collection. Adding, removing, or renaming a field in the app **requires a matching update to `firestore.rules`** — otherwise writes will be rejected at the server.
- The same `firestore.rules` file must be deployed to all environments (dev, staging, production) to catch schema mismatches early. Never test against loose rules in dev while production has strict ones.
- When changing Firestore document schemas, always update in this order:
  1. Update `firestore.rules` to allow the new/changed fields
  2. Update Swift model + write logic
  3. Deploy rules to all environments before or alongside the app update

### Connectivity UX
- Connectivity is an app-wide concern with a single source of truth — features must not each implement their own offline detection.
- Surface connectivity state in one consistent, persistent location (not feature-by-feature banners or alerts). When the user is offline, they should know it without having to discover it through failed actions.
- Fail fast on user-initiated network actions when there is no network path — don't wait for request timeouts to tell the user they're offline.
- Connectivity is *not* the same as request success. Online requests can still time out, hit backend errors, or return partial data. Features decide the user-facing response (retry button, cache fallback, error message), but the mechanics — timeout policy, retry logic, error categorization — belong in shared request infrastructure. If you find yourself implementing the same network error pattern in a second feature, extract it into the shared layer rather than duplicating it.

### Import UX

External workout imports exist because Ascend partly serves as a logger — alongside the two in-app workout origins (Live Climbs captured via headphone motion, and manual entries typed by the user), users may want to bring in Apple Health stair workouts or future wearable data. The principles below govern how external data enters the system safely. The first subsection's data-integrity rules apply to *all* workout origins, not just imports.

**Data integrity (applies to all workout origins)**
- A single canonical `Workout` is the only persisted form. Every origin — manual entry, headphone-motion Live Climbs, Apple Health imports, future wearables — converges to it. Source-specific provenance is recorded on a separate provenance type, never as fields on the workout itself.
- All *external imports* flow through a single import facade. Provider-specific code lives behind that facade; UI and downstream code never speak directly to a provider. (Manual entry and Live Climb capture have their own in-app creation paths — they don't go through the import facade.)
- Plausibility validation runs at the entry boundary — bad data (implausible step rates, impossible durations) never enters the canonical store. The gate is the same for manual save, edit, external import, and Live Climb completion.

**External health sources (e.g. Apple Health)**
- External health data is read-only. Never write back to the source platform.
- Apple Health permission grant doubles as auto-import opt-in: when the user grants access, auto-import turns on automatically, with clear inline guidance about how to disable it later. We never sync without permission, but we treat granted permission as "the user wants their new workouts to flow in."
- An activation timestamp is recorded at the moment auto-import turns on (i.e., when the user grants permission). Only workouts finished *after* that moment flow in automatically. Pre-existing history stays in the manual review flow until the user explicitly imports it — granting permission shouldn't dump weeks of old data on them.
- Auto-imported workouts use a **latest-unseen review model**, never a backlog queue. Surface only the newest unseen workout for review; if a newer one arrives mid-review, replace; advance the watermark when review completes so older ones never resurface.
- Auto-import setup is handled inline in the import flow — don't require the user to navigate to settings to set up a provider for the first time.
- Apple Health workouts that enrich an existing Live Climb (per the enrichment rules in Live Climbs V1) **do not** surface in the review flow or in the manual import list — regardless of auto-import setting. Enrichment is silent; the user is never asked to confirm imported data on a Live Climb.

**Review semantics**
- Reviewing an auto-imported workout is a *cleanup pass on an already-saved record* — semantically distinct from creating a new workout. UI affordances (button labels, dismiss behavior) should reflect that the workout already exists.
- The review surface exists to fix bad step counts on workouts imported from external wearables (Apple Watch step data is frequently wrong for stair-stepper use) and to let the user add notes / media to the imported record. It does not apply to Live Climbs — those have accurate in-app step counts and gather notes / media at the completion summary, not via review.

**Background freshness**
- Prefer system-provided background delivery (e.g. HealthKit observers) when available; fall back to launch/foreground incremental refresh.
- Observer callbacks must be serialized through the import facade — a callback wakes the pipeline; the pipeline owns the actual fetch.

### Analytics Architecture

**What analytics is for**
- **Funnel measurement** — where users drop off between acquisition → activation → trial start → paid subscription → renewal. This drives the business decisions.
- **Engagement** — session count, climb completions, leaderboard interactions, return rate (Day 1 / Day 7 / Day 30). Tells us if the product is working day-to-day.
- **Feature-specific signals** — First Ascent claim rate, Live Climb completion vs. abandon rate, paywall presentation outcomes, copy-variant performance. Tells us what to iterate on.
- **Quality** — crash rate, error rate, performance regressions. Stability is non-negotiable.

If an event wouldn't change a decision, don't log it. Volume of events ≠ value of analytics.

**Providers**

Multiple analytics destinations are sanctioned — each is best at a different job. Route events to the right destination through a single facade; never call providers directly from feature code.

- **Firebase Analytics** — broad funnel, cohort, retention analysis. Most product events go here.
- **SuperWall** — onboarding-flow step-level conversion + paywall presentation analytics (its specialty).
- **Crashlytics** — crashes, fatal errors, stability metrics.
- **Sentry** — error/crash diagnostics mirror alongside Crashlytics (non-fatal errors, app hangs, symbolicated traces). When reading, triaging, or updating Sentry issues/events, use the repo-local skill at `skills/sentry/SKILL.md`. Like the climb-content skill, it is harness-neutral so Codex, Claude, Cursor, or any other AI provider can follow the same workflow.

When evaluating new providers, justify them by what they uniquely measure that the existing set doesn't.

**Implementation principles**
- One analytics facade. Feature code never imports a provider directly; it logs through the facade, which routes to the right destination.
- Event definitions are typed, discoverable, and feature-owned. Don't pass arbitrary string event names — events are values defined alongside the feature that emits them.
- Log from logic layers (view models, coordinators, services), not from view bodies. SwiftUI screen tracking is the exception — it belongs on the view via a shared modifier.
- Parameters stay low-cardinality and privacy-safe: never log raw user input, email, DOB, exact location, exact health samples, or any PII. Bucket continuous values into categories before logging.
- Event contracts are verifiable. Tests should exercise event-emission paths without requiring a live analytics runtime.

**Local inspection**

DEBUG builds expose a developer-visible analytics console so events and screen views can be inspected without leaving the simulator.

### Live Climbs V1 Architecture

Live Climbs is the hero competitive experience: a user picks a real-world landmark (Mt. Everest, Empire State Building, etc.), races against past attempts in real time via headphone-motion step tracking, and either reaches the target step count (completion) or doesn't (failed attempt). This section defines the surface architecture, attempt model, live session execution, replay leaderboard, content delivery, and visual conventions.

**Surface architecture**
- Live Climbs lives on a 3-screen loop: **Home** (a stateful entry card showing the day's recommended climb), **Browse** (a searchable globe for discovery), and **Climb Detail** (the primary destination — overview, your history, per-climb leaderboard).
- Home shows one concrete recommended climb per day, persisted per local calendar day so it stays consistent even if completion state changes mid-day. The card is fully tappable; no extra in-card CTA chrome.
- Browse treats the globe and bottom drawer as distinct navigation modes: globe pin taps open a compact preview card; search/list/section taps open Climb Detail directly. Search lives in the drawer and expands above the keyboard when focused. Globe state (zoom, preview, search) clears when re-entering Browse from elsewhere.
- Climb Detail uses a flippable hero card (landmark image on the front, tier + fun fact on the back) and three swipeable pages: overview, personal history, per-climb leaderboard. The leaderboard page uses the per-climb leaderboard pattern defined in **Leaderboard UX Flow**.
- Globe pins are state-driven: hollow outline for available climbs, filled with double-pin glow for the active climb, filled check badge for completed climbs.
- Hardware-capability gating (headphones required) belongs at the *start-attempt* moment, not as warnings on Home or Browse. Surface help inline at the gate, not as ambient warnings.

**Attempt model**
- The climb attempt is the source of truth for progress and history. It replaces any older completion-only model.
- Catalog climbs are *single-session challenges*: the live attempt must reach the target step count to count as a completion. Ending early saves a failed attempt in personal history; only target-reached completions count publicly (leaderboard, First Ascent eligibility).
- Live Climb completions come only from the live headphone-motion attempt flow. Manual entries, external imports, and routine completions cannot progress or complete a Live Climb. (Integrity gate; cross-referenced from Workout Source + Context.)
- The live attempt creates a workout only after the live session stops with recorded steps. The workout flows through the normal workout mutation pipeline so leaderboards, Best Efforts, and remote backup stay on one path.
- Reaching the climb's step target *is* the finish, and `LiveClimbCompletionPolicy` is the only place that decides it.
  Status always reads steps, never `stopReason`.
  Never add a second finish definition: readers ask the policy, they don't re-derive.
- `stopReason` describes *how* a session ended, never whether it counted.
  `ClimbService.apply` upgrades it to `.targetReached` for the manual-stop case only - a climber who tapped End past the target finished - so rehydration and the replay Cloud Function agree on that path.
  Every other stop reason is deliberately left as recorded.
- An interrupted recovered draft past the target counts locally as a completion but is deliberately never published by the replay Cloud Function, because a recovered draft's step count is typed by hand.
  That asymmetry is an intentional First Ascent integrity gate, not the reinstall bug it resembles: a First Ascent is permanent and never reclaimable, so a typed number must never claim one.
  Ask `LiveClimbCompletionPolicy` before changing what normalizes; don't widen it to heal a status that already reads steps.
- Saved Live Climb attempts are immutable competitive history. Discard during the live session if the attempt shouldn't count; once saved, workout-log delete affordances do not erase the underlying attempt.

**First Ascent (World First) prestige**
- Every climb has a permanent First Ascent holder — the first user to complete it. The holder's name and completion date remain associated with the climb forever, even after their time is beaten by faster climbers. This creates a permanent-prestige retention loop: every new climb drop opens a fresh First Ascent slot that can never be reclaimed once held. In leaderboard surfaces, First Ascent is honored but secondary to the active top-3 chase — the *current* glory belongs to whoever holds the top times; First Ascent is a permanent annotation, not the headline.
- The universal no-finisher copy is: "First Ascent open. The first finisher claims it forever." Use it verbatim on any surface that needs to explain an unclaimed climb.

**Live session execution**
- Sensor stats (time, steps, progress, SPM) update locally every second during a live session without waiting on the network. Stale or failed backend reads must never interrupt local tracking.
- The replay leaderboard is the primary visual surface during a live attempt — elapsed time + target step count in top chrome, the user's row anchors as a horizontal accent progress indicator, with an end-attempt control at the bottom. Pre-start countdown fully obscures the live UI until recording begins.
- Live attempts cannot be paused. Once recording starts, the clock runs until the user reaches the target step count (completion) or ends the attempt (DNF). If the user stops stepping or steps off the machine, the clock keeps running — competitive integrity comes from the unbroken clock, like an ultra-marathon. We don't try to detect "is the user still climbing" via motion heuristics or location; that's complexity without product value, and any rest the user takes legitimately costs them rank.
- A background-execution helper runs alongside the headphone-motion session so the session survives backgrounding. The helper must not write HealthKit workouts or request new Health permissions.
- A Live Activity / Dynamic Island surface mirrors session state (compact: steps + rank; expanded: name + image + duration + steps + intent-driven controls). The widget extension reads from the session view model only — never Firestore, never the replay index directly.
- Completed sessions transition to a post-save summary before dismissal — adaptive pace splits, vertical-gain display, share carousel with a Live Climb–specific share card when climb metadata is available, and direct affordances to add notes and media to the climb workout. The completion summary is the moment for adding context; we don't gather notes / media via a deferred review sheet.

**Replay leaderboard architecture**
- The replay leaderboard is a context-agnostic system reusable for Live Climbs and future race surfaces (challenge climbs). Don't clone climb-specific comparison logic per surface — share the context / sampler / service abstractions.
- Replay rank compares the live user's current steps against completed eligible attempts at the same elapsed-time bucket. Failed, abandoned, and partial attempts never publish into replay indexes. Tied completed attempts rank ahead of the live user (a new attempt starts at the bottom of the completed field).
- Per-climb replay contexts rank the live climber against **one row per opponent — each opponent's best (fastest) completion on that climb**. Multiple completions by the same user collapse to their best for the live race; chasing a rival three times (their slow, middling, and fast attempts) is clutter, not competition. The static per-climb leaderboard separately preserves the full completion history (see Leaderboard UX Flow). Only target-reached completions feed the replay context.
- Post-completion share / summary rank is computed against completed bucket-zero replay entries with `completedCount` as the denominator. Don't reuse in-session time-window rank or total-climber count for completed share surfaces.
- Step timeline checkpoints are source-neutral. Sensor producers emit cumulative step samples into a shared recorder so result / replay UI doesn't depend on one sensor source.
- The replay index is server-published — clients write zero leaderboard data during a live session. A Cloud Function publishes from saved attempts after the session ends and normalizes degenerate curves (e.g. all-zero-until-final-bucket) into conservative monotonic curves so replay rows don't appear stationary.
- Replay rows denormalize public display fields (display name, avatar token, optional photo URL) so live-session client code does not read private user documents during a race.
- Per-climb rank and total-climber counts stay hidden until real backend data exists. No placeholder public stats.
- Future demographic / peer-group insights must use declared profile fields and stay opt-in / privacy-safe.

**Apple Health enrichment**
- Apple Health can *enrich* a saved Live Climb workout with wearable metrics (heart rate, calories, device metadata, HealthKit UUID, an external provenance link). It must never become the canonical Live Climb source.
- Enrichment is automatic only for confident one-to-one matches between an unlinked Live Climb workout and an unlinked Apple Health stair / step workout. Ambiguous matches are skipped, never guessed.
- Enrichment preserves the Live Climb's source, steps, floors, duration, and attempt participation — it only adds health metrics and the external provenance link.
- Enrichment is **silent**. An enriched Live Climb never appears in the auto-import review flow, never shows up as a manual-import candidate, and never asks the user to confirm or edit the merged data. If the Apple Health workout arrives after the Live Climb's completion summary has been dismissed, the new health metrics show up on the workout detail next time the user looks — no notification, no review.
- The user gathers notes / media for a Live Climb at the **completion summary**, not in a post-hoc review surface. Enrichment never inserts itself into that moment.

**Climb content (catalog + images)**
- When adding, editing, releasing, or validating Live Climb catalog content, use the repo-local skill at `skills/live-climb-content/SKILL.md`. This file is intentionally harness-neutral so Codex, Claude, Cursor, or any other AI provider can follow the same workflow.
- Climb content is remote-first by default. The catalog ships as a hosted manifest + versioned catalog file; climb images live in Storage as hero / card / thumb sizes. Adding a new climb means publishing new content, never shipping app code (see Content-driven over rebuild).
- A bundled bootstrap catalog ships with the app for *metadata only*, so Home and Browse render even if the remote catalog has never been fetched. Once a remote catalog has been successfully fetched, subsequent launches prefer the disk-cached catalog over the bundled bootstrap.
- Climb images do not ship in the app bundle — artwork is remote-only. Missing images render a placeholder until the remote image is cached locally.
- Catalog and image fetching use shared disk-backed cache infrastructure. Climb-specific fetch/decode logic stays in climb repositories; the cache layer is generic.
- Home, Browse, and Detail render from cached / local state first, then refresh remote content in the background. Don't block UI on network fetches.

**Climb card visual treatment**
- Reusable climb card surfaces share common chrome (split-card surface, leading artwork, animated tier border). Don't reimplement split layouts, image clipping, or tier-border animation per screen.

### Catalog Release Phasing
- Catalog release state is server-controlled. The app model currently uses `releaseState`; if a remote content feed exposes `releaseStatus`, map it into the same release-state domain instead of branching UI on a second concept.
- Launch composition should be content-driven: available climbs, coming-soon climbs, hidden climbs, and disabled climbs are all catalog data, not app-release code paths.
- New climb drops should be publishable by changing hosted catalog data and image assets. Avoid adding per-climb code, hardcoded IDs outside smart defaults, or app-store-release dependencies for catalog expansion.
- First Ascent availability follows release phasing: hidden and disabled climbs do not appear as open First Ascent opportunities; coming-soon climbs can tease future drops but must not accept live attempts until available.
- Coming Soon climbs follow a cross-surface mystery pattern. The Pokedex shows blurred silhouette only (no name, no location). The Globe shows location only (via dim pin with region revealed on tap). The user pieces together identity by cross-referencing both surfaces; neither reveals everything on its own.
- All climb tiers use the same rotating tier-border treatment driven by per-tier color tokens. Mythic is the emphasized tier (strongest glow, purple-forward prismatic palette).
- Persistent idle climb surfaces (e.g. the Home daily card) may use a lighter ambient border treatment with an unblurred moving highlight to reduce per-frame animation work while preserving visible motion.

### Onboarding

**Planned flow**

The planned onboarding sequence, in order:
1. Welcome screen
2. Pre-auth value carousel
3. Sign-in (Apple / Google)
4. Survey
5. Paywall priming screens
6. Hard paywall
7. Home

This sequence will evolve as we learn from SuperWall and RevenueCat funnel analytics. Treat it as the current plan, not a permanent contract.

**Routing & resolver**
- Sign-in is a routing transition, not a sheet dismissal — auth screens should not dismiss themselves after provider sign-in; the auth surface is replaced by the authenticated root.
- The post-auth resolver distinguishes three user states: **first-time** (run full post-auth flow), **returning-complete** (skip to home), **interrupted-returning** (resume at the step where they left off, not restart from the beginning).

**Pre-auth value screens**
- Follow a single shared cinematic pattern — full-bleed dark background, thin top progress indicator, one large product hero, short copy at the bottom, one CTA per screen. Don't fork the layout per screen.
- No skip affordances. No card chrome or boxed surfaces.

**Content discipline**
- Survey and paywall content is product-defined. Engineers should not ship onboarding screens, copy, or content beyond what product has provided mocks for.

**State persistence**
- Onboarding state is local per Firebase `uid` during early testing. Do not add remote onboarding fields to `users/{uid}` without updating `firestore.rules` in the same change.
- Progress persists locally across app restarts and backgrounding so a user who leaves mid-onboarding resumes at the exact step they left, with the same state. Uninstall/reinstall resets state via app data removal until remote onboarding state is introduced.

**Other**
- Bodyweight is a single profile-level value editable in settings. It's the app-wide source for body-mass usage; don't introduce parallel bodyweight inputs in feature-specific flows.

### Workout Measurement

Workouts are described by **absolute, measured signals** — steps, duration, cadence (steps per minute), and optional supporting data (heart rate, calories, RPE, added weight). There is no user-calibrated effort score, no base level, no relative-to-fitness intensity calculation. We trust what was measured.

**Why no base level:** the personalization it enables — adjusting workout effort relative to a personal baseline — isn't load-bearing. Live Climbs are target-step-count challenges (same target for everyone). Routines expose their own absolute difficulty (level + duration sequences) for self-selection. Leaderboards rank by absolute metrics. Best Efforts compares the user to their own past. None of these need a fitness baseline, and asking for one at onboarding adds friction before the user has felt any value.

**What stays:**
- The canonical mapping between StairMaster levels (1-25) and steps-per-minute is preserved as a **display utility**. Surfaces that want to show "you stepped at the equivalent of level 8" alongside a workout's cadence read from this shared mapping — don't duplicate the math.
- Historical percentile remains as a ranking layer over absolute metrics, computed against the user's own workout history ("harder than 85% of your past sessions"). It's a personal benchmark, not a calibrated effort definition.
- Every workout mutation (create, edit, delete, import) still triggers a recompute of derived data — Best Effort inputs, percentile snapshots, local leaderboard aggregates. Surfaces reading derived values trust them to be current.

**What's deprecated (don't extend):**
- Base level state (seed value, auto-calculated estimate, manual override).
- "Fitness level" terminology and migration code.
- User-calibrated effort score (workout intensity computed relative to a personal baseline).
- Base-level seeding UI in onboarding; manual base level override in settings.

Existing code for these can stay until the cleanup task lands, but treat it as legacy — don't add features through it, don't introduce new dependencies on it, and prefer absolute metrics in new code.

### Routines

Routines are a **first-class peer feature** to climbs — not a stepping stone toward absorption. Climbs and routines coexist as the two canonical live-tracked experiences, and they answer different user intents.

**Climbs vs. routines — the core distinction:**
- **Climb** = race to a specific step target tied to a real-world landmark ("I'm climbing to the top of the Burj Khalifa"). Fixed destination, fixed step goal, prestige tied to the place.
- **Routine** = open-ended guided interval session ("I'm running through these intervals"). Variable step count depending on how many intervals the user completes. Prestige tied to the routine itself, not a destination.

Both have their own browse, detail, live, and leaderboard surfaces. Don't fold one into the other.

**Routine structure:**
- A routine is an ordered sequence of **intervals**, each specifying a target level (1-25 on the StairMaster mapping) and a duration. The session ends when all intervals are completed, or when the user ends early.
- Routines are content-driven: server-published catalog entries plus user-created routines. Adding a new routine should never require an app release. The same content-driven principle that applies to the climbs catalog applies to routines.
- User-created routines live alongside server-published routines and use the same model. The browse surface distinguishes them visually (e.g. "My Routines" vs. catalog) but the detail / live / leaderboard experiences are the same.

**Per-routine leaderboards:**
- Every routine has its own leaderboard. Completing a routine publishes the user's attempt onto that routine's leaderboard.
- Leaderboards include a **"Just Me" toggle** so the user can switch between the global ranking and their own attempt history filtered to that routine.
- Leaderboard rankings use absolute metrics (matching the Workout Measurement section's "no calibrated effort score" rule). The ranking metric for a given routine is whichever absolute signal best reflects performance on that routine's intervals — typically a combination of completion, total session duration vs. target, and adherence to interval levels. Don't introduce a calibrated effort score for routine ranking.

**Live routine sessions:**
- Routine completions come only from the live routine flow (analogous to how Live Climb completions come only from the live climb flow). Manual entries and external imports cannot complete a routine.
- The live experience is routine-specific: current interval, target level, time remaining in interval, progress through the full routine, real-time step count. It is NOT the same UI as a Live Climb (which is structured around a step-target race), even though both share the headphone-motion sensor pipeline.

**Routines vs. challenge climbs:**
- The "challenge climb" concept stays alive but as a **subtype of climbs**, not a way to absorb routines. A challenge climb is a regular climb (target step count tied to a landmark) with additional constraints layered on — e.g. "you must sustain level 12+ for the final 5,000 steps." Challenges live inside the climbs feature; they do not replace or absorb routines.
- The two features answer fundamentally different user intents: routines = open-ended interval training, climbs = destination-focused races. Don't conflate them.

**Visual identity:**
- Each routine's interval sequence has an intrinsic **shape** (a pyramid, a plateau, alternating spikes, etc.) that visually encodes what the workout feels like. Treat that shape as the routine's primary visual identity — a hero-sized stylized rendering of the interval bars on the detail screen, not a generic data viz widget tucked in a corner.
- Don't require per-routine illustrations or category icons. The interval shape itself differentiates one routine from another and works automatically for user-created routines without needing a designer in the loop.

### Week Start + Leaderboard Windowing

**Week boundaries**
- Monday is the single app-wide week start. Don't reintroduce a user-configurable week-start preference or selection UI.
- Home summaries use Monday-based weeks in the user's local timezone.
- Competitive / global leaderboards use canonical Monday-based weeks in UTC.
- Per-week user-configurable numeric targets are intentionally out of scope. Don't reintroduce target cards, setup prompts, or CRUD around personal weekly goals unless product explicitly changes direction.

**Document model**
- Leaderboard documents are **current-period-only**, not historical archives. One document per user per time frame: weekly, monthly, yearly, all-time.
- Each document carries metadata (schema version, time frame, period key, period start timestamp) and the aggregated metrics for the period (steps, floors, workouts, duration, pace). The exact field names live in `firestore.rules`; CLAUDE.md → Firestore Schema-Change Rule governs how to extend or modify them.

**Metrics**
- **Steps** is the canonical climb leaderboard metric.
- **Floors** is supporting / display data only and must never change rank order.
- **Pace** leaderboards rank by canonical steps-per-minute (SPM), not by viewer-preference floors-per-minute.

**Publication & sync**
- Leaderboard publication is mutation-driven: workout create / import / delete always affects publication; workout edits affect publication only when leaderboard-relevant fields change (date, duration, steps, floors). Photo, notes, heart-rate, calorie, or MET edits don't touch leaderboard publication.
- The leaderboard refresh UI must never own the only publication path. Users must appear remotely even if they never open the leaderboard tab.
- Local leaderboard state updates incrementally for current periods only. Full-history rebuilds are reserved for migration, repair, or schema backfill.

### Leaderboard Seeding Policy (Debug / CI)
- Firestore client rules only allow writes to `leaderboard_stats` where `userId == request.auth.uid`.
- Multi-user seed data should not be written from client debug tools in shared environments.
- Use server-side seeding (Admin SDK / Cloud Function / CI job) for deterministic multi-user leaderboard fixtures.
- For local-only iteration, use Firestore emulator or seed only the authenticated user.
- Use `scripts/dev-db.mjs` as the central dev/staging database tool for repeatable fixture workflows. It can seed, clear, or reset `profiles`, `leaderboard`, `live-replay`, or `all`, and it must keep refusing production (`ascend-prod-9c8f2`) and unknown Firebase projects.
- Dev database cleanup should be target-scoped and metadata-driven. Do not hide an unrestricted project wipe behind a friendly `clear all` command; full destructive wipes need an explicit, separately guarded command and a reviewed collection list.
- Profile fixture data must include the full public profile contract: display name, age, gender, `weight_kg`, `location_country`, optional `location_region`, `joined_at`, public profile mirror, profile stats, achievements, and public workout summaries.
- To create one dev/staging QA Auth account, use `scripts/dev-db.mjs create-auth-user`. It must stay dev/staging-only, can generate a password, and can optionally run `--hydrate-profile` or `--seed-demo-data` after the Auth account exists.
- To patch one dev/staging account, use `scripts/dev-db.mjs hydrate-user` so private `users/{uid}` and public `users/{uid}/public_profile/current` stay in sync.
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

Leaderboard UX in Ascend covers two distinct surfaces — the global tab (community-wide aggregate stats) and per-climb leaderboards (completion times for one specific climb). They share data-model conventions but use different layouts and emphasis.

**Global leaderboard tab — aggregate stats across the community**
- The tab root is a category hub previewing each canonical metric (climb, workouts, duration, pace per the Week Start + Leaderboard Windowing rules). A "see all" affordance opens a per-metric detail screen.
- Per-metric detail screens lock the metric and filter by time frame (weekly, monthly, all-time).
- Detail screens compose from focused, reusable subviews — time-frame picker, podium (top 3), pinned current-user row when not in podium, rank list. Don't reimplement these patterns per metric.
- The podium always renders three slots even when sparse; empty slots use a motivational empty-slot treatment.
- The current user appears in exactly one place at a time. If they're in the podium, they're not duplicated in the rank list below.
- Rank subtitles must be chase-oriented. Show earned percentile bands only at Top 1%, Top 5%, Top 10%, Top 25%, or Top 50%; never render low-value percentiles such as Top 98% or Top 100%. Below Top 50%, show the nearest meaningful steps target instead: Top 100 when unlocked, otherwise Top 10, or Top 50% when that is the relevant next tier.
- Active rank cards use this ladder: #1 `DEFENDING GOLD · X AHEAD`, tied #1 `TIED FOR GOLD`, #2 `X STEPS FROM GOLD`, #3 `X STEPS FROM SILVER`, #4-10 `X STEPS TO BRONZE`, #11-100 after the Top 100 population threshold `TOP 100 · X TO TOP 10`, and #11+ before that threshold `X STEPS TO TOP 10`.

**Per-climb leaderboard — completion times for one climb**
- Top finishers (#1, #2, #3) get medal-color emphasis (see Design System: medal tokens). They're the *active* prize being chased.
- The climb's First Ascent holder is surfaced as a quiet, persistent annotation — permanent prestige, but visually secondary to the active leaderboard chase. See the First Ascent principle in the Live Climbs section.
- Achievement terminology is locked to **Top 1**, **Top 3**, **Top 10**, and **Top 100**. Top 1 may be swapped to a product-approved label later, but it must be centralized as a single string constant.
- Achievement counts use cumulative inclusive counting: a Top 1 finish also counts toward Top 3, Top 10, and Top 100. Do not render these as mutually exclusive medal bands.
- Per-climb leaderboards rank *completed attempts on one climb*, not aggregate community totals. They don't share a layout with the global aggregate leaderboards.
- The static per-climb leaderboard shows **every completed attempt**, not best-per-user. A user appears as many times as they've completed the climb; this surface is the historical record of completions. Contrast with the in-session live race, which ranks against best-per-user (see Replay leaderboard architecture in Live Climbs).

**Tie handling (applies to global and per-climb)**
- Ties are ranked using **standard competition ranking** ("1, 2, 2, 4"). Tied users share the same rank; the next rank is skipped by the count of tied users. This matches the sports convention and honors the honest outcome.
- Don't break ties with secondary metrics (steps tie ≠ floors tiebreaker; time tie ≠ cadence tiebreaker). Adding a secondary criterion quietly changes what the leaderboard measures.
- Don't break ties with submission timestamp. First-to-submit is a property of when the user happened to climb, not how well they climbed.
- Match precision to perception. Per-climb completion times rank at second granularity; sub-second tiebreakers feel arbitrary and don't reflect anything users perceived during the attempt.
- Tied ranks must be visually obvious in the UI — same rank number on each tied row, "T" prefix or equivalent treatment. Don't render ties as if they were ordered.
- Podium display must handle tied top ranks (e.g. three users tied for #1) — multiple users may share a podium slot. The podium is a *visual* surface; the ranking rule is the source of truth.
- First Ascent is exempt — it's keyed on submission timestamp and is unambiguous by design. Two users may tie on the leaderboard, but only one submission reached the backend first.

### Design System
- **Fonts**: Montserrat (custom) — `montserratBold`, `montserratSemiBold`, `montserratMedium`, `montserratRegular`
- **Accent color**: `#86D30A`
- **Medal tokens**: Gold `#D4AF37`, Silver `#C0C0C0`, Bronze `#CD7F32`. Reserved for podium / rank-prestige moments (leaderboard top 3, First Ascent emphasis, achievement displays). The only sanctioned exceptions to lime-accent discipline — apply sparingly, never as primary surface color.
- **Achievement motif vocabulary**: laurels represent personal achievements and record-book moments; crowns represent competitive ranking dominance. Do not combine laurel and crown in the same badge treatment.
- **Theming**: `ThemeManager` with dark/light mode, `effectiveColorScheme`, `.themedBackground()`
- **Icons**: SF Symbols (considering migrating to a custom icon set for consistency)
- **Icon consistency**: Use the same icon for the same action across screens (for example, overflow menus should use one consistent `ellipsis` style app-wide unless product design explicitly says otherwise)
- **Level sliders**: Reuse the shared `SegmentedHeatmapSlider` for 1-25 heatmap-based level selection (base level onboarding/settings and routine interval builder) instead of creating screen-specific segmented sliders
- **Sheets**: Use `AppSheetPreset` with `.appSheetStyle(...)` for sheet sizing, drag indicator behavior, and sheet surface background instead of raw `presentationDetents` arrays at call sites. Use `AppSheetScaffold` for reusable sheet layouts, `AppSheetOptionRow` for menu-style options, and `appSheetButtonStyle(...)` for consistent sheet button semantics. Prefer a dedicated preset/layout pair for dense action sheets when they need tighter row density than general compact dialogs, and avoid root-level `Spacer()`-driven layouts in compact sheets.
- **Keyboard dismissal**: Reuse the shared `keyboardDoneToolbar(...)` helper with `KeyboardDismissButton` for text-entry keyboards that need an explicit Done action instead of re-creating keyboard toolbar buttons per screen.
- **Integrations UI**: Keep integrations list cards as overview surfaces, not inline control panels. Shared card styling and structure should live under `Features/Integrations/Shared`, while provider-specific actions live in provider-owned manage sheets or detail surfaces.

---

## Coding Rules

### Engineering Principles

These apply to every change, regardless of feature or domain. If a loaded skill (`swiftui-pro`, `swift-concurrency-pro`, `swiftdata-pro`, etc.) prescribes a more specific pattern, follow the skill — these are the baseline that holds even when no skill is loaded.

**Code structure**
- **Single Responsibility (SRP).** Each type does one thing. If a type has two unrelated reasons to change, split it.
- **DRY — Don't Repeat Yourself.** If a non-trivial pattern (UI, logic, formatting) appears more than once, extract it to a shared component, view model, or service. Repeated three-line snippets are tolerable; repeated thirty-line patterns are debt.
- **YAGNI — You Aren't Gonna Need It.** Don't add abstractions, parameters, or "flexibility hooks" for hypothetical future needs. Build for what's needed now; refactor when a real second use case appears.
- **Layering — keep responsibilities separated.** Views render. View models hold UI state and orchestrate. Services own side effects (network, persistence, sensors, system APIs). Models represent persistent data. A view that calls a network API directly is a smell.
- **Dependency injection over singletons in business logic.** Services that touch external systems should be injectable so they can be mocked in tests. Convenience singletons are acceptable for global state (theme, settings) but not for testable business logic.
- **Content-driven over rebuild.** Distinguish app *shell* (durable code) from *content* (instances the shell handles). Shell code accepts any instance of its content type; adding new content should not require code changes or App Store releases. If you find yourself writing a new code path for every new climb, email template, or share-card background, that's a smell. Whether content lives remote (catalogs, configs) or bundled (offline-first assets) is a separate decision; the principle is that *adding content* should never mean *shipping code*.

**Testability**
- **Business logic does not live in SwiftUI view bodies.** Anything decision-driving (computations, transformations, conditional flows, side-effect orchestration) must be reachable from a unit test without instantiating a SwiftUI view tree.
- **ViewModels do not import SwiftUI.** They depend on Foundation, Combine, Observation — never `import SwiftUI`. This guarantees they're testable independently of the UI layer.
- **Pure functions where possible.** If a computation has no side effects, write it as a pure function or static method. Pure functions are trivially testable and reusable.

**Performance and rendering**
- **Render path stays cheap.** No filter / reduce / sort over large arrays inside `body`. No SwiftData queries inline in views. Cache derived state via `@State` + `.onChange` or precomputed view-model properties bound to stable inputs.
- **Don't fight SwiftUI's diff.** Give views stable identities. Avoid forcing re-renders by passing fresh closures or recreated objects into deep children.

**Code hygiene**
- **Clarity over cleverness.** Code reads like prose. If a future reader (human or agent) won't immediately understand a line, the code is wrong — not the reader.
- **Delete before you defend.** Dead code, unused parameters, commented-out experiments, "just in case" abstractions — remove them. Git history is the backup.
- **Comments explain WHY, not WHAT.** A well-named function explains *what*. Comments earn their space only when there's a non-obvious *why*: a hidden constraint, a workaround for a specific bug, an invariant that would surprise a reader.
- **No leftover scaffolding from refactors.** Removed code stays removed; don't keep deprecated paths "for safety" without a written deprecation/removal date.

### Specialized Skills

Load these skills before writing or reviewing code in their domains. Each listing below is mandatory for the areas it claims — if a task touches a domain, the matching skill is not optional.

- `swiftui-pro` is required for SwiftUI code, layout, navigation, accessibility, animation, performance work, and SwiftUI-focused reviews.
- `swift-concurrency-pro` is required for actors, async/await, `Task`, cancellation, `Sendable`, isolation, and strict-concurrency fixes or reviews.
- `swiftdata-pro` is required for SwiftData models, relationships, predicates, queries, CloudKit sync constraints, and persistence reviews.
- `swift-testing-pro` is required for Swift Testing, async test patterns, unit/integration test work, and XCTest migration.
- `vibe-security` is required for Firebase Auth, Firestore rules, Cloud Functions, waitlist/signup endpoints, user data, secrets, tokens, privacy, subscriptions/payments, or any auth/authz/trust-boundary change.
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
- `product-design-playbook` (custom user-level skill at `~/.claude/skills/product-design-playbook/`) is required for UI/UX design decisions and consumer-app copywriting — empty states, headlines, CTAs, onboarding patterns, conversion mechanics, brand voice work, and any design-pattern reference. The skill indexes 33 plays from *The Product Design Playbook* and the agent should consult relevant plays before shipping design or copy changes.
- If a task spans multiple domains, use every matching skill.
- If a request is ambiguous but clearly adjacent to one of these domains, load the relevant skill rather than skipping it.
- Keep this file focused on Ascend-specific rules. If a skill conflicts with this guide, follow this guide.

### Ascend-Specific Overrides
- **Targeting**: iOS 17.0+, Swift 6, strict concurrency. If a newer iOS API meaningfully improves a feature, mention it and gate it with `@available` rather than silently raising the baseline.
- **State management**: SwiftUI with `@Observable` for shared state, and mark shared `@Observable` classes with `@MainActor`.
- **Dependencies**: No third-party frameworks without asking first. Avoid UIKit unless requested.
- **Code hygiene**: Never commit API keys or secrets.
- **Local style conventions**: prefer modern Swift idioms — `replacing("a", with: "b")`, `URL.documentsDirectory`, `url.appending(path:)`, `.formatted()` or `Text(..., format:)`, and `localizedStandardContains()` for user-facing filtering.
- **SwiftData + CloudKit**: Never use `@Attribute(.unique)`. Properties must have defaults or be optional. All relationships must be optional.

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
- Waitlist submissions are subscribed server-side to Beehiiv. The Beehiiv API key and publication ID live in the `BEEHIIV_CONFIG` Secret Manager JSON secret; never expose them in website or iOS client code.
- `joinWaitlist` rate limits public submissions using hashed requester IPs stored in `email_rate_limits`, calls Beehiiv, and mirrors normalized email hash + Beehiiv subscription metadata in the `waitlist` collection for dedupe/debugging.
- Transactional emails for feedback and future non-Beehiiv product triggers must be sent server-side from Cloud Functions, never directly from the website or iOS client.
- Cloud Functions email provider config lives in the `TRANSACTIONAL_EMAIL_CONFIG` Secret Manager JSON secret, with `functions/.secret.local` used only for local emulator overrides.
- Legacy queued transactional emails are delivered in the background by the scheduled `processEmailJobs` worker. Do not reintroduce waitlist welcome emails through `email_jobs` unless product explicitly moves off Beehiiv.
- In-app feedback submissions (`feedback` collection) trigger `onFeedbackCreated`, which sends an admin notification email directly via Resend (not queued). The recipient is `feedbackNotificationEmail` from the secret config (falls back to `replyTo` → `fromEmail`). Reply-to is set to the submitting user's email. Notification delivery metadata is written back onto the feedback document.
- Email copy, templates, lifecycle automations, Beehiiv campaigns, and subject lines must follow the Ascend Email Playbook. Codex has this as the `ascend-email-playbook` skill at `~/.codex/skills/ascend-email-playbook`; other agents should apply the same rule set: app-triggered emails go through Cloud Functions/Resend with deterministic dedupe, broadcasts go through Beehiiv, copy is competitive/stair-stepper-specific, and each email has one primary CTA.

### Key Config Files
- `.firebaserc` — project aliases (dev, staging, prod)
- `firebase.json` — hosting, functions, firestore config
- `firestore.rules` — security rules
- `.github/workflows/ci.yml` — PR validation
- `.github/workflows/deploy-staging.yml` — staging deploy pipeline
- `.github/workflows/deploy-production.yml` — production deploy pipeline (gated)
- `Gemfile`, `fastlane/Appfile`, `fastlane/Fastfile`, `fastlane/Matchfile` — iOS build/signing/TestFlight automation
