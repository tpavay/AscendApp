# Ascend Onboarding Design Guide

Last updated: May 27, 2026

## Source Read

Reference file: `Onboarding-For-Ascend`

Figma file key: `ednFZL8LsfbHXj63OBf30K`

Screens inspected:
- Puff Count splash, value carousel, survey, mirror/result screens, and paywall variants.
- Calorie tracking row for fitness-style demographic capture, goal questions, plan calculation, and trial entry.
- Period tracking row for sensitive personal question framing and soft emotional sequencing.
- Language learning row for gamified dark onboarding, progress, goals, streaks, and reward setup.
- Note taking row for productivity-style feature demos and plan selection.
- Ascend local assets and current SwiftUI onboarding scaffolds.

Key reference pattern:
Puff Count is the closest structural template. It uses a short value promise, a lightweight value carousel, survey transition, single-question survey screens, mirror/result screens, a loading/calculation beat, social proof, then paywall. Ascend should borrow that structure, not its soft visual tone.

## North Star

Ascend onboarding should make the user feel:

1. This app is for the stair stepper, not generic fitness.
2. My effort will be visible on a competitive field.
3. I can claim permanent status if I move before other people.
4. The subscription unlocks the thing I already want to enter.

The core promise:

> Race the world up real landmarks. From your stair stepper.

Do not soften this into exploration, wellness, or general activity tracking. The stair stepper and competition are the product.

## Reference Patterns To Copy

### Puff Count

What it does:
- Opens with a brand splash and a large social proof number.
- Shows four simple value screens on a clean background.
- Uses one centered illustration per screen.
- Places copy in the middle third and CTA near the bottom.
- Starts the survey with a transition screen: "Take the survey to get your plan."
- Uses one question per screen, a top progress bar, back, skip, and large pill options.
- Converts answers into a mirror result: "Based on your answers..."
- Uses a loading moment: "Creating your plan."
- Paywall starts with testimonial/social proof, then benefit bullets, then plan options.

Why it works:
- The first screen borrows trust before asking for effort.
- The value carousel keeps visual weight high and cognitive load low.
- The survey transition reframes questions as part of personalization, not setup.
- Mirror screens make the user feel seen before the paywall.
- The paywall sells a personalized outcome, not a generic subscription.

Ascend translation:
- Use the same funnel shape, but make the visuals darker, heavier, and more competitive.
- Replace community wellness proof with open First Ascents, leaderboards, and launch-wave urgency.
- Replace "custom plan" with "calibrated climb field" and "recommended first climb."

### Calorie Tracking

What it does:
- Uses direct demographic and body questions with low-friction single-choice rows.
- Creates a calculation reveal after user input.
- Shows plan/progress outcomes after the calculation.
- Uses a strong trial hook before subscription.

Why it works:
- Users tolerate personal fields when they believe the app is computing something for them.
- The calculation beat creates payoff for the friction.

Ascend translation:
- Demographics should come after auth, but before the final field reveal.
- The payoff is not a meal plan. It is a leaderboard-ready identity and smart first climb.
- Avoid implying a fake rank if there is no real field yet.

### Period Tracking

What it does:
- Frames sensitive questions calmly and personally.
- Uses soft progress, low-pressure copy, and small answer steps.
- Interleaves proof/stat screens with questions.

Why it works:
- Sensitive inputs feel less invasive when the app explains why each one matters.

Ascend translation:
- Age, weight, and location are public leaderboard context. Say that plainly.
- Do not bury public-use context in legal copy. Use direct microcopy near the fields - but only where the claim is true. A field whose public use will not survive an honest one-line description ships without a subtitle rather than with an invented one.
- Gender is the standing exception and carries no such line. See `21. Required Demographics`.

### Language Learning

What it does:
- Uses dark screens, bright progress, simple mascot moments, goals, streaks, and achievement previews.
- Turns setup into game setup.
- Makes the user feel like they are choosing a challenge lane.

Why it works:
- Progress, rewards, and streak setup make later subscription feel like joining the game.

Ascend translation:
- Treat onboarding like entering a competitive event.
- Use climb cards, rank rows, badges, and First Ascent art instead of mascot comedy.

### Note Taking

What it does:
- Uses feature screenshots, capability cards, and plan choices.
- Keeps feature explanations short and visual.

Why it works:
- It shows the product instead of describing it.

Ascend translation:
- Use real Ascend screenshots for feature demos.
- Use landmark photography and badge art for emotional hooks.

