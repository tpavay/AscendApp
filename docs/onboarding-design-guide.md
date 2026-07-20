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
- Age, gender, weight, and location are public leaderboard context. Say that plainly.
- Do not bury public-use context in legal copy. Use direct microcopy near the fields.

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
- Login link below CTA.

Value screens:
- Top 52-58 percent visual.
- Bottom 42-48 percent black panel or dark gradient.
- Text just above dots and CTA.
- Dots between copy and CTA.
- CTA advances pages; only the final value page goes to the next flow.

Survey/question screens:
- Top row: back button, progress bar, optional skip only if the step is truly skippable.
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
   - `OnboardingWelcomeBackground`
   - `AuthStaircaseBackground`
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

## Recommended Flow

This is the V1 flow to ship. It lands at 21 screens before the paywall if auth and demographics are counted as onboarding.

### 1. Welcome

Purpose: recognition.

Copy:
- Headline: `Race the world up real landmarks.`
- Subhead: `From your stair stepper.`
- CTA: `GET STARTED`
- Secondary: `Already have an account? Log in`

Visual:
- Use `OnboardingWelcomeBackground`.
- Keep wordmark small and premium.
- Accent only `real landmarks`.

### 2. Value - Climb Real Landmarks

Copy:
- Headline: `Climb Real Landmarks`
- Subtitle: `Take on the Empire State Building, Eiffel Tower, Everest, and more from your stair stepper.`
- CTA: `Continue`

Visual:
- Use globe screenshot plus a horizontal strip of the 10 launch landmark thumbnails.
- Show tier-colored borders.

### 3. Value - See Where You Stand

Copy:
- Headline: `See Where You Stand`
- Subtitle: `Every climb has a leaderboard. Every session has a rank.`
- CTA: `Continue`

Visual:
- Use `OnboardingEmpireLeaderboardScreenshot`.
- Highlight the user's row in lime.

### 4. Value - Earn First Ascents

Copy:
- Headline: `Claim It First`
- Subtitle: `First Ascent open. The first finisher claims it forever.`
- CTA: `Continue`

Visual:
- Use `FirstAscentBadgeDetailed`.
- Add a ghost FA row below the badge: `OPEN`, `Awaiting first finisher`, `--:--:--`.

### 5. Survey Transition

Purpose: convert setup friction into personalization.

Copy:
- Eyebrow: `BUILD YOUR FIELD`
- Headline: `Set up your first climb.`
- Subtitle: `Answer a few questions so Ascend can place you on the right start line.`
- Time note: `Takes 1 minute`
- CTA: `Start`

Visual:
- Minimal field/map line art or the angular A mark over a faint route line.

### 6. Baseline Qualifier

Copy:
- Eyebrow: `STAIR STEPPER BASELINE`
- Headline: `How would you describe your stair stepper experience?`
- Options:
  - `Just getting started`
  - `Some experience`
  - `Regular`
  - `Serious athlete`
  - `I do not use a stair stepper`
- CTA: `Continue`

Behavior:
- If the user chooses `I do not use a stair stepper`, show a graceful exit/soft redirect:
  - `Ascend is built for the stair stepper.`
  - `Come back when you are ready to climb.`

### 7. Problem Mirror Question

Copy:
- Eyebrow: `THE PROBLEM`
- Headline: `What makes stair sessions easy to waste?`
- Options:
  - `No clear target`
  - `No reason to push`
  - `No record of progress`
  - `No one to race`
  - `They already count for me`
- CTA: `Continue`

### 8. Motivation Question

Copy:
- Eyebrow: `COMPETITIVE PULL`
- Headline: `What pulls more effort out of you?`
- Options:
  - `Beating my last result`
  - `Passing other climbers`
  - `Claiming a first`
  - `Finishing a hard target`
  - `Keeping a streak alive`
- CTA: `Continue`

### 9. Frequency Question

Copy:
- Eyebrow: `CURRENT VOLUME`
- Headline: `How often do you use the stair stepper?`
- Options:
  - `Less than once a week`
  - `1-2 times a week`
  - `3-4 times a week`
  - `5+ times a week`
- CTA: `Continue`

### 10. Session Length Question

Copy:
- Eyebrow: `SESSION SIZE`
- Headline: `How long is a typical stair session?`
- Options:
  - `Under 10 minutes`
  - `10-20 minutes`
  - `20-40 minutes`
  - `40+ minutes`
- CTA: `Continue`

### 11. Goal Segmentation

Copy:
- Eyebrow: `TRAINING TARGET`
- Headline: `What are you climbing for?`
- Subtitle: `Choose up to 2.`
- Options:
  - `Better endurance`
  - `Weight loss`
  - `Stronger legs and glutes`
  - `Training for races/events`
  - `Hiking and outdoor performance`
  - `Long-term health`
- CTA: `Continue`

Behavior:
- Max 2 selections.
- Selected options use lime fill or lime stroke.

### 12. Mirror Moment

Purpose: name the user's situation before showing the solution.

