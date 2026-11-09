# Apple Health import

Stair stepper workouts a watch or another app saved to Apple Health become Ascend climbs.
This shipped in 1.3.0 as piece two of three.
Apple Health workout import was removed on 2026-08-08 (#437) under the racing-not-tracker positioning, and returned because headphones die or break, the app can glitch mid-climb, and many climbers have no compatible headphones.
Live headphone climbs stay the main way to climb.

## What counts

Only `HKWorkoutActivityType.stairClimbing`, `.stairs` and `.stepTraining` workouts are read (`HealthKitWorkoutReader.stairActivityTypes`).
A watch or an app decides which Apple activity type its stair stepper session is saved under, so the read covers the stair types and not one of them.
Only workouts that start on or after the climber's join date (Firebase Auth `creationDate`) are filed by the pass.
Older ones arrive only through the history backfill below, and only when the climber asked for it.
A workout shorter than a second or longer than a day is not a climb and is never filed.
Everything else in Health is somebody else's data and is never read.

## The step rule

One rule, the same for one workout or three hundred (`HealthWorkoutStepRule`):

1. The workout carries steps of its own (its `stepCount` statistic): those are the climb's steps.
2. It carries none, or zero: one `HKStatisticsQuery` with `.cumulativeSum` over `stepCount`, from the workout's start to its end.
   A sum above zero is the climb's steps.
   `cumulativeSum` merges the sources that counted the same steps (a watch, the phone, a Garmin), so nothing is added twice.
3. The window sums to zero too: the climb arrives without steps and the Add steps handling below applies.

Either number is the climb's number.
No tilde, no "check this" marker, no extra state, and no field anywhere that says which of the two it was.
A climber who thinks the steps are off opens the climb and edits it, the same as a typed climb.

The rule runs on every read before the workout is filed, summarised or imported: the pass, the history backfill, the fresh read at import time, and the totals the history screens show.
So the number a screen promises is the number that lands.
Window reads run at most twelve at a time (`concurrentWindowReads`), so a history of a few hundred workouts resolves in a few rounds and the screen's total is exact, never an estimate.
A window read that fails leaves the steps unknown, and the read at import time looks again.
Steps a later read does not hold never erase steps an earlier read found (`HealthWorkoutRecord.updateMeasurements`).

This is what the app did before import was removed, and the 1.3.0 rebuild had dropped it, which is why nearly every import arrived with no steps.

## What gets passed over

A stair workout a read sees and does not count is reported once as `apple_health_workout_skipped` (`AppleHealthImportAnalyticsEvent`), so the way other watches and apps label the machine shows up in real numbers.
The event carries `reason` (`duration`, `overlaps_live_climb`), `activity_type` (the `HKWorkoutActivityType` raw value), `source_bundle_id` and `duration_bucket`, and nothing else: no date, no steps, no heart rate, no identifier.
An Apple Watch writes under `com.apple.health.<a UUID of that watch>`, which is reported as `com.apple.health`.
`HealthWorkoutSkipReporter` sends one event per workout however many reads see it in a session.
The privacy policy's Apple HealthKit section says what the event records in plain words, and `PrivacyInfo.xcprivacy` declares it under Health with the Analytics purpose; the App Store privacy answers are applied by hand.
A workout of an activity type outside the three is never read, so it is never reported: the privacy policy says Ascend does not read any workout that is not a stair stepper workout, and widening the read to learn other mappings is a disclosure change first.

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

`overlaps_live_climb` is terminal.
If a Health workout covers a climb Ascend already recorded with headphones, the live climb is the climb: the workout is never imported, nothing of it is merged into the live climb, and the climber is never asked about it.
The Imports list does not show those rows, and no count includes them.
A workout whose window a headphone session covers before that session has saved its climb - still recording, or waiting to be recovered (`ActiveHeadphoneWorkoutDraft`, `startedAt` to `lastCheckpointAt`) - stays `not_imported` and is not imported, so the import after the session saves files it as `overlaps_live_climb`.

The ledger is local only.
A skipped workout is not cloud-synced, so on a new device a workout the climber once skipped can reappear as waiting.
That is accepted: the climb is the climber's data and the ledger is bookkeeping.

## Settings and keys

`AppleHealthImportSettings` keeps three values in UserDefaults, keyed by uid so a different climber on the same device starts clean: auto-import (default on), when Imports was last opened, and the HealthKit query anchor.
The anchor is stored under the scope of the read that produced it (`anchorScope`), because an anchor says "nothing new before here" only about the activity types that read asked for.
An anchor from the two-type read is not this read's anchor, so the first pass after the update starts from the join date like a first pass, silently, and the ledger stops anything it already knows from importing twice.
Growing `stairActivityTypes` again means changing `anchorScope` with it.
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
The pass refuses before any Health call when Health is unavailable, the climber has not connected, nobody is signed in, the local store's remembered owner (`AccountSessionStore.localDataOwnerUserId`, recorded once the account-ownership gate allows a climber) is not this climber, deletion is draining, the build is locked out, or `apple_health_import_enabled` is off.
The anchor does not advance while it is blocked, so the first pass afterwards reads everything that arrived in between.

The first pass after connecting has no anchor, so what it finds is history.
In auto mode it imports history silently: no notification and no Home strip.
A pass with no anchor also waits until the authenticated bootstrap, past the account-ownership gate, has restored this climber's climbs from the cloud in this session and said so (`confirmCloudClimbsRestored`, cleared on sign-out), because the climb a workout became on an old phone is the only thing that stops it importing a second time on a new one; the bootstrap that finishes the restore runs the pass again.
A pass with an anchor does not wait, so a background wake still imports what is new.

At import time the workout is read again by UUID and the step rule runs again, because a watch can write its statistics, and hand its steps to Health, after the workout.
A workout Health no longer has keeps the numbers it was found with.

## Importing

An imported climb is `WorkoutSource.appleHealth`, which `ClimbOrigin` reads as `healthImport`.
Steps are what the step rule settled: the workout's own, else the window's, and never a tilde.
Average and maximum heart rate and active energy come from the workout's own statistics.
A workout Health holds no steps for at all imports with zero steps, which `Workout.isMissingSteps` reads as absent.
Steps that fail the unsaveable test in `AppleHealthImportPolicy.importableSteps` (300 steps a minute, or more than 120,000) are dropped to missing: a typed save is refused there, an import cannot be, and a climb the cloud would refuse on every sync is worse than one asking for its number.

Imported climbs go through `ClimbPacePolicy` and the join-date rule exactly like a typed climb.
Up to 220 steps a minute ranks, 220 to 300 is saved and kept off leaderboards and the Best Efforts that feed them, and the server re-derives eligibility from `source`, `steps` and `durationSeconds` and never reads the device's verdict.
A change to steps, time or date, edited here or restored from the cloud, re-runs the check, and nothing else does.
There is no report button, no review queue, and no hold on a top placing.

A climb whose workout and window both hold no steps is unfinished, so unknown never reads as zero:

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
A climber connecting later sees Import automatically (preselected) or Let me choose, and the choice is the one setting Imports and Settings show.
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

## The history backfill

Connecting finds the stair workouts Health already holds, and one screen asks the one question about them.
Onboarding's "We found your climbs" (07a) and Settings' Import older workouts are that screen in two frames, drawing the same body (`HealthHistoryContent`) from the same state (`HealthHistoryChoice`).

- The primary button is `ADD <N> TO MY HISTORY`.
  N is the number of workouts inside the range, and those are the identifiers the import is handed.
- One row under the number changes the range.
  It reads `Everything since <month year of the oldest workout>` by default and opens a picker with Everything, Last year, Last 90 days, and Since a date (`HealthHistoryRange`).
  The count, the hours, the step total, the comparison and the button all follow the range.
  A preset that holds no workouts cannot be picked and the date row only offers days between the first workout and the last, so the screen never has nothing to add.
- In onboarding a quiet link under the button says `Skip history, just import new workouts`.
  It clears the found identifiers exactly as declining Health does and moves on.
  Either choice leaves Health connected with auto-import on, so the next stair stepper workout still arrives.
  A climber who holds the rails, whose watch counts badly, connects and imports nothing; a climber whose watch is right takes all of it.
- Both answers report once as `onboarding_question_answered` with `question_id=health_history`: `answer_id` is the range (`everything`, `last_year`, `last_90_days`, `since_date`) or `skip_history`, with `workouts_added` and `workouts_found`.
  A picked day reports that one was picked, never which.

The pass never reaches workouts from before the climber joined, so `AppleHealthImportService.importHistory(matching:)` does, after sign-in.

- Before sign-in nothing is filed.
  07a only reads: `HealthHistory.load(using:)` is one `changes(since: nil, startingOnOrAfter: .distantPast)` over the stair workouts plus the step rule's window reads, and the anchor it returns is dropped.
  The only things left behind are `PreAuthOnboardingAnswers.foundHealthWorkoutIDs` on the device, which the button sets to the workouts inside the range and the sign-in hand-off (`OnboardingV3SignInHandOff.importHealthHistory`) reads, and `foundHealthKnownSteps`, the total the sign-in screen's list says back beside their count.
  Declining Health, finding no workouts, or skipping history clears both.
- `importHistory` files the workouts whose start is before the join date and whose identifier is in that list, through the same ledger (`file(_:ledger:)`, shared with the pass) and the same `importRecords` choke point, so a workout is recognised the same way whichever meets it first, `apple_health_import_enabled` still gates every climb it creates, and a workout already imported or skipped is left alone.
  It never touches the pass's anchor, announces nothing, and opens nothing.
- It waits for what the first pass waits for: Health connected, the ownership gate, and the cloud restore (`confirmCloudClimbsRestored`), because a climb the account already holds is the only thing that stops its own workout importing twice.
  It returns false when anything defers it and the sign-in hand-off keeps the identifiers.
  The sign-in's first attempt usually arrives before the restore does, so the authenticated bootstrap runs the hand-off again right after it confirms the restore and resumes import, which lands the history in the session that asked for it; a launch or foreground runs it again after any other deferral.
- The climbs land in the first session, and that session is usually before the paywall, when `firestore.rules` would refuse their upload.
  `WorkoutSyncCoordinator` holds workout uploads back until the climber is known to hold app access, so no refusal is recorded and the climbs stay pending.
  The `hasAppAccess` change in `RootView` runs a pass once the backend has heard about the purchase, and when RevenueCat had answered no, that pass re-opens anything a refusal slowed or stopped, so every climb goes up without a retry.
  An entitlement still unknown holds uploads and re-opens nothing, so an ordinary launch of a paying climber cannot launder a refusal into another attempt.
  `workout_sync_app_access_hold_enabled` turns the hold off.
- `apple_health_history_import_enabled` is its own kill switch (`docs/remote-config-kill-switches.md`).
- The climbs arrive `.excluded`.
  History fills the climber's own history, personal bests and streak (`Workout.canHoldRecords` is false only for an over-pace climb or one with no steps), and never a leaderboard: only climbs after a climber signed up count on leaderboards, so it is fair for everyone.
  The server agrees from Auth's creation time (`startedBeforeAccount` in `functions/src/leaderboardStats.ts`), the device agrees through `ClimbPacePolicy.startedBeforeAccount`, so editing the steps of a history climb never puts it on a board, and `SharedTestVectors/pre-join-unmeasured-climb-vector.json` holds the two to the same answers.
  The rule covers every unmeasured climb (`manual`, `apple_health` and the legacy `hevy`), typed or imported, and an account Auth cannot date ranks none of them.
  It compares the exact moment the account was created, so a workout from the morning of the day a climber signs up is history too, which is why 07a says "Every climb after you sign up counts on the leaderboards" and not "from today".
- Production holds no such workout today: measured on 2026-11-06, `ascend-prod-9c8f2` had 117 cloud-backed workouts from 11 climbers, all `headphone_motion`, none `manual`, `apple_health` or `hevy`, so the rule cannot take a standing from an existing climber.
  Count them again on `ascend-prod-9c8f2` right before the production functions deploy, because a stale measurement licenses a change that damages real customers' data.
- A history workout goes through the step rule like any other, and one with no steps anywhere follows the Add steps handling above unchanged.
- Settings' Import older workouts lists what the backfill can still bring in (`olderWorkouts()`): stair workouts from before the join date that are not climbs yet and were never turned away.
  It files through the same `importHistory(matching:)`, so a second visit offers only what the first left out.
  Workouts since joining are the pass's and arrive through Imports.

## Settings

Settings carries an Apple Health section between Preferences and Purchases with one plain row, Workout import, to the Apple Health screen (`AppleHealthSettingsView`, `apple_health_settings`).
The row carries a chevron and no state, like every other Settings row (`SettingsReorganizationEvidenceTests` holds Settings to that), and it is absent when import is not on offer at all: a device with no Health, or `apple_health_import_enabled` off.
The screen has three rows:

- **Apple Health.**
  Off, the row says so and opens the Connect flow (`AppleHealthConnectFlowView`, `health_connect_later`).
  Connected, it says Health access is managed in the Health app and opens it, because iOS gives an app no way to disconnect.
- **Import automatically.**
  A switch on `AppleHealthImportSettings`' auto-import value through `setAutoImportEnabled`, so turning it on imports what already waits, silently.
- **Import older workouts.**
  Opens the history screen in the Connect flow's chrome (`AppleHealthOlderWorkoutsView`, `apple_health_older_workouts`): the close X, the range row, `ADD <N> TO MY HISTORY`, and Not now in the reserved slot.
  Hidden when `apple_health_history_import_enabled` is off.

The last two rows show only while Health is connected.

## Not built

- Merging a Health workout into a live climb it overlaps.
  This was HANDOFF 5.2 and is dropped, not deferred: the live climb is the climb (see `overlaps_live_climb` above).
- A How you track screen in Settings.

## Testing without a device

`AscendAppTests/AppleHealthImportTestDoubles.swift` holds `FakeHealthWorkoutReader` (a Health database whose anchor is a count of what it has handed out), a recording notifier, an in-process climb remover, a fake authorization controller, and `AppleHealthImportHarness`, which wires a service to an in-memory store and a signed-in climber who joined 30 days before a fixed `now`.
`AppleHealthImportServiceTests` covers mapping, dedupe, skip and remove, the badge rules, both modes, the kill switch and the observer completion handler.
`HealthWorkoutStepRuleTests` covers the step rule on its own and through the pass, the import-time read and the backfill; `AppleHealthWorkoutSkipTests` the three activity types, the anchor scope, the terminal overlap and the skip event; `HealthHistoryRangeTests` the range arithmetic; and `AppleHealthSettingsTests` the Settings rows and Import older workouts.
`FakeHealthWorkoutReader.windowSteps` is what Health's step count holds for a window, keyed by the window's start.
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
The Ascend tile on the connect screen is the real `AppIconInternalAccent` mark.
The tiles pop in and the dotted line between them flows from Health toward Ascend, one 12 point step every 0.4 seconds (the design's 24 points in 0.8), which Reduce Motion holds still.

## In onboarding

`AppleHealthConnectView` is also onboarding's screen 06, in `Chrome.onboarding`: the progress header replaces the X, the quiet link says "Skip" with "You can always connect this in Settings." under it, the art is centred in the room above the words, and the one-line hint is left out because the next screen shows the sheet.
The two chromes track `.onboardingHealthConnect` and `.healthConnectLater`.
06b ("Two taps and you're set") shows a drawn picture of Apple's sheet with the four types of `readTypes` and "access", never "update"; its "GOT IT" is the request, through `AppleHealthConnectViewModel.requestAccessOnly()`, the same `HealthKitAuthorizationClient` request without the discovery and the import choice, because there is no account to file in yet and onboarding connects with auto-import on.
The picture follows iOS 26's own sheet, captured from the simulator: Allow is at the bottom, under Turn On All and the four switches, so the step reads "Tap Allow at the bottom" (the handoff's "in the top right" was the older sheet, and is the wording the connect flow already dropped on 2026-11-02).
The system's sentence above the switches still reads "access and update your Health data" on the real sheet because the Info.plist declares `NSHealthUpdateUsageDescription` beside the share string; the drawn picture says "access", which is what Ascend does.
After the sheet it reads the history and routes: workouts found go to 07a, none (or a failed read) go to 07b.
`HealthPermissionSheetMock.categories` has to change with `readTypes`.
