# App Store listing proposal: racing repositioning

Locale: en-US.
Status: **proposal**, not applied.

This file is a proposal for issue [#439](https://github.com/tpavay/AscendApp/issues/439).
Nothing here has been written to App Store Connect.
Firstmate owns App Store Connect metadata and applies it.

Every claim below was re-verified against build `2026081101` (commit `650acdbc`) on 2026-08-11, after the pre-submission audit found the live description and the live App Review notes both selling manual workout entry and Apple Health workout import - two features [#437](https://github.com/tpavay/AscendApp/issues/437) deleted on 2026-08-08.
That is Guideline 2.1 and 2.3, so both are submission blockers.
The claim-by-claim evidence is in [Traceability](#traceability); the replacement review notes are in [App Review notes](#app-review-notes).

The currently-live listing copy is recorded in `data/ascend-support-page-and-product-page-package/app-store-copy.md`.
That file still describes the tracking product.
It should be updated to match whatever is actually applied to App Store Connect, and only then, so the repo keeps exactly one record of what is live.

## What this copy assumes about the app

Written against the app as it stands after [#437](https://github.com/tpavay/AscendApp/issues/437), which merged on 2026-08-08.

Gone: Apple Health workout import, manual workout logging, and any framing of Ascend as a place to log or import training.
Kept: connecting Apple Health to enrich a climb performed *in Ascend*, live heart rate from a Bluetooth chest strap, Live Climbs, leaderboards, First Ascents, Best Efforts, guided routines, and the share composer.

For that enrichment, Ascend reads exactly two Apple Health types - heart rate and active energy - over the climb's own time window, and attaches your heart rate and active-energy calories to that climb.
It never requests `workoutType()`, so Workouts does not appear in the Health permission sheet, and it never writes to Apple Health.
`HealthKitAuthorizationClient.readTypes` is the authority for that set; the legal pages, the `Info.plist` usage string, and the App Store data answers all have to match it.

The live App Review notes describe the same two deleted features, so they are replaced wholesale by [App Review notes](#app-review-notes) below.

## App name

```text
Ascend: Stair Stepper Racing
```

28 characters of 30.
Settled by the captain on 2026-08-08.

## Subtitle

```text
Race real towers from any gym
```

29 characters of 30.
Settled by the captain on 2026-08-08.

## Keywords

```text
climber,stepmill,climb,steps,cardio,leaderboard,running,vertical,workout,compete,records,stairs,hiit
```

100 bytes of 100.

### How this set was derived

Apple indexes the app name and subtitle alongside the keyword field and combines tokens across all three into phrases.
The name supplies `ascend`, `stair`, `stepper`, `racing`; the subtitle supplies `race`, `real`, `towers`, `gym`.
None of those are repeated here, because a repeat buys nothing and costs bytes.

| Keyword | Why it earns its bytes |
|---|---|
| `climber` | Combines with the name's `stair` to cover "stair climber", the second most common name for the machine after StairMaster. |
| `stepmill` | The third common name for the machine, and a term nobody searching for a general fitness app types. |
| `climb` | The product's own verb, and the root of the queries that describe what Ascend does rather than what it runs on. |
| `steps` | Ascend's canonical metric, and the unit every climb target is expressed in. |
| `cardio` | The broadest term where a stair-stepper app has any legitimate claim, and the category a stepper user self-identifies with. |
| `leaderboard` | The differentiator. Anyone searching this is searching for competition, which is exactly the customer. |
| `running` | Only here to form "tower running" with the subtitle's `towers`, which is the name of the real sport this product is. |
| `vertical` | Forms "vertical climb" and reaches the Vertical World Circuit vocabulary that tower-running athletes already use. |
| `workout` | Discovery, not positioning. Machine queries are habitually phrased as "stairmaster workout" or "stair workout", and losing that traffic buys nothing. |
| `compete` | The intent word. Pairs with `climb`, `steps`, and the name to reach competitive rather than passive searchers. |
| `records` | Covers Best Efforts intent, "stair records" and "climb records". The weakest term in the set and the first to cut if something better appears. |
| `stairs` | Apple's plural handling is inconsistent, and `stairs` is how people actually type the query. Cheap insurance on the single most important token. |
| `hiit` | Four bytes for the routines feature and a high-volume interval-training query. Fills the field exactly. |

### Deliberately excluded

**`stairmaster`.** This is the highest-volume query in the category and the single biggest judgment call in the set.
It is also a registered trademark of Core Health & Fitness, which Ascend does not own.
Third-party marks in metadata are a routine App Review rejection under Guideline 5.2.1, and a metadata rejection on a first submission costs a review cycle at exactly the wrong moment.
Recommendation: launch without it.

If the captain accepts that risk, swap it in for `leaderboard`, which is the same 11 bytes:

```text
climber,stepmill,climb,steps,cardio,stairmaster,running,vertical,workout,compete,records,stairs,hiit
```

100 bytes of 100.

**`everest`, and mountain names generally.**
[#440](https://github.com/tpavay/AscendApp/issues/440) is curating unraceable mountains out of the catalogue.
Indexing on content that is being removed is a keyword spent on a promise the app will stop keeping.

**`treadmill`, `elliptical`, `peloton`.**
Adjacent-machine terms attract the wrong intent and dilute a listing whose whole strategy is being unmistakably about one machine.

**`fitness`, `training`, `gym` equivalents, `heart rate`, `intervals`, `routines`.**
Each of these is either too generic for a new app to rank on, already covered by a stronger token in the set, or a secondary feature Ascend would not win a search on.
`intervals` in particular loses to `hiit`, which is shorter and higher volume.

**Phrases with spaces.**
A space costs a byte and buys nothing, because Apple already forms phrases by combining single tokens across the name, subtitle, and keyword field.

### Dropped from the existing keyword set, and why

The live set is `workout,leaderboard,steps,cardio,gym,fitness,intervals,records,heart rate,training,routines`.
It was derived for a tracking product, and it reads like one: every term describes what the app stores rather than what the user does.

- `gym` moves into the subtitle, so it is free.
- `fitness` and `training` are generic category terms a launch app cannot rank on.
- `heart rate` spends 11 bytes including a space on a secondary feature.
- `intervals` and `routines` are replaced by the shorter, higher-volume `hiit`.

That frees the bytes for `climber`, `stepmill`, `climb`, `stairs`, `running`, `vertical`, and `compete`, which are the terms that describe racing a stair machine.

## Description

```text
Tower running is a real sport. Ascend puts it on the machine in front of you.

Athletes race the stairwells of the world's tallest buildings. Getting into one of those races takes a skyscraper, an event date, a travel budget, and a place in a limited field.

Ascend is that sport, on a stair stepper, on any day, from any gym.

Pick a tower. Race its real step count. Take your rank.

RACE REAL TOWERS

Choose a landmark and attack its actual step count: the Empire State Building, Taipei 101, the Eiffel Tower, Burj Khalifa, and more.
Motion sensors in compatible AirPods or Beats count your steps in real time.
Every climber who has raced that tower lines up beside you, each running their best attempt.
Watch your position move while you climb.

CLIMB THE LEADERBOARDS

Every tower keeps its own rankings.
Compare finish times, cadence, and steps against real climbers.
Reach the podium, then defend it.

CLAIM FIRST ASCENTS

Every new tower opens with one permanent prize: the First Ascent.
The first finisher claims it forever, even after someone posts a faster time.
Be ready when the next tower drops.

BREAK YOUR OWN RECORDS

Best Efforts turns the races you finish into a record book only you can break.
Most steps, longest climb, strongest pace, and more, each tied back to the session that set it.
See the work stack up instead of disappearing when the session ends.

TRAIN BETWEEN RACES

Guided routines build structured intervals and changing intensity into a stair session.
Pair a Bluetooth chest strap for live heart rate and effort zones.
Or start a Just Climb when you only want the work, with a step goal if you want one.
Every finished session lands in the same history as your races.

SHARE THE CLIMB

Build a share card from the tower you raced and the result you posted.

Ascend is built for people who take the stair stepper seriously.
It is not a generic activity tracker and it is not a social feed.
Every climb and every record in Ascend comes from a session you performed in Ascend. There is no manual entry and no importing from other apps.

An auto-renewing subscription is required after onboarding.
Available plans, billing terms, and any eligible trial are shown before purchase.
Subscriptions can be managed through your Apple Account, and eligible purchases can be restored in Ascend.

Every session in Ascend - a tower race, a Just Climb, or a guided routine - is counted by motion sensors in compatible AirPods or Beats, and needs a stair stepper to climb.
Apple Health is optional and is used only to attach heart rate and active-energy calories recorded while you were climbing in Ascend.
A Bluetooth heart-rate monitor is optional.
Ascend is not a medical device and does not provide medical advice.
```

2,738 characters of 4,000.

### What changed from the live description, and why

The live description opens with "Your stair-stepper work should count", which is a tracker's promise: it says the app will hold your effort for you.

This one opens by naming the sport.
Tower running exists, it is organised, and the only thing standing between a stepper user and it is a skyscraper they cannot get into.
That framing names the customer and answers "why does this not already exist" in the same breath, which "nobody does this" does not.

Three other changes carry the repositioning:

- The **KEEP YOUR HISTORY TOGETHER** section is gone. It promised logging and Apple Health import, both of which #437 removed. Its replacement is an explicit statement that everything in Ascend comes from a session performed in Ascend, which turns the removal into a credibility claim about the leaderboard rather than a missing feature.
- **Mt. Everest is gone** from the landmark examples, ahead of #440.
- The Apple Health footnote now says what Apple Health is actually for after #437: attaching heart rate and active-energy calories to a climb performed in Ascend, from an Apple Watch or any wearable that writes to Apple Health.

Three further corrections came out of verifying every sentence against build 2026081101 on 2026-08-11:

- **"Every attempt ever posted on that tower is the field you are racing" was not true.** The replay field carries one entry per climber, their best attempt on that context's own metric, because `reconcileUserBestEntries` in `functions/src/liveReplayLeaderboard.ts` is the authority for the `bestPerUser` flag the board renders. The line now says what the climber actually sees.
- **Just Climb was missing.** It is one of the three start actions on Home (`HomeStartAction`), it produces a real recorded session, and a description that never mentions it undersells the app rather than overselling it.
- **The hardware footnote named too few sessions.** Just Climb routes into `LiveClimbSessionView` like a tower race does, so it is gated by the same `HeadphoneMotionReadinessService` check. The footnote now covers all three session types and names the stair stepper, which the old wording left implicit.

### Traceability

Every claim in the description, and where the app makes it true. Checked against build `2026081101` on 2026-08-11.

| Claim | Evidence |
|---|---|
| Races real towers by their actual step count | `web/public/climbs/catalog-v1.json` - 59 `available` climbs. Empire State Building, Taipei 101, Eiffel Tower and Burj Khalifa are all `available` and all carry a `realStairCount` sourced in `docs/climb-real-stair-counts.md`. |
| Steps come from AirPods / Beats motion | `HeadphoneMotionReadinessService` gates every start on `CMHeadphoneMotionManager.isDeviceMotionAvailable`; the supported models are listed in `CompatibleHeadphonesHelpSheet`. |
| A field of other climbers, live | `LiveReplayLeaderboardPanel` renders the `everyone` field during the session; `functions/src/liveReplayLeaderboard.ts` derives it as each climber's best attempt. |
| Per-tower rankings on finish time, cadence, steps | `ClimbDetailView`'s All Times page; the global board's metrics are `LeaderboardMetric` - steps, workouts, duration, steps/min. |
| First Ascent is permanent | `ProfileAchievementLadder`, `TodayClimbStakeLine`, `Climb`. Locked copy lives in `ascend-brand-voice`. |
| Best Efforts record book | `BestEffortMetric` - most steps, longest climb, highest average SPM, most steps in a time window, fastest step target. |
| Guided routines with chest-strap heart rate | `AscendApp/Features/Routines/`; `HeartRateMonitorIntegrationCard` names the Bluetooth chest strap, and `LiveHeartRateSourceKind` ranks it above the watch. |
| Just Climb, open-ended with an optional goal | `HomeStartAction.justClimb` -> `LiveClimbSessionView(justClimbGoal:)`. |
| Share card from a race result | `AscendApp/Features/ShareComposer/`. |
| No manual entry, no import | `WorkoutSource.filterOptions == [.headphoneMotion]`, and `AscendAppTests/ManualLoggingAndImportRemovalEvidenceTests.swift` reads the removal back off rendered pixels. |
| Apple Health is heart rate and active energy only, over the session's own window | `HealthKitAuthorizationClient.readTypes`; `workoutType()` is never requested and no share types are requested. |

Two claims the description deliberately does **not** make, because the build does not support them:

- **No landmark count.** The catalogue moves with every climb drop, and #440 already took the hard-coded count out of the onboarding paywall for the same reason.
- **No Mapbox globe.** `ClimbMapboxPrototypeSurface` and `ClimbMapboxPrototypeRenderer` are both wrapped in `#if DEBUG`, and the production `MBXAccessToken` is empty. The browse globe a customer sees is `ClimbMapKitRenderer`, which is MapKit.

## App Review notes

Locale-independent; App Store Connect keeps one set for the version.
Apple's limit on this field is 4,000 bytes.
As written below it is **3,810 bytes**, so the bracketed fields have roughly 190 bytes to grow into - enough for real addresses, eight-digit backup codes, a video URL and a contact line, but not much more.
Count it again after filling them in; a long hosting URL is the one field that can blow the budget.

This text is truthful **only** once the bracketed fields are filled and the checklist below is verified against the production-signed build being submitted.
Every unbracketed sentence in it was checked against build `2026081101` on 2026-08-11.

```text
ASCEND - NOTES FOR APP REVIEW

Ascend is a stair stepper racing app. You pick a real tower, such as the Empire
State Building or Burj Khalifa, and race its real step count on a stair stepper
while motion sensors in your AirPods or Beats count your steps. Your time is
ranked on that tower's leaderboard.

1. SIGNING IN

Production offers Sign in with Apple and Sign in with Google only. Please use
Google, so you never have to sign out of your own Apple ID. Google challenges a
sign-in from a new device: choose "Try another way", then "Enter one of your
8-digit backup codes". Each code works once.

Full access, no purchase needed:
  Email: [REVIEW GOOGLE ADDRESS]
  Password: [PASSWORD]
  Backup codes: [CODE] [CODE] [CODE]
This account already holds the app_access entitlement and goes straight in.

Subscription flow, for reviewing the purchase:
  Email: [UNENTITLED GOOGLE ADDRESS]
  Password: [PASSWORD]
  Backup codes: [CODE] [CODE] [CODE]
No entitlement. After onboarding it reaches the subscription gate: an annual
plan with a seven-day free trial, or a monthly plan charged immediately.
Restore Purchases is on that gate and in Settings > Subscription.

2. THE HARDWARE, AND THE DEMO VIDEO

Demo video: [STABLE HTTPS URL, NO LOGIN]

Recording a session needs two things you will not have at a desk:

- AirPods or Beats that report headphone motion through Core Motion: AirPods 3
  and later, any AirPods Pro, AirPods Max, Beats Fit Pro, Beats Studio Pro,
  Beats Solo 4. Ascend counts steps from those sensors; an Apple Watch or the
  iPhone itself cannot supply them.
- A stair stepper, stair climber or StairMaster to physically climb.

Without both, the start control refuses with "Connect compatible headphones to
start this live climb" and no session begins. That is designed behaviour, not a
failure.

The video was recorded on the submitted build and shows the headphones, the
machine, a live tower race with splits and leaderboard movement, the finish,
and a guided routine start to finish. We will ship the hardware on request.

3. WHAT YOU CAN REVIEW WITHOUT THAT HARDWARE

On the full-access account, everything except starting a session:

- Home: today's tower, your weekly standing, recent records.
- Globe and catalogue: open any tower for its step count, floors, overview,
  history and per-tower leaderboard.
- Leaderboard: steps, workouts, duration and steps-per-minute, over weekly,
  monthly, yearly and all-time windows. Open another climber's profile.
- Training: browse routines, open a routine's overview, history and
  leaderboard, and create, edit or delete your own.
- Profile: lifetime stats, tower collection, achievements, Best Efforts,
  activity calendar, session history.
- Settings: profile, units, notifications, integrations, Manage Subscription,
  Restore Purchases, Terms, Privacy, Contact Us, sign out, Delete Account.

4. THINGS WE WANT TO STATE PLAINLY

- There is no manual entry and no import. Every session is recorded live by
  Ascend. Typed-in workouts and Apple Health workout import were both removed
  from the app, and earlier notes that mentioned them were wrong.
- Apple Health is optional and read-only. Ascend requests exactly two types,
  heart rate and active energy, and reads them only across the time window of a
  session Ascend itself recorded, to attach heart rate and calories to it.
  Ascend never requests workout data and never writes to Health.
- Bluetooth is used for one thing: an optional heart-rate chest strap.
- Delete Account sits at the bottom of Settings and is also reachable from the
  subscription gate, so an account that never subscribed can still delete
  itself. Deleting it does not cancel an App Store subscription, and the app
  says so and points to Apple's subscription settings.

Contact: [NAME] [PHONE] [EMAIL]
```

### Before these notes are pasted into App Store Connect

Each item is a sentence in the notes that this repository cannot prove on its own.

1. **Both accounts exist and are non-expiring, and both sets of Google backup codes are fresh.** Generating a new set invalidates the previous set, and the account must not be in Google's Advanced Protection Program, which disables backup codes entirely.
2. **The full-access account really opens the app.** Sign in on a device that has never held those credentials and confirm you land on Home rather than the gate. RevenueCat's dashboard reports a grant active whether or not Ascend's own product allowlist accepted it, so the dashboard is not the check - the app is. `app-setup-runbook.md` 4h has the failure mode.
3. **The unentitled account still sees both products** and can complete an Apple test purchase and a restore.
4. **The demo video is recorded on the submitted build**, is hosted at a stable HTTPS URL with no login, expiry or geographic restriction, and actually shows every artifact paragraph 2 claims it shows.
5. **Delete Account is reachable from the subscription gate.** As audited on 2026-08-11 it was not: the gate auto-presents the Superwall paywall, which has no close control, and hides the recovery actions behind it. That is a separate submission blocker. If it is not fixed in the submitted build, delete that clause from the notes - it is the one sentence here that a reviewer can disprove in ten seconds.
6. **The attached build is 2026081101, or the notes were re-checked against a newer one.** `docs/heart-rate-zones-plan.md` owns the decision to submit 1.0 without the watch app and ship it in 1.1.
7. **The plan wording matches the live products.** The notes describe the plan structure rather than quoting prices, so a price change cannot make them false, but confirm the trial and billing terms still read as written.

## Out of scope for this proposal

- **Screenshots.** Tracked separately in [#390](https://github.com/tpavay/AscendApp/issues/390).
- **In-app copy.** Tracked in #437.
- **The Superwall onboarding paywall** (`web/public/superwall/onboarding-paywall.html`). Resolved by #440: it no longer hard-codes a landmark count, and derives it from the published catalogue instead. `docs/launch-readiness-audit.md` (Promise vs. reality, item 8) owns how that resolution works.
