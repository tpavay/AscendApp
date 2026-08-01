# Ascend - Project Guide

This file is the always-on core. Domain detail lives in `.claude/skills/` - see the Skill Router below.

## What Is Ascend

Ascend is a competitive stair stepper companion for iOS. It's built for people who already use the stair stepper (or are about to start) and want their work to count. Users race the world up real landmarks, top per-climb leaderboards, log every session, and watch their progress compound over time. The leaderboard is the conversation.

**Solo dev + AI assisted** (Tyler Pavay). Launch monetization is a hard paywall with no freemium tier: `$49.99/year` with a seven-day free trial, or `$9.99/month` charged immediately with no trial. Both unlock RevenueCat entitlement `app_access`; there is no weekly or separate launch-discount product.

## What Ascend Is NOT

The niche defined by exclusion. Check every feature, screen, and copy change against it:

- Not for users who don't care about the stair stepper.
- Not a social fitness network - no feed, no followers, no kudos. Interaction happens *on the climb*.
- Not a generic fitness tracker. Activity scope is stair stepper sessions.
- Not weight-lifting / strength-training focused.
- Not a passive tracker. Every session is competitive context.

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
- **Cloud Functions** (TypeScript): Beehiiv-backed waitlist signup endpoint with dedupe, transactional email for server-owned notifications
- **Web**: Astro site in `web/`, built to `web/dist/`

## Project Structure

Organized by **features**, not file types. One type per file.

```
AscendApp/
├── App/                # Entry point, Firebase init, env plists, deep links
├── Features/           # Account · Authentication · Celebration · Climbs · Debug · Home
│                       # Integrations · Leaderboards · Moderation · Monetization · Onboarding
│                       # Profile · Progress · Routines · ShareComposer · Workouts
└── Shared/             # Components · Extensions · Managers · Models · Repositories · Services · Views
AscendAppTests/         # Swift Testing suite
AscendLiveActivityWidgets/  # Live Activity / Dynamic Island extension
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

```bash
# iOS tests (mirrors CI - .github/workflows/ci.yml)
xcodebuild -project AscendApp.xcodeproj -scheme "AscendApp-Staging" \
  -configuration Staging -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
  ENABLE_TESTABILITY=YES test

# iOS Release compile check (unsigned, device SDK - catches Release-only errors)
xcodebuild -project AscendApp.xcodeproj -scheme "AscendApp" \
  -configuration Release -sdk iphoneos -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO build

