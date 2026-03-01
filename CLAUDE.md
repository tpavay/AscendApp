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
- **Cloud Functions** (TypeScript): Strava OAuth + sync, waitlist signup endpoint with dedupe

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
│   ├── Services/               # HealthKitService, WorkoutService, PersonalRecordService
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
| Production | (not created yet) | Release | (not created yet) |

**Environment-agnostic URLs**: Never hardcode Firebase project IDs. Derive from `FirebaseApp.app()?.options.projectID`:
```swift
let hostingURL = "https://\(projectId).web.app"
let functionsURL = "https://\(region)-\(projectId).cloudfunctions.net"
```

### Data Models (SwiftData)
Workout, LeaderboardStats, PersonalRecord, Goal, Routine, RoutineFolder, WeightPersonalRecord, AggregateWeightRecord, PendingMediaUpload

### Import UX
- Workout import supports individual import, selected-batch import, and import-all from the same sheet.

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

### Design System
- **Fonts**: Montserrat (custom) — `montserratBold`, `montserratSemiBold`, `montserratMedium`, `montserratRegular`
- **Accent color**: `#B4CC00`
- **Theming**: `ThemeManager` with dark/light mode, `effectiveColorScheme`, `.themedBackground()`
- **Icons**: SF Symbols (considering migrating to a custom icon set for consistency)
- **Icon consistency**: Use the same icon for the same action across screens (for example, overflow menus should use one consistent `ellipsis` style app-wide unless product design explicitly says otherwise)

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

### Branching Strategy (implementing)
- `main` — production-ready code
- `develop` — integration branch, merges trigger staging pipeline
- `feature/*` — individual work, PR into develop

### Pipeline (implementing)
- **On PR to develop**: CI build with Staging scheme + tests (verify only, no deploy)
- **On merge to develop** (sequential, stop on failure):
  1. Build iOS app (Staging scheme, produce IPA)
  2. Deploy Firebase Functions
  3. Deploy Firestore Rules
  4. Deploy Firebase Hosting
  5. Upload to TestFlight (last — hardest to reverse)
- **On merge to main**: Same pipeline but with Release scheme targeting production

### Firebase Hosting
Website at `web/public/`. Deploy with `firebase deploy --only hosting`. Currently manual — will be automated via CI/CD.
- Waitlist form submissions must use `POST /api/join-waitlist` (Hosting rewrite to `joinWaitlist` Cloud Function), not direct Firestore client writes.

### Key Config Files
- `.firebaserc` — project aliases (dev, staging, prod)
- `firebase.json` — hosting, functions, firestore config
- `firestore.rules` — security rules
- `.github/workflows/build-ios.yml` — CI/CD pipeline