## Visual System

### Color

Use the existing Ascend dark system:

- Screen background: `#111111`
- Elevated panels/cards: `#1A1A1A`
- Deep black overlays: `#000000` at 28-82 percent depending on photo contrast
- Primary accent: `#86D30A`
- Primary text: `#FFFFFF`
- Secondary text: `#A8A8A8`
- Muted text: white at 56-72 percent opacity
- Borders: white at 10-24 percent opacity
- Active borders/glows: `#86D30A`
- Gold prestige: use only for First Ascent, Champion, and paywall premium accents

Do not make the onboarding a blue or wellness-colored flow. Puff Count's blue is structurally useful, not visually right for Ascend.

### Typography

Use Montserrat throughout.

Hero welcome headline:
- Font: Montserrat Bold
- Size: 34-38
- Line height: 38-43
- Alignment: centered
- Max width: 330-350
- Use one accent phrase max, usually `real landmarks`

Value carousel headline:
- Font: Montserrat Bold
- Size: 27-31
- Line height: 32-36
- Alignment: centered
- Max 2 lines
- Minimum scale factor allowed down to 0.74

Question headline:
- Font: Montserrat Bold
- Size: 33-37
- Line height: 39-43
- Alignment: leading
- Max 2-3 lines

Mirror/result headline:
- Font: Montserrat Bold
- Size: 30-35
- Line height: 36-41
- Alignment: leading or centered depending on visual

Paywall headline:
- Font: Montserrat Bold
- Size: 30-34
- Line height: 36-40
- Alignment: centered or leading

Eyebrow:
- Font: Montserrat SemiBold
- Size: 11-12
- Tracking: +1.2 to +1.8
- Uppercase
- Color: lime or muted white

Body/subtitle:
- Font: Montserrat Regular or Medium
- Size: 14.5-16
- Line height: 20-23
- Color: white at 68-76 percent opacity, or `#A8A8A8`

Answer option text:
- Font: Montserrat Medium or SemiBold
- Size: 15-16
- Line height: 20
- Selected state: white or black on lime depending on component

CTA:
- Font: Montserrat Bold
- Size: 16-17
- Height: 54-62
- Corner radius: 10-14
- Background: lime
- Text: black at 90 percent opacity
- No arrow icons in CTA buttons

Legal/restore copy:
- Font: Montserrat Regular
- Size: 11-12
- Color: white at 46-60 percent opacity

### Layout

Base frame:
- Target: iPhone 390 x 844 class
- Horizontal padding: 24-32
- Bottom CTA inset: safe area + 12-28
- Keep one primary action pinned near the bottom on every step.
- Avoid nested cards. Use one card layer only for answers, previews, or paywall plan rows.

Welcome:
- Full-bleed image background.
- Wordmark near top.
- H1 in upper third or lower third depending on image read.
- CTA at bottom.
- Sign-in link below CTA.
- Both bottom actions share one bottom safe-area inset so they cannot collide at large Dynamic Type; the sign-in row drops its `Already have an account?` prefix at accessibility sizes.

Value screens:
- Top 52-58 percent visual.
- Bottom 42-48 percent black panel or dark gradient.
- Text just above dots and CTA.
- Dots between copy and CTA.
- CTA advances pages; only the final value page goes to the next flow.

Survey/question screens:
- Top row: leading control, progress bar, optional skip only if the step is truly skippable.
  The leading control is a back button on every screen that has something behind it.
- Brand mark can appear on section starts, not every question if it creates vertical crowding.
- Question starts around 185-225 y on 844-height screens.
- Answers start 28-40 below headline.
- Option height: 50-58.
- Option spacing: 10-12.

Mirror/result screens:
- Visual proof object in top third.
- Result statement in middle.
- CTA at bottom.
- Use one strong number, badge, or leaderboard preview.
- Do not stack multiple dense cards.

Paywall:
- Header visual or testimonial at top.
- Product promise immediately under header.
- Benefits as 3 tight rows.
- Plan selector in lower middle.
- CTA fixed near bottom.
- Restore and terms below CTA.

## Imagery Direction

Use three categories of imagery:

1. Emotional hero images
   - Dark landmark photography
   - Mountain/route/rank visuals

2. Real product screenshots
   - `OnboardingGlobalClimbsScreenshot`
   - `OnboardingEmpireLeaderboardScreenshot`
   - `OnboardingWorkoutsScreenshot`
   - `OnboardingProgressScreenshot`