npm run test:firebase-rules            # Firestore/Storage rules (emulator)
node --test scripts/test/*.test.mjs    # scripts + shared migration vectors
cd functions && npm run lint && npm test   # Cloud Functions
cd web && npm run build                    # Website -> web/dist/

# Deploy (aliases in .firebaserc: dev · staging · production)
# Pinned CLI - see docs/dependency-security.md before changing the version
npx -y firebase-tools@15.22.1 deploy --project staging \
  --only functions,firestore:rules,firestore:indexes,storage,hosting
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
- **Medal tokens**: Gold `#D4AF37`, Silver `#C0C0C0`, Bronze `#CD7F32`. Reserved for podium / rank-prestige moments. The only sanctioned exceptions to lime-accent discipline - apply sparingly, never as primary surface color.
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

## Tripwires

Rules that fire from contexts that don't look like their own domain. Each names the skill with the full version.

- **Adding/renaming/removing a Firestore field requires a matching `firestore.rules` update, rules first** - strict `hasOnly`/`hasAll` means the server rejects unlisted fields. Fires while editing Swift. -> `ascend-firebase-data`
- **Bumping a `schemaVersion` constant is a Swift-only change; never re-pin the rule to it.** `firestore.rules` accepts a bounded range, because an exact pin locks stored documents and un-updated clients out the day the number moves. Fires while editing a `currentSchemaVersion`. -> `ascend-firebase-data`
- **Collecting a new data type, calling a required-reason API, or adding an SDK requires updating `AscendApp/PrivacyInfo.xcprivacy` in the same PR** - and the privacy policy, App Store questionnaire, and `Info.plist` strings must agree. Fires while adding a Firestore field or a HealthKit read. -> `ascend-privacy-manifest`
- **User media goes only under `users/{uid}/...` Storage prefixes**, never shared root paths. Fires while writing an upload path. -> `ascend-firebase-data`
- **Account-authored identity (displayName/photo) is public, so it may only be published through the validated write path and only rendered through the shared moderation resolver.** Views take `Moderated*` render models, never raw identity; public writes screen the name and bound the photo URL. Fires while writing any public projection - leaderboards, mirrors, functions, seeds - or any new surface showing another climber. -> `ascend-profile`
- **Connectivity has one app-wide source of truth.** Never add feature-local offline detection or a second network-retry pattern. Fires when you're about to write the duplicate. -> `ascend-firebase-data`
- **Live Climb and routine completions come only from their live sensor flows.** Manual entries and imports can never complete or progress one. Fires when wiring any new workout origin. -> `ascend-workout-model`
- **A chest strap always outranks an Apple Watch as the live heart-rate source.** Every live session type samples through the one shared recorder; never grow a second capture path. Fires while wiring any heart-rate source or new live session. -> `LiveHeartRateSourceKind.selectionPriority`, `LiveHeartRateRecorder`
- **No third-party frameworks without asking first.** Avoid UIKit unless requested. Fires at `import` time.
- **SwiftData + CloudKit**: never use `@Attribute(.unique)`; properties need defaults or must be optional; all relationships must be optional. Fires while writing an `@Model`.
- **"Pre-launch" means PRODUCTION data is free, not dev, staging, or TestFlight stores.** Any change to an `@Model`'s persisted shape - including moving an enum to a raw value - needs a `SchemaMigrationPlan`, or lightweight migration silently defaults every existing row. Fires while editing an `@Model`, which is exactly where the reasoning goes wrong. -> `swiftdata-pro`
- **Store an `@Model` enum as a raw value if anything will ever filter on it.** `#Predicate` rejects a captured Codable enum (`unsupportedPredicate`) and *hard-crashes* on `array.contains(optional ?? "")`; `[String?].contains(optionalProperty)` is the working optional form. A non-filterable column is why a query becomes a whole-store scan. Fires while writing an `@Model` property, long before anyone writes the query. -> `swiftdata-pro`
- **Nothing on a screen's `.task` may run a store query whose cost grows with the user's history.** Home blocked for 182s answering a one-UUID question with `fetch(FetchDescriptor<Workout>())` (ASCEND-IOS-1K). Use the bounded queries in `Shared/Repositories/`; `Workout` carries its heart-rate series inline, so a full fetch is never cheap. Fires while writing a view's `.task` or a coordinator's `configure`. -> `ascend-workout-import`
- **A new code path that writes or reshapes persisted data needs a Remote Config kill switch in front of it** - an iOS binary cannot be rolled back, so a shipped data-corrupting write has no other undo. Gate at the choke point that can *defer* the work (pending state survives untouched), never at the raw Firestore call. Fires while adding a repository write, a sync coordinator, or a migration. -> `docs/remote-config-kill-switches.md`, `AscendApp/Shared/Services/RemoteConfig/`
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
| Imports, Apple Health, enrichment | `ascend-workout-import` |
| Best Efforts, Progress, trends | `ascend-best-efforts` |
| Routines, intervals | `ascend-routines` |
| Profile, demographics, public mirrors, block/report moderation | `ascend-profile` |
| Onboarding, auth routing, paywall priming | `ascend-onboarding` |
| Analytics, telemetry, events | `ascend-analytics` |
| Sharing, stickers, export | `ascend-share-composer` |
| Firestore, Storage, rules, connectivity | `ascend-firebase-data` |
| Privacy manifest, App Store data declarations | `ascend-privacy-manifest` |
| CI, release, TestFlight, fastlane | `ascend-deploy` |
| Web, email, Cloud Functions, waitlist | `ascend-web-email` |
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
- `.github/workflows/ci.yml` - PR validation; `ci-required-check-fallback.yml` routes the required check for PRs that change no CI-relevant path (`ascend-deploy`)
- `.github/workflows/deploy-staging.yml`, `deploy-production.yml` - deploy pipelines (prod gated)
- `Gemfile`, `fastlane/Appfile`, `fastlane/Fastfile`, `fastlane/Matchfile` - build/signing/TestFlight
- `remoteconfig.template.json` - the kill-switch parameters; publish only via `scripts/deploy-remote-config.mjs`, never from CI (`docs/remote-config-kill-switches.md`)
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
