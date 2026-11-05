# Apple Health import

Stair stepper workouts a watch or another app saved to Apple Health become Ascend climbs.
This shipped in 1.3.0 as piece two of three.
Apple Health workout import was removed on 2026-08-08 (#437) under the racing-not-tracker positioning, and returned because headphones die or break, the app can glitch mid-climb, and many climbers have no compatible headphones.
Live headphone climbs stay the main way to climb.

## What counts

Only `HKWorkoutActivityType.stairClimbing` and `.stairs` workouts are read.
Only workouts that start on or after the climber's join date (Firebase Auth `creationDate`) are ever filed.
A workout shorter than a second or longer than a day is not a climb and is never filed.
Everything else in Health is somebody else's data and is never read.

## The ledger

`HealthWorkoutRecord` (schema V7, `AscendSchemaV7`, lightweight) holds one row per HealthKit workout UUID for the life of the account.
It carries the numbers Health reported at discovery so the Imports list renders with no HealthKit read.
Those numbers stop updating once the row is imported, so an imported row and the Home strip read steps and time from the climb and fall back to the record only where the climb is gone.
`Workout.healthKitUUID` carries the same UUID on the climb, and it travels through the cloud backup, so a restored climb still stops its own workout importing again.

| State | Meaning |
|---|---|
| `not_imported` | Waiting in Imports, or for auto-import to take it. |
| `imported` | Became a climb. `importedWorkoutID` names it. |
| `skipped` | Swiped away, or its climb was removed. Never imports again, in either mode. |
| `overlaps_live_climb` | An Ascend live climb already covers the window by a minute or more. |

`overlaps_live_climb` is the named hook for the overlap merge (HANDOFF 5.2).
Nothing resolves those rows yet.
The live climb stays the only climb, and the merge will let the Health workout add heart rate and calories and offer the extra minutes.
A workout whose window a headphone session covers before that session has saved its climb - still recording, or waiting to be recovered (`ActiveHeadphoneWorkoutDraft`, `startedAt` to `lastCheckpointAt`) - stays `not_imported` and is not imported, so the import after the session saves files it as `overlaps_live_climb`.

The ledger is local only.
A skipped workout is not cloud-synced, so on a new device a workout the climber once skipped can reappear as waiting.
That is accepted: the climb is the climber's data and the ledger is bookkeeping.

## Settings and keys

`AppleHealthImportSettings` keeps three values in UserDefaults, keyed by uid so a different climber on the same device starts clean: auto-import (default on), when Imports was last opened, and the HealthKit query anchor.
Account deletion empties the whole defaults domain.
The ledger rows are user records, so `AccountDataOwnershipService` blocks an account switch over them the way it does over climbs.

## A pass

`AppleHealthImportService.syncNow()` is the only pass.
It reads from the persisted anchor with `HKAnchoredObjectQueryDescriptor`, files what is new, saves the ledger, and only then stores the new anchor.
With auto-import on it then imports everything waiting.
A pass that created no climb skips the derived refresh: the refresh rebuilds the Best Effort cache from every climb and forces a rank read, and a pass runs on a screen's `.task`.
Passes are coalesced: a caller that arrives during a pass asks it to go round once more.
It runs on authenticated bootstrap, on every foreground, on Home entry, when Imports opens, and when the observer fires.

Nothing a blocked pass leaves behind is lost.
The pass refuses before any Health call when Health is unavailable, the climber has not connected, nobody is signed in, the local store's remembered owner (`AccountSessionStore.localDataOwnerUserId`, recorded once the account-ownership gate allows a climber) is someone else, deletion is draining, the build is locked out, or `apple_health_import_enabled` is off.
The anchor does not advance while it is blocked, so the first pass afterwards reads everything that arrived in between.

The first pass after connecting has no anchor, so what it finds is history.
In auto mode it imports history silently: no notification and no Home strip.
A pass with no anchor also waits until the authenticated bootstrap, past the account-ownership gate, has restored this climber's climbs from the cloud in this session and said so (`confirmCloudClimbsRestored`, cleared on sign-out), because the climb a workout became on an old phone is the only thing that stops it importing a second time on a new one; the bootstrap that finishes the restore runs the pass again.
A pass with an anchor does not wait, so a background wake still imports what is new.

At import time the workout is read again by UUID, because a watch can write its statistics after the workout.
A workout Health no longer has keeps the numbers it was found with.

## Importing

An imported climb is `WorkoutSource.appleHealth`, which `ClimbOrigin` reads as `healthImport`.
Steps are the exact number on the workout's own statistics, never a tilde and never a second query over a time window.
Average and maximum heart rate and active energy come from the same statistics.
A workout with no step count imports with zero steps, which `Workout.isMissingSteps` reads as absent.
Steps that fail the unsaveable test in `AppleHealthImportPolicy.importableSteps` (300 steps a minute, or more than 120,000) are dropped to missing: a typed save is refused there, an import cannot be, and a climb the cloud would refuse on every sync is worse than one asking for its number.

Imported climbs go through `ClimbPacePolicy` exactly like a typed climb.
Up to 200 steps a minute ranks, 200 to 300 is saved and kept off leaderboards and the Best Efforts that feed them, and the server re-derives eligibility from `source`, `steps` and `durationSeconds` and never reads the device's verdict.
Editing steps or time re-runs the check, and nothing else does.
There is no report button, no review queue, and no hold on a top placing.

Stair stepper imports usually carry no steps, and a climb without them is unfinished, so unknown never reads as zero:

- The Profile Activity row, the Imports row and the Home strip say `Add steps` where the number would be.
  On the Imports row it is a button into the existing steps entry, and a workout still waiting is imported first.
- Climb detail shows a dash with the `Add steps` action, its menu leads with Add steps instead of Share until the steps are in, and copied workout text drops the Steps line.
- The Home week line names only the climbs when the week's step total is zero because of such climbs.
- `Workout.canHoldRecords` is false, so the climb holds no Best Effort, no ranked or record badge such as 3rd longest, and no published profile record until it has steps.
- `PersonalizedClimbPaceService.allTimeAverageSPM` and the Profile fallback average leave its minutes out of the division.
  The weekly Avg SPM chart and the `averagePace` share sticker still count them.

Importing never opens a sheet or a dialog.
Removing an imported climb from its summary, the climbs list, or the quick edit marks the workout skipped for good.
A workout deleted in Apple Health keeps its climb.

## Auto-import and choosing

Auto-import is on by default.
Onboarding connects Health with it on and shows no choice.
A climber connecting later sees Import automatically (preselected) or Let me choose, and the choice is the one setting Imports and, later, Settings show.
Turning auto-import on imports what is already waiting, silently.

With auto-import off, new workouts land in Not imported and nothing is sent.
The red badge on the + button and the Climb sheet's Health button counts waiting workouts that started in the last seven days and that Ascend found after Imports was last opened, and opening Imports clears it.
The last-viewed cut is on when Ascend found the workout, not when it started, because a watch can hand a workout to the phone long after it ended: one that started before the last visit but arrived after it still raises the badge.
With auto-import on the badge is always zero.

## Announcing an automatic import

For each workout a non-history pass imports automatically:

- A local notification titled Climb imported, body `Your {steps}-step stair stepper workout from Apple Health is in. Tap to add a note or photo.`
  A workout with no steps reads `Your stair stepper workout from Apple Health is in. Tap to add your steps.`
  It is sent only if iOS notification authorization allows.
  It rides on the authorization the climb-drop opt-in already obtained and never asks for its own, and it does not read the climb-drop preference.
- A green strip on Home the next time Home appears, with Edit, retired when used or after a day.
- Tapping the notification or Edit opens the quick edit sheet: time, editable steps, average heart rate, note, photo, effort, Done, and Remove this climb.
  That sheet is reached from those two doors only.
  Everywhere else an imported climb opens the full climb summary.

## The observer

`HealthKitWorkoutReader` registers an `HKObserverQuery` on the workout type and calls `enableBackgroundDelivery(for:frequency: .immediate)`.
`AppleHealthImportService.resume` is called from `AscendApp.init`, because HealthKit relaunches the app in the background with no scene and delivers only to an observer registered by then.
The completion handler is called on every path, after the pass or after 25 seconds, whichever is first, and the reader ignores a second call.
Sign-out and account deletion stop the observer through `AutonomousSessionWorkers`.
The `com.apple.developer.healthkit.background-delivery` entitlement is in `AscendApp/AscendApp.entitlements`.

## Permissions and disclosure

The read set is exactly four types, read only, with `toShare: []`: `workoutType()`, `stepCount`, `heartRate` and `activeEnergyBurned` (`HealthKitAuthorizationClient.readTypes`).
Ascend never writes to Health.
`enrichmentReadTypes` is the heart rate and active energy pair alone, so enrichment's connection state is unaffected by the wider ask; `importConnectionState` is the wider check, and a climber connected before import returned answers not connected there until shown the sheet for the workout types.
The `NSHealthShareUsageDescription` sentence, `PrivacyInfo.xcprivacy`, the privacy policy on the website and the App Privacy answers all name this set, and `AppleHealthSurfacesEvidenceTests` and `scripts/test/outward-positioning-copy.test.mjs` hold them to it.

## Kill switch

`apple_health_import_enabled` (`RemoteFeatureFlag.appleHealthImport`).
Off, the entry points disappear, no pass runs, nothing is imported or announced, and the anchor is not advanced.
See `docs/remote-config-kill-switches.md`.

## Leaderboard rows

The server still stores two counts beside a leaderboard row's totals, `typedWorkouts` and `importedWorkouts`, and the client still parses them as `FirestoreLeaderboardStats.origin`, but nothing draws them: the captain ruled on 2026-11-02 that how a climb was recorded shows only on the Imports list and as the footnote on the climb's own detail.
`aggregateForPeriod` counts both from the same workouts as the totals, `FirestoreLeaderboardStats.origin` reads them, and one typed climb makes the row typed before one imported climb makes it a Health row.
A row written before the server counted imports reads as live until the next derivation rewrites it.

## The Climb sheet

The sheet follows the handoff's screens 03 to 05.
Just Climb is the hero row, ringed in the accent, because a live climb stays the main way to climb.
The Landmark row names today's climb (`DailyClimbRecommendationPolicy`, the Home daily row's pick) and the Routine row names today's featured built-in routine (`DailyRoutineRecommendationPolicy`, same 4 a.m. rollover).
Tapping either row opens that pick; `See all ›` opens the full list, the expanded Home sheet for landmarks and Training for routines.
With no pick in hand a row falls back to what it is for.
SwiftUI keeps a single orphaned word off the last line, so the Just Climb subtitle wraps one word earlier than the mock's browser render.

