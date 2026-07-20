# Feature Contract: Capture chest-strap heart rate during routine sessions

- Issue: #241
- Base branch: `develop`
- Change type: fix
- Owner: orchestrator

## User outcome

A climber wearing a connected chest strap during a routine gets the same live sampling behavior as Live Climb and Just Climb, and the saved routine workout includes average heart rate, maximum heart rate, and the sampled series.

## Non-goals

- Do not add Apple Watch live heart-rate support.
- Do not change the Heart Rate Monitor integration copy.
- Do not migrate, backfill, or deploy data.
- Do not refactor unrelated workout capture or persistence behavior.

## Acceptance criteria

- [x] AC-1: A routine session with fresh chest-strap readings saves average heart rate, maximum heart rate, and the complete sampled series on its workout.
- [x] AC-2: A routine session without fresh chest-strap readings saves successfully with no heart-rate summary or series.
- [x] AC-3: Live Climb, Just Climb, and routine sessions use one shared sampling and summary pipeline.
- [x] AC-4: The shared live-source selection gives a chest strap higher priority than an Apple Watch source.
- [x] AC-5: Existing routine completion, motion tracking, workout mutation, and Apple Health enrichment behavior remains unchanged.

## State matrix

| State | Expected behavior | Verification |
|---|---|---|
| Happy path | Fresh strap readings are sampled and saved with their derived average and maximum. | Routine save integration test and shared recorder unit tests. |
| Loading | A remembered strap reconnect attempt starts without delaying the routine countdown or recording. | Shared recorder preparation test and code review. |
| Empty | No connected or fresh source produces an empty summary, and the routine workout saves nil heart-rate fields. | No-strap routine save integration test. |
| Error/offline | Bluetooth absence or stale measurements does not block local workout save. | Empty-source recorder test and no-strap routine save integration test. |

## Test mapping

| Acceptance criterion | Automated test or evidence | Why it proves the behavior |
|---|---|---|
| AC-1 | Producing-strap routine save integration test | Exercises the routine workout construction and persistence path with deterministic sampled readings. |
| AC-2 | No-strap routine save integration test | Exercises the same save path with an empty source and verifies clean nil fields. |
| AC-3 | Shared recorder consumer test plus source diff review | Verifies equivalent sampling output and confirms all three session modes depend on the same recorder type. |
| AC-4 | Chest-strap priority unit test | Supplies simultaneous strap and Watch readings and asserts the strap reading wins. |
| AC-5 | Existing routine and iOS test suites | Detects regressions in existing session and workout behavior. |

## UX evidence

Not applicable: this changes captured workout data without changing layout, copy, navigation, or interaction design.

## Risk and rollout

No migration or deployment is required because workouts already support optional heart-rate summaries and series.
Backward compatibility is preserved because workouts without samples continue to store nil heart-rate fields.
No analytics contract changes are required.
The existing privacy declaration already covers heart-rate data collected by the app, and this fix routes another promised workout type through the existing capture path.
No feature flag or special deployment order is required.
Rollback consists of reverting the shared recorder integration.

## Human gates

- None.