3. Prestige objects
   - `FirstAscentBadgeDetailed`
   - Champion crown badge when available
   - Trophy artwork
   - Tier-colored climb cards

Use real screenshots for "this app delivers" screens. Use badge art and landmark photography for motivation and First Ascent stakes. Use collection thumbnails when the screen is about "climbs collected" or smart first-climb recommendation.

Do not use generic fitness illustrations. The user should see landmarks, rank rows, climb cards, badges, or the Ascend interface.

## The Shipped Flow

There is one onboarding, and a signed-out climber gets it on every launch: the selling screens, the setup questions, then sign-in, where the flow ends.
`OnboardingV3Step` is the authority on the screens and their order, `OnboardingV3Coordinator` owns the navigation, and the enforced count of screens and their ordered IDs is the funnel contract in the `ascend-analytics` skill, not a number restated here.
What a climber without access meets after sign-in is the app-access gate, a Superwall paywall (`docs/superwall-paywall-setup.md`).

The earlier flow - a landing screen, a value carousel, a sign-in screen, then survey, demographic and first-climb questions after sign-in - was removed in 1.3.0, together with the `onboarding_v3_enabled` rollout that chose between the two.
It was removed rather than left behind the switch because a fresh install on a slow or blocked network fell back to it, and its city question could not be left when Apple Maps failed (Guideline 2.1(a), 2026-11-14).

A signed-in climber is never sent through questions.
A climber who signed in on an older build and never finished those questions meets the app-access gate on update, and sets the answers they skipped (gender, birthday, height and weight, city) from Profile, where each has an editor.
Nothing in the app waits on them: leaderboard filters and the profile read a missing value as unset.

The one screen that asks for a city, `OnboardingClaimCityScreen`, is optional.
Apple Maps is a network call, and a reviewer's network, a restricted one or any `MKError` ends a search the climber did nothing wrong in, so the screen carries a Skip in its header in every state, and a failed search says so beside it.
`OnboardingCityStepCannotTrapTests` fails a search on purpose, through `PostAuthCitySuggestionSource`, and holds that the Skip is still there and moves the climber on without a city.

### Permission messages - always followed by the request

Guideline 5.1.1(iv): a custom message that appears before a system permission request must always be followed by the request.
Apple rejected 1.3.0 (build 2026111701) on 2026-11-19 because screen 06, the Health connect message, carried a Skip.
Screens 06, 06b (the picture of the Health sheet) and 12 (the notification primer) therefore have one forward action each and no Skip, Not now or X; the header's Back is the only other control and it leaves the flow's earlier screens.
The climber's no is the iOS sheet's own Don't Allow, and the flow moves on whatever the answer was, or when the request could not be made, so declining never blocks onboarding.
`PrePermissionMessagesHaveNoWayOutTests` holds it, and any new screen that explains a permission before iOS asks joins that suite.

### Name - Resolved, Never Asked

There is no name screen, and one may not be added back.

App Review rejected 1.0 under Guideline 4 on 2026-08-20 because every Sign in with Apple climber was forced through a mandatory step demanding a first and last name that Authentication Services already supplies.
A better-prefilled screen is not the fix either.
`ASAuthorizationAppleIDCredential.fullName` is populated only on the FIRST authorization for an Apple ID and app pair and never again, so App Review's device - which has already spent that first authorization - always arrives with nothing, and a screen the reviewer cannot pass is the same rejection with extra steps.

Ascend resolves the name instead, on one provider-agnostic path, first hit wins, always terminating:

1. The Ascend profile Ascend already holds.
2. Whatever the provider supplied at this sign-in - Apple's once-only credential, or the display name Google supplies on every sign-in.
3. The placeholder first name `CHANGE`, last name `ME`.

A name typed on the v3 flow's pre-sign-in profile screen ranks between steps 1 and 2, on an account with no stored name - see the carve-out below.

`SuppliedNameAdoption.decide` is the single pure rule, and `AscendApp/Features/Authentication/SignInSuppliedIdentity.swift` owns it.
Deliberately not a per-provider branch: two branches are two things to drift.

Behavior:
- Never ask the climber for a name anywhere in onboarding, and never gate reaching the app on having one.
- Half a name - one part only - resolves to the placeholder rather than to a composed half, because there is nowhere left to ask for the missing part.
- A profile that could not be read defers to the next launch rather than guessing.
- The placeholder is deliberately an instruction rather than a plausible generated handle like `Climber 2A4F`, and it is written without asking.
- The name is changed only in Settings -> Edit Profile -> First name / Last name.
- A single supplied name string is split at the first whitespace: the first word becomes the first name and the remainder becomes the last name, so a multi-word family name survives intact.
  That split is how the display name Google and Firebase hand back on every sign-in is consumed.
