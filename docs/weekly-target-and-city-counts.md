# Weekly target and city counts

Two small pieces of the 1.3.0 onboarding that outlive it.

## Weekly target

A climber can choose a target of one to seven climbing days a week, on onboarding screen 10 or in Settings -> Weekly target.
It is optional: skipping leaves it unset, and a climber with no target gets no weekly ring on Home.
No weekly-target reminder is built yet, for any climber.
Everyone has the week streak (`WeeklyStreak`, a week with any climb) whether or not they set a target, and the streak is never computed from it.

- `WeeklyTarget` and `WeeklyTargetProgress` (`Shared/Models/WeeklyTarget.swift`) are the value and the count of distinct climbed days in the Monday week.
- The device keeps the target per account (`WeeklyTargetStore`), and Home reads that copy.
- The account keeps it as `users/{uid}.weekly_target_days`, an integer from 1 to 7 and private to its owner.
  Rules came first; it is never mirrored to the public profile and feeds no leaderboard.
- The write sits behind `weekly_target_writes_enabled`.
  Off, a change stays on the device marked unsynced, and goes up when the switch returns (`WeeklyTargetService.reconcile`).
- A new phone adopts the account's target once a launch, unless the device holds a change the account has not seen.
- One account's reads and writes run one at a time (`WeeklyTargetSyncQueue`), so an older write can never land after a newer one.
- Onboarding keeps the answer on the device in `PreAuthOnboardingAnswers.weeklyTargetDays`.
  No hand-off after sign-in is built yet, so nothing carries that answer to the account or to Home's ring; the hand-off has to write through `WeeklyTargetService.save`.

## City climber counts

Onboarding's "Claim your city" screen runs before sign-in, so it cannot read the leaderboard.
`publishCityClimberCounts` (hourly, `functions/src/publicCityClimberCounts.ts`) derives one document per city, `public_city_climber_counts/{key}`, from the server-owned all-time `leaderboard_stats` rows of real climbers who have a city.
The key is `COUNTRY__region__city`, normalized, and `SharedTestVectors/city-count-key-vector.json` holds the server and `CityClimberCountKey.swift` to it.

- Rules let anyone `get` one document and nobody `list` or write.
- A city with no climber has no document, so "no document" alone cannot tell "nobody here" from "never ran".
  The run writes `_summary` last, and the app treats a missing summary as an answer it does not have: the screen then says nothing about the city's climbers instead of a guessed zero.
- `_summary` carries only `schemaVersion` and `updatedAt`, because it is readable by anyone and no screen needs totals.
- Deploy the function and let it run once before the build that reads it ships.
- A zero count says nothing about who has climbed there ("Be among the first climbers in Chicago..."), because a city's key follows the spelling its climbers' phones stored, which varies with the phone's language.
  Follow-up: canonicalize the stored city before keying, so one city has one key whatever language the phone speaks.
