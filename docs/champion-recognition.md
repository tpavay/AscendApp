# Champion recognition and period recaps

The captain settled this design on 2026-09-27.
This document owns the data contract and the product rules the app and the backend both build against.
The rank model itself - what a rank counts and how ties resolve - stays owned by `ascend-leaderboards`.

## What the climber sees

- **The reign.** The #1 of a closed weekly, monthly or yearly Steps board wears that board's crown on their picture for the whole of the next period, on every surface, and loses it when the next champion is crowned.
  Every #1 is crowned however many climbed, and an exact tie crowns every tied climber (co-champions).
- **Three crowns.** Weekly is gold (`LeaderboardCrown`), monthly is diamond (`LeaderboardCrownDiamond`), yearly is mythic (`LeaderboardCrownMythic`).
  All-time has no crown yet.
- **Steps only.** Only the unfiltered Steps board crowns, because it is the only board the finalizer awards.
  The climber with the most climbs is named on past boards and in the recap, and never crowned.
- **The mark.** A crown perched on the picture, tilted, at the top right.
  Pictures 56pt and larger wear the full perch; smaller pictures wear the compact perch at half the picture's width.
  It is hidden on a picture that already wears a gold, silver or bronze ring (the global podium, and the top three rows of ALL TIMES and routine boards), and there is never a crown beside a name in a list row.
- **Several titles.** The rarest title leads (yearly, then monthly, then weekly); large pictures carry a small dot per other title; holding all three is "Undisputed".
- **Blocked climbers** keep their crown on the placeholder picture: a title is a standing, not identity.
- **The board.** A slim champion strip leads the weekly, monthly and yearly Steps boards, with a chevron to past champions.
  First place on the podium takes the board's colour - crown, ring and number - gold weekly, diamond monthly, mythic yearly; #2 and #3 keep silver and bronze.
- **Past champions are past boards.** The board frozen at each final result, stepped back one period at a time, with the climber count and most climbs underneath.
- **Profiles.** The crown sits on the picture; there is no title bar.
  The comparison screen names the title under the other climber's name.
- **Countdown.** Every board's window line and the Home weekly rank tile read `ENDS IN 2D 14H`, hours and minutes on the last day, and turn gold on the last day.
  All-time has none.
- **Recap.** The first open after a week or month closes shows a story: everyone's period, then your period (rank, climbs and steps with gains, badges earned named in words, new best efforts), then the crown (the winner's coronation page when the viewer won).
  Missed periods fold into one catch-up screen (at most four weeks and two months); a week and a month closing together show the month, then the week, and end on one page naming both champions; a period with no climbs is one short screen; someone who has never climbed gets everyone's period and the crown, ending on `START YOUR FIRST CLIMB`.
  It is shown once per period across every device, never over the lockout, sign-in, the paywall or onboarding.
