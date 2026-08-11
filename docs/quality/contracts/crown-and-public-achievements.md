# Feature Contract: Crown and Public Achievements

- Issue: Not required: the 2026-08-10 Firstmate launch brief explicitly directs this isolated implementation without assigning an issue.
- Base branch: `develop`
- Change type: fix
- Owner: orchestrator

## User outcome

Leaderboard champions see a free-standing crown instead of a clipped square tile, and every climber can see another champion's earned leaderboard bands near the top of that climber's public profile.
A board nobody has entered yet renders the three pedestals with the crown seated in the open first-place slot, so the empty state shows the prize instead of an absence notice.

## Non-goals

- Do not change achievement awarding or the nightly leaderboard finalizer.
- Do not change or enqueue the `leaderboard_first_place` email.
- Do not change First Ascent or non-crown leaderboard token artwork.

## Acceptance criteria

- [ ] AC-1: The crown asset catalog contains only the prepared transparent `LeaderboardCrown.png` and the existing universal 1x, 2x, and 3x declarations.
- [ ] AC-2: The crown renders with aspect fit and without a rounded tile clip or tile border at 16, 30, 46, and 54 points.
- [ ] AC-3: First Ascent, Top 3, Top 10, and Top 100 tokens retain their existing framed presentation.
- [ ] AC-4: A loaded public profile renders only the other climber's nonzero leaderboard achievement bands and exact cumulative counts.
- [ ] AC-5: A loaded public profile with no achievements renders no achievement section.
- [ ] AC-6: A public profile whose remote snapshot is still loading renders no achievement section at all; the bands appear only once the counts resolve.
- [ ] AC-7: Public achievement badges are non-interactive, because the public snapshot carries no records for the history sheet to show.
      The own-profile shelf keeps its history sheet, including when a band has no backing records yet.

## State matrix

| State | Expected behavior | Verification |
|---|---|---|
| Happy path | The other climber's crown and earned bands appear between Profile and All-Time, with exact counts and no tap target. | Hosted SwiftUI rendering test and simulator evidence. |
| Loading | Nothing renders while the other profile snapshot loads - no heading, no placeholder badges - so no count is ever shown before it is known. | Hosted SwiftUI rendering test. |
| Empty | The entire achievement section is absent after a zero-count snapshot loads. | Hosted SwiftUI rendering test. |
| Error/offline | The existing remote profile loading/error behavior remains authoritative; this section reflects the snapshot state it receives. | Existing profile loading tests and regression review. |

## Test mapping

| Acceptance criterion | Automated test or evidence | Why it proves the behavior |
|---|---|---|
| AC-1 | Asset-catalog file and alpha-channel inspection. | Verifies the prepared file is the only referenced crown bitmap and retains transparent pixels. |
| AC-2 | Source contract inspection plus rendered crown evidence at every requested size. | Detects fill, clipping, borders, square edges, and cropped crown points. |
| AC-3 | Rendered prestige shelf evidence with all non-crown tokens. | Detects any shared presentation regression. |
| AC-4 | `PublicProfileAchievementRenderingTests` present-state case. | Hosts the shipping section and reads back every supplied count from accessibility output. |
| AC-5 | `PublicProfileAchievementRenderingTests` absent-state case. | Proves no heading or badge remains after a zero-count load. |
| AC-6 | `PublicProfileAchievementRenderingTests.loadingAchievementsRenderNothingUntilTheCountsResolve`. | Proves no heading and no band label reaches the accessibility tree while the snapshot is loading. |
| AC-7 | `PublicProfileAchievementRenderingTests.publicBadgesNeverOpenAchievementHistory` and `.ownProfileBadgesStayTappableWithNoFinalizedRows`. | Proves the public shelf exposes no button trait while the record-backed own-profile shelf still does. |

## UX evidence

- Capture the 16-point leaderboard row crown, 30-point podium crown, 46-point public-profile crown, and 54-point own-profile crown in dark mode.
- Capture the public profile in present, absent, and loading states on an iPhone 16 Pro device-type simulator - the last two show no achievement section.
- Verify VoiceOver announces each achievement label and count on a loaded public profile, and announces nothing for it while the snapshot loads.
- Verify the public badges carry no button trait and the non-crown tokens retain their frames.

## Risk and rollout

This change does not migrate data, write persisted state, change analytics, alter privacy collection, or change backend contracts.
The public profile already loads public-safe achievement counts and records, so rendering them adds no new data access.
Rollback is a normal binary and asset rollback with no deployment ordering requirement.

## Human gates

- None.