- A profile that already resolves to a name is never overwritten, legacy `displayName`-only records included.
  Resolution writes only when the profile carries no name at all.

The one carve-out is the pre-sign-in profile screen of the flow (08, `OnboardingProfileSetupScreen`), which offers optional First name and Last name fields beside a photo, gender, birthday, height and weight.
It is not the rejected step: Skip and Continue both pass with the fields empty, and nothing waits on them.
What a climber types is held on the device and written after sign-in by the hand-off, which fills blanks only - it replaces a `CHANGE ME` placeholder and never a real name the account already carries.
A typed name outranks the provider's on an account with no stored name, because the screen shows the climber exactly that name: resolution sees one pending, writes nothing, and leaves it to the hand-off, which runs only after resolution has settled.
A stored real name still wins, so a returning climber keeps theirs, and the provider's name fills only when nothing usable was typed.
With `onboarding_answers_profile_write_enabled` off the hand-off cannot write, so resolution ignores a typed name and the provider's name or the placeholder lands; a real name landing that way then outranks the typed one when the switch comes back.
One half is a whole name here: the row previews it and the hand-off publishes it alone, with the other stored field empty.
A name `DisplayNamePolicy` refuses gets an inline hint, the row keeps the default name, and it is left out rather than blocking the rest, so the provider's name or the placeholder resolves instead.
A photo picked there waits on the device the same way and is uploaded through the existing profile photo path under `users/{uid}/profile_pictures/`, for an account that has none.
Do not make either field required, and do not add a name screen anywhere else.

## App Workflow Map

Use this as the organizing layer for product planning. The onboarding above is the entry ramp; the workflows below are the actual app loops those screens should prepare the user to enter.

### 1. Acquisition And Account Entry

User goal: understand the promise, trust the product, and create an account.

Primary path:
1. Welcome
2. Selling screens and setup questions
3. Auth

App surfaces:
- `OnboardingV3FlowView`
- `OnboardingAuthScreen`
- `AuthenticationViewModel`

State and data:
- Anonymous pre-auth state until provider sign-in.
- Firebase Auth owns identity after Apple / Google / email sign-in.
- Onboarding progress stays local per Firebase `uid` until remote onboarding state is intentionally added.

Success condition:
- User reaches authenticated onboarding without feeling like they entered a generic fitness app.

Design principle:
- Keep time to first value short. The value shown before auth is not a tutorial; it is proof that the app turns stair stepping into rank, First Ascents, and landmark completion.

### 2. Competitive Setup And First-Climb Routing

User goal: give enough context for Ascend to place them on a strong first climb.

Primary path:
1. Baseline qualifier
2. Problem mirror
3. Motivation
4. Frequency
5. Session length
6. Goal segmentation
7. Mirror moment
8. Calculation
9. Smart first-climb reveal

App surfaces:
- `OnboardingFirstClimbHandoffStore`, read only, until 1.4.0: a first climb a climber staged on 1.2 or earlier and had not yet carried into the app
- `MainTabView` climb-detail handoff

State and data:
- Survey answers are product personalization inputs, not a permanent training model unless explicitly promoted into profile schema.
- Smart first-climb recommendation should route to Climb Detail, not directly into a live attempt.
- Do not invent a fake rank, fake user count, or fake leaderboard field.

Success condition:
- User lands on a real climb detail screen with a clear target and a reason to start.

Design principle:
- Use progressive disclosure. Ask only what is needed to route the first competitive action; delay deeper stats, filters, and settings until the user has climbed.

### 3. Live Climb Attempt

User goal: start a landmark attempt and watch their real effort progress against the field.

Primary path:
1. Climb Detail
2. Start Live Climb
3. Headphone-motion tracking
4. Live replay race field
5. Target reached or user stops

App surfaces:
- `ClimbDetailView`
- Live climb session views and view models
- Headphone motion / step tracking services
- Live replay leaderboard services

State and data:
- Live Climb completions require live sensor data from the live attempt flow.
- Routine completions cannot complete a Live Climb or enter its leaderboard.
- Step tracking diagnostics should be collectable from this workflow because this is where algorithm quality matters.

