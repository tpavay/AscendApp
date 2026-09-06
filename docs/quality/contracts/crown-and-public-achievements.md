# Feature Contract: Crown and Public Achievements

- Issue: Not required: the 2026-08-10 Firstmate launch brief explicitly directs this isolated implementation without assigning an issue.
- Base branch: `develop`
- Change type: fix
- Owner: orchestrator

## User outcome

Leaderboard champions see a free-standing crown instead of a clipped square tile, and every climber can see another champion's earned leaderboard bands near the top of that climber's public profile.
A board nobody has entered yet renders the three pedestals with the crown seated in the open first-place slot, so the empty state shows the prize instead of an absence notice.

**Superseded on 2026-08-28 by #542 for the public-profile half only.**
The other climber's badges are no longer a 46-point one-sided shelf near the top of the comparison: they are one `ProfileAchievementComparisonRow` per badge type, both climbers counted, below ALL-TIME.
Anything below that describes only the other climber's ladder, or hides the section on that climber's emptiness, is history.
The crown half of this contract still stands.
The shipping rules now live in `ascend-profile`; the ladder's provable-versus-unreadable counts live in `podium-placement-badge-ladder.md`.

## Non-goals

- Do not change achievement awarding or the nightly leaderboard finalizer.
- Do not change or enqueue the `leaderboard_first_place` email.
- Do not change First Ascent or non-crown leaderboard token artwork.

## Acceptance criteria

- [ ] AC-1: The crown asset catalog contains only the prepared transparent `LeaderboardCrown.png` and the existing universal 1x, 2x, and 3x declarations.
- [ ] AC-2: The crown renders with aspect fit and without a rounded tile clip or tile border at 16, 30, 46, and 54 points.
- [ ] AC-3: First Ascent, Top 3, Top 10, and Top 100 tokens retain their existing framed presentation.
      Superseded on 2026-08-11 by `podium-placement-badge-ladder.md`: First Ascent joined the free-standing
      set when its art was re-cut, and the Top 3 band badge was retired. Top 10 and Top 100 followed later the
      same day with their own cut-out art, so no token frames any more and the framed branch is gone. The shelf
      art contract now lives in `ascend-profile`.
- [ ] AC-4: A loaded public profile renders only the other climber's nonzero leaderboard achievement bands and exact cumulative counts.
      Superseded on 2026-08-28 by #542: the section counts both climbers, the viewer on the left and the other on the right.
- [ ] AC-5: A loaded public profile with no achievements renders no achievement section.
      Superseded on 2026-08-28 by #542: the section hides only when *neither* climber is known to hold a badge, so the other climber's emptiness no longer hides the viewer's own trophies.
- [ ] AC-6: A public profile whose remote snapshot is still loading renders no achievement section at all; the bands appear only once the counts resolve.
- [ ] AC-7: Public achievement badges are non-interactive, because the public snapshot carries no records for the history sheet to show.
      The own-profile shelf keeps its history sheet, including when a band has no backing records yet.
      Still true after #542, now of the comparison rows rather than a public shelf.

## State matrix

| State | Expected behavior | Verification |
|---|---|---|
| Happy path | Both climbers' badges appear below All-Time, one row per badge type, with exact counts and no tap target (#542; before that, the other climber's shelf alone sat between Profile and All-Time). | Hosted SwiftUI rendering test and simulator evidence. |
| Loading | Nothing renders while the other profile snapshot loads - no heading, no placeholder badges - so no count is ever shown before it is known. | Hosted SwiftUI rendering test. |
| Empty | The entire achievement section is absent after a zero-count snapshot loads - since #542, only when both climbers' snapshots are empty. | Hosted SwiftUI rendering test. |
| Error/offline | The existing remote profile loading/error behavior remains authoritative; this section reflects the snapshot state it receives. | Existing profile loading tests and regression review. |

## Test mapping

| Acceptance criterion | Automated test or evidence | Why it proves the behavior |
|---|---|---|
| AC-1 | Asset-catalog file and alpha-channel inspection. | Verifies the prepared file is the only referenced crown bitmap and retains transparent pixels. |
| AC-2 | Source contract inspection plus rendered crown evidence at every requested size. | Detects fill, clipping, borders, square edges, and cropped crown points. |
| AC-3 | Rendered prestige shelf evidence with all non-crown tokens. | Detects any shared presentation regression. |
| AC-4 | `PublicProfileAchievementRenderingTests.bothClimbersBadgesRenderOnTheirOwnSideOfEveryRow`. | Hosts the shipping section and reads back every supplied count, attributed to its side, from accessibility output. |
| AC-5 | `PublicProfileAchievementRenderingTests.twoClimbersWithNoBadgesRenderNoPublicAchievementShell`, `.aDecoratedViewerStillSeesTheirOwnBadgesAgainstAnEmptyClimber`. | Proves no heading or badge remains when neither climber holds one, and that one climber's emptiness alone does not hide the section. |
| AC-6 | `PublicProfileAchievementRenderingTests.loadingAchievementsRenderNothingUntilTheCountsResolve`. | Proves no heading and no band label reaches the accessibility tree while the snapshot is loading. |
| AC-7 | `PublicProfileAchievementRenderingTests.publicComparisonRowsNeverOpenAchievementHistory` and `.ownProfileBadgesStayTappableWithNoFinalizedRows`. | Proves the comparison rows expose no button trait while the record-backed own-profile shelf still does. |

## UX evidence

- Capture the 16-point leaderboard row crown, 30-point podium crown, 46-point and 54-point own-profile crowns in dark mode.
  The 46-point size was the public-profile shelf's until #542 replaced it with 32-point row art; the size check survives as crown evidence.
- Capture the public profile in present, absent, and loading states on an iPhone 16 Pro device-type simulator - the last two show no achievement section.
  Since #542 the absent state means both climbers empty, and `PublicProfileAchievementsVisualEvidenceTests` captures the lopsided matchups too.
- Verify VoiceOver announces each achievement label and count on a loaded public profile - since #542, attributed to "you" and "them" - and announces nothing for it while the snapshot loads.
- Verify the public badges carry no button trait and the non-crown tokens retain their frames.
  The frame half of that check is superseded with AC-3 above: no token frames any more.

## Risk and rollout

This change does not migrate data, write persisted state, change analytics, alter privacy collection, or change backend contracts.
The public profile already loads public-safe achievement counts and records, so rendering them adds no new data access.
Rollback is a normal binary and asset rollback with no deployment ordering requirement.

## Human gates

- None.