Copy:
- Headline: `Your stair work needs a field.`
- Body: `You are not here to log cardio. You are here to climb, race, rank, and make the work count.`
- CTA: `Build My Field`

Visual:
- Leaderboard silhouette with the user's row empty.
- Keep it dark and direct.

### 13. Calculation / Loading

Copy:
- Headline: `Calibrating your climb field`
- Progress labels:
  - `Reading your baseline`
  - `Choosing your first climb`
  - `Opening leaderboard divisions`
  - `Checking First Ascent windows`

Visual:
- Route line animates upward.
- Lime progress bar.
- No fake percentages unless the timer maps to real progress.

### 14. Smart First-Climb Reveal

Copy:
- Headline: `Start with [Landmark].`
- Subtitle examples:
  - Beginner: `Statue of Liberty is your first clean target. Finish it, then climb bigger.`
  - Some experience: `Space Needle gives you a real climb without burying the first win.`
  - Regular: `Empire State Building puts you on the board fast.`
  - Serious athlete: `Burj Khalifa is open. Prove the engine.`
- CTA: `View Climb`

Visual:
- Landmark card with steps, estimated time, tier, and FA state.
- Do not route straight into live attempt. Route to climb detail.

### 15. Feature Demo - Live Climbs

Copy:
- Headline: `Race The Climb Live`
- Subtitle: `Pick a landmark. Start the attempt. Watch the field move as you climb.`
- CTA: `Continue`

Visual:
- Live replay leaderboard screenshot or live attempt mock.
- The user's row should be visually anchored.

### 16. Feature Demo - Records

Copy:
- Headline: `Beat Your Records`
- Subtitle: `Best Efforts turn every stair session into a record book.`
- CTA: `Continue`

Visual:
- Use progress/record screenshot.
- Show one record, not a dense analytics dashboard.

### 17. Feature Demo - Collection

Copy:
- Headline: `Collect Climbs`
- Subtitle: `Every landmark you finish becomes part of your climb history.`
- CTA: `Continue`

Visual:
- Use 3-card collection preview.
- Copy must say `Climbs collected`, not completed.

### 18. Launch Social Proof / Scarcity

Launch-safe copy:
- Headline: `The first field is forming.`
- Subtitle: `Launch climbs open with empty First Ascent slots. Move early or watch someone else claim them.`
- CTA: `Continue`

Post-launch copy when real proof exists:
- Headline: `The field is real.`
- Subtitle: `Climbers in your league are racing right now.`

Rules:
- Do not fake user counts.
- Use early tester quotes only if they are real.
- Until real numbers exist, use scarcity from open First Ascents and launch-wave framing.

### 19. Auth

Copy:
- Headline: `Enter The Field`
- Subtitle: `Save your climbs, ranks, and First Ascent claims.`
- Buttons:
  - `Continue with Apple`
  - `Continue with Google`
  - `Continue with Email`
- Legal: inline Terms and Privacy links.

Visual:
- Use `AuthStaircaseBackground`.
- Use angular A mark and/or `AscendWordmark`.
- Keep provider buttons familiar and high contrast.

### 20. Display Name

Copy:
- Eyebrow: `FIRST THINGS FIRST`
- Headline: `What should we call you?`
- Placeholder: `Enter your name`
- Microcopy: `This is the name climbers see on leaderboards.`
- CTA: `Continue`

### 21. Required Demographics

Break into low-friction screens unless the combined form remains clean:

Gender:
- Headline: `Choose your division.`
- Body: `Gender helps place you in leaderboard context.`
- Options use `ProfileGender` raw values:
  - `Woman`
  - `Man`
  - `Non-binary`
  - `Prefer not to say`

Age:
- Headline: `How old are you?`
- Body: `Age keeps leaderboard context honest.`
- Input: bounded 13 through 120.

Weight:
- Headline: `What is your body weight?`
- Body: `Weight can appear in profile and leaderboard-adjacent context.`
- Input: respect current measurement system.

Location:
- Headline: `Where are you climbing from?`
- Body: `Region gives the field a place.`
- Input: country/region first, city optional only if product wants it.

Use direct public-context copy. Do not hide that these fields may appear on profiles and leaderboard-adjacent surfaces.

### 22. Value Reveal

Copy:
- Headline: `You're on the field.`
- Subtitle: `Your profile is ready. Your first climb is waiting.`
- CTA: `Continue`

Visual:
- Leaderboard preview with the user's display name, demographic context, and smart first climb.
- If there are no real competitors yet, show empty-slot structure instead of fake people.

### 23. Notifications

Copy:
- Headline: `Never miss a First Ascent.`
- Subtitle: `Get 24-hour notice before each climb drop. Move before the field catches it.`
- CTA: `Turn On Notifications`
- Secondary: `Not Now`

Visual:
- First Ascent badge plus clock/drop card.
- This is a single ask. Do not bundle other permission requests.

### 24. Paywall

Purpose: make subscription the natural next click.

Headline options:
- `Unlock The Field`
- `Start Climbing For Rank`
- `Race Every Landmark`