Success condition:
- User understands where they are on the climb, who they are chasing, and whether they finished.

Design principle:
- Intent mirroring matters here: the UI should reflect the user's effort in real time, not explain the algorithm.

### 4. Completion, Public Result Sync, And Leaderboard

User goal: see what they earned, then see where the result sits in the public field.

Primary path:
1. Completion Summary
2. Local workout saved
3. Public result publish
4. Immutable rank-at-completion snapshot
5. Dynamic per-climb leaderboard
6. Retry sync if publication fails

App surfaces:
- `LiveClimbCompletionSummaryView`
- `LiveClimbPublicResultSyncStore`
- `ClimbDetailView` All Times page
- `LiveReplayLeaderboardService`
- `onWorkoutReplaySplitsWritten`

State and data:
- Summary metrics come from the local workout immediately.
- Rank-at-completion comes from the server snapshot and should not be faked locally.
- The per-climb leaderboard is dynamic and can change as new attempts publish.
- The user's finisher order is permanent, and so is the completion summary's rank and its denominator once the server has ranked the workout; the climb's live finisher count is the number that keeps growing. What each surface may assert is stated once in `ascend-leaderboards` under The rank model.
- Sync status is shared by workout id so retrying from one surface updates the others.

Success condition:
- The user never sees a rank paired with a denominator from a different population, and wherever the app can name what a figure counted it labels it, so summary, climb card, and leaderboard never read as contradicting each other.

Design principle:
- Treat publication failure as recoverable state. Show the saved workout, make rank status clear, and offer a small underlined `Retry sync` action only where it matters.

### 5. Workout History And Personal Progress

User goal: see that every stair session counted and improved the record book.

Primary path:
1. Workout saved by a live session
2. Workout Detail
3. Best Efforts recalculated
4. Progress / trends updated
5. Profile activity reflects the session

App surfaces:
- `WorkoutDetailView`
- `WorkoutListView`
- `BestEffortCacheEntry`
- Progress and profile sections

State and data:
- `Workout` is the canonical activity.
- Best Efforts are derived from workouts, never authored directly.
- Edits, deletes, imports, and live completions must all trigger derived-data repair.

Success condition:
- A user can trust that history, records, and profile totals agree.

Design principle:
- This is value replay. Use it to reinforce the work the user already did, not to introduce a separate dashboard-first product.

### 6. Routines

User goal: run an interval-based stair session when they want structure instead of a landmark target.

Primary path:
1. Browse routines
2. Routine detail
3. Start routine
4. Complete intervals or end early
5. Save workout
6. Routine result / history

App surfaces:
- Routine browse, detail, active session, and result surfaces
- Shared workout mutation pipeline

State and data:
- Routines are a first-class peer to climbs.
- Routine completions come only from the live routine flow.
- Routine workouts still produce canonical workouts and personal progress, but they do not complete Live Climbs.

Success condition:
- The user gets guided structure without confusing routines with landmark competition.

Design principle:
- Keep the distinction simple: climbs are fixed destinations; routines are guided interval sessions.

### 7. Apple Health Enrichment

User goal: see heart rate and calories on a climb they ran in Ascend.

Primary path:
1. Connect Apple Health from onboarding's screen 06, Settings -> Integrations, or the Climb sheet's Connect Health (`docs/apple-health-import.md`)
2. Silent enrichment of climbs Ascend recorded, retried on a bounded persisted schedule until Health writes the samples
3. Heart rate and calories appear on workout detail once they exist

App surfaces:
- Settings -> Integrations - Apple Health card and manage sheet, the only surface that explains revoked access, and where Import automatically and Import older workouts live (`docs/apple-health-import.md`)
- `AppleHealthEnrichmentService`
- Workout detail heart-rate chart, shown only when a series exists