## Not built yet

These belong to the third piece:

- The overlap merge with a live climb and the Apple Health added-minutes prompt (HANDOFF 5.2).
- The Settings screens: How you track, Apple Health connected or off, Import older workouts.
- Importing workouts older than the join date.
- Onboarding wording and a Health step in onboarding itself.

## Testing without a device

`AscendAppTests/AppleHealthImportTestDoubles.swift` holds `FakeHealthWorkoutReader` (a Health database whose anchor is a count of what it has handed out), a recording notifier, an in-process climb remover, a fake authorization controller, and `AppleHealthImportHarness`, which wires a service to an in-memory store and a signed-in climber who joined 30 days before a fixed `now`.
`AppleHealthImportServiceTests` covers mapping, dedupe, skip and remove, the badge rules, both modes, the kill switch and the observer completion handler.
`HealthWorkoutRecordSchemaMigrationTests` proves the V6 to V7 stage against a real on-disk store.
Hosted Home tests pass a service built on `FakeHealthWorkoutReader` with Health unavailable, so no test points the process-wide service at a throwaway store.

## The connect flow

Connecting is the Connect button, the iOS sheet's Turn On All and its Allow, then Continue on the import choice.
The in-app permission guide the handoff drew as screen 10 was dropped on 2026-11-02: it cost a tap and its copy told climbers to tap Allow in the top right, where iOS puts it at the bottom.
The connect screen carries one line instead: "Next, iOS asks for access. Tap Turn On All, then Allow."
The flow has two Ascend screens, Connect and the import choice.
Both end in `HealthFlowChrome`'s bottom bar, which always reserves the secondary slot under the primary button, so the primary button sits in the same place on both.
Only the Connect screen draws the close X, 6 points under the safe area's top and 16 from the leading edge.
The import choice draws no control at the top and starts its content 40 points lower than Connect's.
The Ascend tile on the connect screen is the real `AppIconInternalAccent` mark, and the dotted line between the tiles is one static dashed stroke with nothing animating.