Recommended paywall structure:
1. Top visual: First Ascent badge or active leaderboard card.
2. Promise: `Every climb, every leaderboard, every First Ascent window.`
3. Benefits:
   - `Race live climbs`
   - `Claim First Ascents`
   - `Track records and trends`
   - `Sync and protect your climb history`
4. Plan selector:
   - Yearly highlighted: `Best value`
   - Trial copy: `Start with a free trial.`
   - Monthly: `Pay as you go`
5. CTA:
   - Trial available: `Start Free Trial`
   - No trial: `Start Climbing`
6. Footer:
   - `Restore Purchase`
   - `Terms`
   - `Privacy`

Pricing display:
- Show yearly as the default selected plan.
- Show monthly as the comparison plan.
- Avoid weekly in V1 unless the pricing strategy is locked.

## App Workflow Map

Use this as the organizing layer for product planning. The numbered onboarding screens above are the entry ramp; the workflows below are the actual app loops those screens should prepare the user to enter.

### 1. Acquisition And Account Entry

User goal: understand the promise, trust the product, and create an account.

Primary path:
1. Welcome
2. Value carousel
3. Survey transition
4. Auth

App surfaces:
- `LandingScreen`
- `OnboardingValueCarouselView`
- `SignUpView`
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
- `PostAuthOnboardingFlowView`
- `OnboardingFirstClimbHandoffStore`
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
- Manual entries, imports, and routines cannot complete a Live Climb or enter its leaderboard.
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
- `ClimbDetailView` leaderboard tab
- `LiveReplayLeaderboardService`
- `onWorkoutReplaySplitsWritten`

State and data:
- Summary metrics come from the local workout immediately.
- Rank-at-completion comes from the server snapshot and should not be faked locally.
- The per-climb leaderboard is dynamic and can change as new attempts publish.
- The user's finisher order is permanent; its denominator grows as more users complete the climb.
- Sync status is shared by workout id so retrying from one surface updates the others.

Success condition:
- The user never sees contradictory rank/count numbers between summary, climb card, and leaderboard.

Design principle:
- Treat publication failure as recoverable state. Show the saved workout, make rank status clear, and offer a small underlined `Retry sync` action only where it matters.

### 5. Workout History And Personal Progress

User goal: see that every stair session counted and improved the record book.

Primary path:
1. Workout saved or imported
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

### 7. Import And Enrichment

User goal: bring in stair-stepper work from Apple Health without corrupting Live Climb integrity.

Primary path:
1. Connect Apple Health
2. Auto-import starts from activation timestamp
3. Latest unseen import review
4. Save or clean up imported workout
5. Silent enrichment for matching Live Climbs

App surfaces:
- Import flow
- `WorkoutImportCoordinator`
- HealthKit integration services
- Workout review/edit surfaces

State and data:
- External imports are read-only from the source platform.
- Apple Health workouts that enrich existing Live Climbs do not enter the manual review queue.
- Imported workouts can contribute to logs and personal records, but not Live Climb leaderboard completions.

Success condition:
- The user's history becomes more complete without weakening leaderboard trust.

Design principle:
- Permission requests should be served at the point of value. Ask for Health access when the user is trying to import or enrich workouts, not as generic onboarding setup.

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

### 9. Share Composer

User goal: turn a climb or workout result into a composed share asset.

Primary path:
1. Open share from summary or workout detail
2. Pick background or preset
3. Add stat stickers
4. Arrange stickers
5. Export or share

App surfaces:
- Share composer
- Background picker
- Sticker editor
- Photo/video export pipeline

State and data:
- Stickers read from canonical workout and climb result data.
- Backgrounds and stats stay independent.
- The composer never becomes the source of truth for metrics.

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
- Back button left, progress centered between back and right padding

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
- `Start Free Trial`
- `Start Climbing`

Do not use arrow icons on CTAs.

## Animation

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
- `OnboardingWelcomeBackground`
- `OnboardingGlobalClimbsBackground`
- `OnboardingGlobalClimbsScreenshot`
- `OnboardingEmpireLeaderboardScreenshot`
- `OnboardingWorkoutsScreenshot`
- `OnboardingProgressScreenshot`
- `OnboardingQuestionsBackground`
- `AuthStaircaseBackground`
- `FirstAscentBadgeDetailed`
- `HomeMyGlobeArtwork`

Current SwiftUI scaffolds already match much of this:
- `LandingScreen`
- `OnboardingValueCarouselView`
- `OnboardingValueShowcaseChrome`
- `OnboardingPrimaryCTAButtonStyle`
- `AscendWordmark`

Build order:
- Use the workflow build plan below as the source of truth. It keeps onboarding, profile setup, paywall, Live Climb activation, and retention work grouped around coherent app states instead of isolated screens.

## Reference Pattern Mapping

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
- Display name.
- Gender, age, weight, and location capture.
- Value reveal.
- Notification opt-in framed around First Ascent drops.

Verify:
- Profile fields match `ProfileGender` raw values and age bounds.
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
- Share composer entry from real results.

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
- Display name completed.
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
- Share composer opened.
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