State and data:
- Apple Health is read-only. Enrichment reads `heartRate` and `activeEnergyBurned` over a climb's own time window and never touches a foreign `HKWorkout`; importing stair workouts is a separate service (`docs/apple-health-import.md`).
- Enrichment is silent about its *results*. It never asks the climber to confirm or edit merged data.
- The Live Climb completion summary and workout detail are deliberately silent about absence: chart when a stored series exists, nothing at all when it does not, while enrichment keeps looking on its schedule (#438).
  Workout detail still shows its remote-series restore state, which means data exists and is arriving, not that the climb has no heart rate.
  No view resolves a per-climb Apple Health status to narrate.
  Contract: `ascend-apple-health-enrichment`.
- A live-captured chest-strap series outranks Health's wrist data; enrichment still fills calories.

Success condition:
- A climb shows what it cost the climber without any of Ascend's numbers coming from somewhere it cannot stand behind.

Design principle:
- A screen that celebrates a climb never begs for a permission.
  The ask lives in Settings -> Integrations, where a climber goes to manage connections, and the result surfaces show earned data or nothing.

### 8. Profile, Collection, And Prestige

User goal: see identity, claimed climbs, First Ascents, records, and standing in one durable place.

Primary path:
1. Own Profile
2. Identity and lifetime stats
3. Collection preview
4. Active standings
5. First Ascents and achievements
6. Records and trends
7. Recent workouts

App surfaces:
- `OwnProfileView`
- `OtherUserProfileView`
- Collection, standings, achievements, records, trends, and activity sections

State and data:
- Own profile can show activation empty states.
- Other-user profile hides empty sections unless comparison needs explanation.
- Public profile reads must use public-safe documents and mirrors, never private workout backups.

Success condition:
- The profile feels like a competitive record, not a social feed.

Design principle:
- Prestige is a retention loop. First Ascents, active standings, and records should be more prominent than generic activity recap.

### 9. Share Sheet

User goal: turn a climb or workout result into a share asset.

Primary path:
1. Open share from summary or workout detail
2. Pick a preset card and its background, or switch to Stickers
3. Copy, save, or send the card to a Story
4. Tap a sticker to copy it, hold to save it

App surfaces:
- Share sheet
- Presets tab and its customization bar
- Stickers tab
- Image export pipeline

State and data:
- Stickers read from canonical workout and climb result data.
- Cards and stickers are rendered on device from one subject built from the saved climb.
- The share sheet never becomes the source of truth for metrics.

Success condition:
- Sharing converts pride into growth without adding a social network.

Design principle:
- Make the proud moment portable. The best share prompt happens after a real completion, record, rank, or First Ascent claim.

### 10. Monetization And Access

User goal: understand what the subscription unlocks and start climbing.

Primary path:
1. Paywall priming
2. Hard paywall
3. Purchase or restore
4. Entitlement resolves
5. App access

App surfaces:
- Superwall paywall placement
- RevenueCat entitlement service
- App access gate
- Restore purchase path

State and data:
- Superwall owns paywall presentation and onboarding-step conversion analytics.
- RevenueCat owns purchases, restore, and entitlement truth.
- Paywall copy should sell the field: climbs, leaderboards, First Ascent windows, records, and history sync.

Success condition:
- The paywall feels like the next step into the competitive field, not a generic blocker.

Design principle:
- Show after commitment and value preview. The user should understand what they are about to enter before being asked to pay.

### 11. Reliability, Analytics, And Diagnostics

User goal: have the app recover from failures without losing climb work.

Primary path:
1. Local-first save
2. Sync coordinator processes remote work
3. Publication / backup succeeds
4. Shared status updates UI
5. Retry handles recoverable failure
6. Crash/error analytics capture failure context

App surfaces:
- Connectivity indicator
- Public result sync status
- Workout sync coordinator
- Firebase Analytics / Crashlytics
- Debug/export tooling

State and data:
- Local save and public publication are separate states.
- Online does not guarantee success; failed requests need shared categorization and retry mechanics.
- Step-tracking diagnostics should be structured so an AI agent can inspect climb attempts, sensor samples, algorithm version, device, and error state.

Success condition:
- A user can finish a climb on a bad connection, keep the workout, retry publication, and never see contradictory leaderboard state.

Design principle:
- Reliability is part of the product experience. When ranking is the app's core promise, sync state must be explicit, centralized, and testable.

## Component Specs

> **History.** This section describes the removed 1.2 onboarding flow and is kept as history.
> For the current flow, read [The Shipped Flow](#the-shipped-flow); `OnboardingV3Step` is the authority on its screens and their order.

### Answer Option Row

Default:
- Height: 54
- Radius: 10
- Fill: `#1A1A1A` at 92-100 percent or black at 28 percent over image
- Border: white 18 percent, 1 px
- Text: Montserrat Medium 15.5, white 86 percent

Selected:
- Border: lime, 1.5 px
- Fill: lime 10-16 percent, or full lime only for high-confidence selection screens
- Checkmark optional on multi-select only

Disabled:
- Opacity 45 percent

### Progress Bar

Use the existing top progress pattern:
- Track: white 22 percent
- Fill: lime
- Height: 4
- Animation: 0.22 ease in/out
- Leading control left, progress centered between it and the right padding

### CTA

Keep existing `OnboardingPrimaryCTAButtonStyle` with:
- Height: 54-62 depending on screen
- Radius: 10-14
- Font: Montserrat Bold 16-17
- No arrow icons
- Press scale: 0.985 is fine

### Ghost First Ascent Row

Open:
- Opacity: 40-50 percent
- Header label: `FIRST ASCENT`
- Name: `OPEN`
- Subtitle: `Awaiting first finisher`
- Time: `--:--:--`
- Body: `The first finisher claims this row forever.`
- CTA treatment: text/button `Climb to claim` with no arrow icon
- Pulse: border opacity from 18 to 42 percent over 2 seconds

Claimed:
- Full opacity
- Gold border/glow
- Real avatar/name/time/demographics
- Footer: `Held since [date] - forever`

## Copy Rules

Use:
- Active verbs
- Short headlines
- Concrete nouns
- Stakes
- Rank, climb, race, claim, push, track

Avoid:
- Explore
- Discover
- Learn
- Maybe
- Could
- Feel free
- Generic fitness claims
- Social-network language

Empty states:
- State, then action.
- Example: `No completed times yet. Climb first and set the mark.`

Question copy:
- Ask one thing per screen.
- Avoid long explanations above answer rows.
- Put context in a single subtitle only when the field is sensitive or public.

CTA copy:
- `Continue`
- `Start`
- `Build My Field`
- `View Climb`
- `Turn On Notifications`
- Paywall CTAs switch with the selected plan - see `### 24. Paywall`.

Do not use arrow icons on CTAs.

## Animation

> **History.** This section describes the removed 1.2 onboarding flow and is kept as history.
> For the current flow, read [The Shipped Flow](#the-shipped-flow); `OnboardingV3Step` is the authority on its screens and their order.

Use animation sparingly:

- Value carousel: horizontal paging, dot transition, screenshot parallax no more than 4-8 points.
- Route line: draw upward during loading.
- First Ascent ghost row: slow border pulse.
- Smart climb reveal: landmark card rises 12-18 points and fades in.
- Paywall: selected plan border brightens, not bouncy.
- Notifications: badge glint once, not looping aggressively.

Avoid:
- Confetti before a real success.
- Heavy mascot-style motion.
- Decorative gradient blobs.
- Long loading screens that feel fake.

## Implementation Notes

Current local assets already support the direction:
- `OnboardingGlobalClimbsScreenshot`
- `OnboardingEmpireLeaderboardScreenshot`
- `OnboardingWorkoutsScreenshot`
- `OnboardingQuestionsBackground`
- `FirstAscentBadgeDetailed`

Current SwiftUI scaffolds already match much of this:
- `OnboardingPrimaryCTAButtonStyle`
- `AscendWordmark`

Build order:
- Use the workflow build plan below as the source of truth. It keeps onboarding, profile setup, paywall, Live Climb activation, and retention work grouped around coherent app states instead of isolated screens.

## Reference Pattern Mapping

> **History.** This section describes the removed 1.2 onboarding flow and is kept as history.
> For the current flow, read [The Shipped Flow](#the-shipped-flow); `OnboardingV3Step` is the authority on its screens and their order.

| Phase | Reference Pattern | Ascend Version |
|---|---|---|
| Welcome | Puff Count splash with big proof and logo | Full-bleed mountain/rank visual, wordmark, `Race the world up real landmarks` |
| Value prop | Puff Count simple illustration carousel | Dark product screenshot carousel with globe, leaderboard, FA badge |
| Survey entry | Puff Count "Take the survey" transition | `Set up your first climb` / `Takes 1 minute` |
| Question flow | Puff Count single-question rows | Ascend baseline, motivation, volume, goals |
| Sensitive fields | Period tracking calm personal questions | Direct public leaderboard context for demographics |
| Calculation | Calorie/Puff plan creation | `Calibrating your climb field` |
| Reveal | Calorie plan result | Smart first climb plus leaderboard-ready profile |
| Gamification | Language streaks/goals | First Ascents, records, ranks, climb collection |
| Social proof | Puff testimonials and user count | Launch-wave scarcity now; real users/testimonials later |
| Paywall | Puff testimonial plus benefits plus plan selector | First Ascent/leaderboard visual plus yearly trial plan |

## Workflow Build Plan

> **History.** This section describes the removed 1.2 onboarding flow and is kept as history.
> For the current flow, read [The Shipped Flow](#the-shipped-flow); `OnboardingV3Step` is the authority on its screens and their order.

Build in workflow order, not screen order. Each workflow should leave the app in a coherent, testable state before moving to the next one.

### Phase 1 — Account Entry And First Value

Ship:
- Welcome.
- Value carousel with 4 screens.
- Auth entry.
- Carousel CTA progression fix.

Verify:
- New user can move from first launch to authenticated root.
- Returning user skips completed onboarding.
- Interrupted onboarding resumes at the correct stage.

### Phase 2 — Competitive Setup

Ship:
- Survey transition.
- Baseline, motivation, volume, session size, and goal questions.
- Calculation/loading screen.
- Smart first-climb reveal.
- First-climb handoff to Climb Detail.

Verify:
- First-climb recommendation never routes straight into a live attempt.
- No fake leaderboard users, ranks, or completion counts appear.
- Survey answers are stored only where intentionally modeled.

### Phase 3 — Required Profile And Permission Serve

Ship:
- Gender, birthday, weight, and location capture.
- Value reveal.
- Notification opt-in framed around First Ascent drops.

Verify:
- No screen anywhere in onboarding asks for a name; the account already carries one by the time the survey opens.
- Profile fields match `ProfileGender` raw values, and the birthday resolves to an age inside the bounds.
- Firestore rules allow only the intended profile fields.
- Native notification prompt is served after the in-app value frame, not before.

### Phase 4 — Monetization Gate

Ship:
- Superwall paywall layout using this structure.
- Yearly highlighted plan.
- Restore path.
- RevenueCat entitlement resolution.

Verify:
- Paywall appears after setup/value preview.
- Entitlement state gates app access consistently.
- Restore works for returning subscribers.

### Phase 5 — Core App Activation

Ship:
- Climb Detail handoff from onboarding.
- Start Live Climb path.
- Completion Summary.
- Public result sync status.
- Per-climb leaderboard consistency.

Verify:
- A completed Live Climb saves locally before public publication.
- Rank-at-completion uses the server snapshot.
- Retry sync updates all relevant screens through one shared state source.

### Phase 6 — Retention Loops

Ship:
- Workout history.
- Best Efforts / records.
- Profile collection and prestige sections.
- Share sheet entry from real results.

Verify:
- Workout mutations repair derived data.
- Profile counts agree with workout history and public leaderboard state.
- Share stickers read canonical result data, not copied metrics.

## Workflow Analytics Plan

Track analytics by workflow so the dashboard can answer where the app is losing users and where the core loop is breaking.

### Account Entry
- Screen view per welcome/value/auth screen.
- CTA tap per screen.
- Auth provider selected.
- Auth completed.
- Auth failed with provider and safe error category.

### Competitive Setup
- Survey started.
- Question answered with bucketed answer values, no raw PII.
- Survey completed.
- Smart first climb generated with recommendation tier and climb id.
- First-climb detail opened.

### Profile And Permissions
- Demographics completed by field, no raw PII in analytics.
- Notification pre-prompt shown.
- Native notification prompt accepted or declined.

### Monetization
- Paywall shown with placement and variant.
- Plan selected.
- Trial started.
- Purchase completed.
- Purchase failed with safe error category.
- Restore started and completed.

### Live Climb Activation
- Live Climb started.
- Target climb id and tier.
- Attempt completed, abandoned, or failed.
- Completion Summary viewed.
- Step-tracking algorithm version.
- Device model, OS version, and sensor path.

### Public Result Sync
- Workout saved locally.
- Remote workout backup started, succeeded, or failed.
- Public leaderboard publish started, succeeded, or failed.
- Retry sync tapped.
- Retry sync succeeded or failed.
- Rank snapshot created with rank bucket and completed-count bucket.

### Retention And Growth
- Workout Detail viewed.
- Best Effort earned.
- Profile viewed.
- Collection card tapped.
- Share sheet opened.
- Share exported.
- Share target selected when available.

### First A/B Tests After Launch

Welcome headline:
- `Race the world up real landmarks.`
- `The stair stepper finally has a field.`

Calculation reveal:
- Smart first climb reveal.
- Leaderboard-ready profile reveal.

Social proof:
- Launch-wave scarcity.
- Early tester quote.

Paywall headline:
- `Unlock The Field`
- `Start Climbing For Rank`
