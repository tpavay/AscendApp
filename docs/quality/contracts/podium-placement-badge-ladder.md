# Feature Contract: Podium Placement Badge Ladder

- Issue: Not required: the 2026-08-11 Firstmate launch brief directs this implementation without assigning an issue.
- Base branch: `develop`
- Change type: feature
- Owner: orchestrator

## User outcome

A climber's achievement shelf names the exact place they finished instead of lumping second and third into one band.
The shelf reads First Ascents, CHAMPION, #2, #3, TOP 10, TOP 100, on their own profile and on anyone else's, and the placement badges carry the captain's cut-out medal art.

## Non-goals

- Do not change achievement awarding, the nightly leaderboard finalizer, or `functions/src/leaderboardAchievements.ts`.
- Do not restyle or replace the TOP 10 and TOP 100 artwork; new art for those is a separate follow-up.
- Do not change how the banded `profile_stats` counters are published or read.

## Acceptance criteria

- [ ] AC-1: The shelf renders First Ascents, CHAMPION, #2, #3, TOP 10, TOP 100, in that order, on the climber's own profile and on another climber's.
- [ ] AC-2: The #2 and #3 counts equal the number of achievement records whose stored `rank` is exactly 2 and exactly 3, for the profile being viewed.
- [ ] AC-3: A profile whose achievement records did not load renders no #2 and no #3 badge, and still renders every badge its banded counters support.
- [ ] AC-4: The retired TOP 3 band badge never renders, and no code references the `LeaderboardTop3` asset.
- [ ] AC-5: First Ascents, CHAMPION, #2 and #3 render free-standing - no clip, no tile, no border. TOP 10 and TOP 100 keep their framed tile.
      Superseded on 2026-08-11 once the TOP 10 and TOP 100 cut-out art landed: every shelf badge is now free-standing,
      the framed branch and the `usesFreeStandingArt` flag were deleted, and the shelf art contract lives in `ascend-profile`.
- [ ] AC-6: None of the four replaced assets is set to `template` rendering intent, so each keeps its own colour.
- [ ] AC-7: Tapping a placement badge on the own-profile shelf lists only the finishes at that exact rank; a band badge still lists every finish inside the band.

## State matrix

| State | Expected behavior | Verification |
|---|---|---|
| Happy path | Records loaded: the full ladder renders, placement counts equal the exact recorded ranks. | `ProfileAchievementLadderTests`, `PublicProfileAchievementRenderingTests`, own-profile shelf evidence. |
| Records missing | Banded counters only: CHAMPION, TOP 10 and TOP 100 render with their counters; #2 and #3 are absent rather than guessed. | `PublicProfileAchievementRenderingTests.aProfileWithoutRecordsRendersTheBandsAndNoPlacements`, banded-fallback evidence. |
| Loading | Nothing renders on another climber's profile until the snapshot resolves. | `PublicProfileAchievementRenderingTests.loadingAchievementsRenderNothingUntilTheCountsResolve`. |
| Empty | No achievements: the shelf becomes the existing activation state. | `PublicProfileAchievementRenderingTests.twoClimbersWithNoBadgesRenderNoPublicAchievementShell`. |
| Error/offline | Existing profile loading and error behavior stays authoritative; the ladder reflects the snapshot it receives. | Existing profile loading tests. |

## Why the fallback path shows no placement

`ProfileScreenViewModel` prefers the finalized achievement records, which store the climber's exact finishing rank.
When none arrive it falls back to `profile_stats`, whose counters are banded into top 1 / 3 / 10 / 100 and carry no second-versus-third breakdown.
`ProfileAchievementLadder` makes that difference explicit: the record-backed initializer produces `placements` and the banded initializer produces `nil`, and `ProfilePrestigeToken.tokens(for:surface:)` reads `ProfileAchievementCatalogue.definitions(for:)`, so the placement badges are now gated by the `place2` / `place3` entries' `count` closures over `secondPlaceFinishes` / `thirdPlaceFinishes`.
A band is never read as a placement.
The one inference that *is* provable is zero: every second and third also counts toward `top3`, so a banded ladder whose `top3` holds nothing beyond its `top1` answers both placements with `0` rather than withholding them.
Separately, a ladder whose read failed is `.unreadable` and answers `nil` for every count, which the comparison screen renders as a dash rather than as a withheld badge.

That path is reached when a climber's `achievements` subcollection returns empty while their `profile_stats` document still reports finishes - a profile published before the records were written, a partial read, or a permission-scoped read that returned nothing.

## Test mapping

| Acceptance criterion | Automated test or evidence | Why it proves the behavior |
|---|---|---|
| AC-1 | `ProfileAchievementLadderTests.theLadderRendersChampionSecondThirdTopTenTopHundredInOrder`, `PublicProfileAchievementRenderingTests.theLadderRendersInChampionSecondThirdTopTenTopHundredOrder`, own-profile shelf evidence. | Asserts the emitted token order and the rendered accessibility order on both profiles. |
| AC-2 | `ProfileAchievementLadderTests.placementsCountTheExactRecordedRanks` and `.placementsIgnoreRecordsWithNoLeaderboardRankBand`. | Counts exact ranks and proves a First Ascent never becomes a placement. |
| AC-3 | `PublicProfileAchievementRenderingTests.aProfileWithoutRecordsRendersTheBandsAndNoPlacements`, `ProfileAchievementLadderTests.theBandedFallbackWithholdsBothPlacementBadges`. | Proves the banded ladder emits no placement badge and still emits the bands. |
| AC-4 | `ProfileAchievementLadderTests.theRetiredTopThreeBandNeverBecomesABadge`, repo-wide grep for `LeaderboardTop3`. | Proves a top-three record raises no TOP 3 badge and the asset reference is gone. |
| AC-5 | Rendered shelf evidence. The token-splitting test was deleted with the flag it read; `PublicProfileAchievementRenderingTests.everyShelfBadgeShipsAsFreeStandingColourArt` now guards the single free-standing presentation. | Photographs the presentation and fails on any asset that reintroduces an opaque backing or template rendering. |
| AC-6 | `PublicProfileAchievementRenderingTests.everyShelfBadgeShipsAsFreeStandingColourArt`, which superseded the manual `Contents.json` inspection once TOP 10 and TOP 100 joined the free-standing set. | Asserts every shelf asset resolves as `.alwaysOriginal`, so no replacement can reintroduce `template` rendering intent. |
| AC-7 | `ProfileAchievementLadderTests.aPlacementBadgeListsOnlyItsOwnRankInHistory` and `.aBandBadgeStillListsEveryFinishInsideIt`. | Proves the history filter separates exact placements from bands. |

## UX evidence

- `own-profile-achievements-full-ladder.png` - the six-badge shelf with records loaded.
- `own-profile-achievements-banded-fallback.png` - the records-missing shelf, with no #2 and no #3.
- `crown-and-prestige-tokens.png` - the ladder at 54 points beside the 16 and 30 point crowns.
- `public-profile-achievements-both-decorated.png`, `public-profile-achievements-viewer-decorated.png`, `public-profile-achievements-other-decorated.png` - the comparison rows for each matchup.
- `onboarding-skip-box-ticked.png` - the onboarding notifications screen, which shares the re-cut First Ascent art.

## Risk and rollout

No data migration, no persisted write, no analytics change, no privacy-collection change, and no backend contract change: the exact ranks were already stored on every achievement record and are only now being read.
Rollback is a normal binary and asset rollback with no deployment ordering requirement.

## Human gates

- The captain supplied and approved the four cut-out assets and approved retiring the TOP 3 band.