- **Winner push.** The champion gets one push when they take the crown, with an opt-out in Settings.
- **Motion.** Crowns are static.
  The only animation is one shine when a crown first appears to a climber (the coronation and the recap's crown page).

## Data contract

Everything here is additive.
No existing document, rule, callable or Remote Config key changes meaning, so 1.0, 1.0.1 and 1.1 keep working untouched (`docs/backend-contract-compatibility.md`).

### `leaderboard_results/{timeFrame}_{periodKey}`

Written only by the Admin SDK, in the same batch as the period's achievements.
Readable by any climber with paid access.

| Field | Type | Meaning |
|---|---|---|
| `schemaVersion` | int | `1` |
| `timeFrame` | string | `weekly`, `monthly` or `yearly` |
| `periodKey` | string | The key `leaderboardPeriod.ts` derives, e.g. `2026-W38` |
| `periodStartAt`, `periodEndAt` | timestamp | The closed UTC window, end exclusive |
| `metric` | string | `steps` |
| `climberCount` | int | Climbers ranked on the period's Steps board (steps above zero), one per climber |
| `championUserIds` | string[] | Every rank-1 uid, board order |
| `podiumUserIds` | string[] | Every uid ranked 1-3, board order |
| `mostClimbs` | map or null | `{count, userIds}`: the highest `totalWorkouts` and every uid holding it (at most ten) |
| `community` | map | `{climbers, climbs, steps, floors}` summed over every climber in the period |
| `finalizedAt` | timestamp | When the finalizer (or the backfill) wrote it |
| `source` | string | `leaderboard_finalizer` or `backfill` |
| `reconstructed` | bool | `true` when the backfill rebuilt it from retained rows |

### `leaderboard_results/{resultId}/placings/{uid}`

One document per climber ranked 1-100, plus every most-climbs leader outside that range.
This is the frozen board: a past board never re-ranks, and a champion who deletes their account stays champion as `Anonymous Climber` instead of promoting the runner-up.

| Field | Type | Meaning |
|---|---|---|
| `schemaVersion` | int | `1` |
| `userId` | string | Owner of the placing, and the identity-propagation key |
| `timeFrame`, `periodKey`, `periodStartAt` | | Copied from the result |
| `rank` | int | Final standard-competition rank on Steps |
| `totalSteps`, `totalWorkouts` | int | The period's totals as frozen |
| `displayName`, `photoURL`, `identityPolicyVersion`, `identityState`, `identityChangedAt` | | The validated identity, the same fields a `leaderboard_stats` row carries |
| `isSynthetic` | bool | Seeded fixture marker |

Identity stays current through the `champion` kind in `functions/src/publicIdentityPropagation.ts`, which reaches placings through a collection-group query on `userId`.
Account deletion de-identifies placings (`Anonymous Climber`, no photo, `identityState: deleted`) and keeps the uid, exactly as it does replay entries.

### `users/{uid}/recaps/{cadence}_{periodKey}`

Composed by the server at 00:30 UTC after a week (Monday) or month (the 1st) closes, for every climber who ever climbed and, with the `never_climbed` variant, for every entitled account that has not.
The 13:00 UTC recap email sends from this stored payload, so the app and the email can never disagree.
The owner may read it and may set `seenAt` once, to `request.time`; nothing else is client-writable.

| Field | Type | Meaning |
|---|---|---|
| `schemaVersion` | int | `1` |
| `cadence` | string | `weekly` or `monthly` |
| `periodKey`, `periodStartAt`, `periodEndAt` | | The closed window |
| `variant` | string | `active`, `inactive` or `never_climbed` |
| `active` | map or null | Rank, climber count, percentile band, climbs, steps and floors with their prior-period values, award rank, First Ascents claimed in the period |
| `inactive` | map or null | Weeks or months since the last climb, and the suggested climb |
| `composedAt` | timestamp | When the compose step wrote it |
| `seenAt` | timestamp or null | When any of the owner's devices first showed it |

### Push

`users/{uid}/communication_preferences/current.pushChampionCrownEnabled` (absent means on) is set through the existing `updatePushNotificationPreferences` callable's new optional `championPushEnabled` field.
A new result written by the finalizer sends one `champion_crowned` push to each champion's deliverable devices.
`_champion_push_deliveries/{resultId}_{uid}` is created before a send so a retried trigger can never push twice, and a backfilled or stale result never pushes at all.

### Remote Config

- `champion_recognition_enabled` hides every champion surface (crowns, strip, past boards, countdown colour) without touching data.
- `period_recap_enabled` stops recap presentation and the `seenAt` write, the one new client write path.

## Reads the app makes

- **Reigning champions:** for each of weekly, monthly and yearly, the result for the period immediately before the current one, and its rank-1 placings - at most three document reads and three small queries per session, refreshed on foreground and when a period rolls.
  Until the finalizer has written that result (the first 15 minutes after a period closes) nobody reigns, rather than guessing.
- **Past boards:** a result and its placings ordered by rank.
- **Recap:** unseen recaps ordered by `periodEndAt`, newest first, at most six, plus the results they name.
