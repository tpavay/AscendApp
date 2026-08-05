---
name: ascend-profile
description: Use when working on Ascend profiles - own vs other-user profile surfaces, profile section order and visibility, the Collection preview, profile demographics (age, gender, weight, location), public profile mirrors, or profile stat derivation - and when publishing or rendering another climber's display name or photo anywhere, including block, report, and the shared moderation resolver. Covers why public reads must use public-safe mirrors, the Guideline 1.2 identity policy, and where profile business logic belongs.
---

# Profile

## Profile Demographics
- Post-auth onboarding captures display name and declared demographics on `users/{uid}`. Gender must use the `ProfileGender` raw values: `woman`, `man`, `non_binary`, or `prefer_not_to_say`.
- **Age is derived, never stored fresh.**
  The stored field is `birth_date`, a private `YYYY-MM-DD` calendar string on `users/{uid}`, bounded so the derived age lands between 13 and 120.
  `ProfileBirthday` (`AscendApp/Shared/Models/`) parses it and computes age on device, and `functions/src/leaderboardStats.ts` derives the same number server-side for board demographics.
  Storing a typed number instead would freeze a climber's age on the day they entered it.
  Climbers who onboarded before the birthday field keep their legacy `age` integer, consulted only when no birthday exists - there is no backfill and no migration (issue #375), and writing a birthday clears the legacy `age`.
- Profile demographics for V1 are public by default with no per-field opt-out: age, gender, body weight, country/region, and joined date may appear on profiles and leaderboard-adjacent surfaces.
  **`birth_date` itself is not one of them** - it stays on the private user document, and only the derived age may reach a public projection or payload.
  `AscendAppTests/ProfileBirthdayTests.swift` fails if the date reaches the public identity payload.
  Email and authentication/provider data remain private.
- Custom display names and profile photos are public account identity only while App Review Guideline 1.2 moderation remains enforced.
  `PublicClimberIdentity` (`AscendApp/Shared/Models/`) resolves account-authored identity, a stable UID-derived fallback, synthetic fixture identity, and the deleted-account `Anonymous Climber` sentinel.
  Every cross-user view must pass that presentation through `ResolvedUserIdentity.Resolver`, which replaces only a blocked climber's name and photo while preserving rank, metrics, and demographics.
  Public profile, leaderboard, Live Replay, finisher, and First Ascent mirrors store validated identity, and the server propagation trigger keeps existing projections current.
  Production has no identity backfill to run: the propagation trigger and its indexes must be deployed before the binary that publishes identity. Rollout order: `docs/production-backend-rollout-runbook.md`.
  Dev and staging do hold pre-policy rows, and the only sanctioned repair writes the public profile mirror and lets that same trigger fan it out - never `leaderboard_stats` directly, which rules make server-owned outright. See `ascend-dev-fixtures`.
- Firestore does not support field-level read masking on a document. Keep `users/{uid}` owner-readable because it contains private account fields, and mirror only public-safe profile fields into public profile documents/subcollections for other-user profile reads.

## Block and Report (Guideline 1.2)
- A block is personal and immediate: one tap, no reason, no approval, and it changes only the blocker's own view.
  `users/{blockerUid}/blocked/{blockedUid}` is the source of truth and hydrates on sign-in so a new device inherits every block; the local cache exists for render speed and is never authoritative.
- A block keeps the row and hides only the identity.
  Rank, steps, times, and demographics stay; only `displayName` and `photoURL` become a neutral placeholder and generic avatar.
  Removing or reordering blocked rows is permanently rejected - it would let anyone improve their standing by blocking the climbers above them and would leave gaps in a ranked list.
- Enforcement lives in the one shared resolver, never per screen, because filtering inside each screen guarantees the next surface someone adds leaks silently.
  The boundary is compiler-enforced: raw identity types keep private members and redacted descriptions, SwiftUI files cannot name them, and views accept only `Moderated*` render models.
  `AscendAppTests/AuditedIdentitySurfaceTests.swift` fails if any audited surface renders a blocked climber's real name or photo.
- A report requires a reason picker - you cannot triage without one - and writes reported uid, reporter uid, reason, timestamp, and source surface to a queue only the captain reads.
  Reporting is not a block and changes nothing for the reporter, and blocking files a report only when the blocker explicitly checks the optional report box.
- There is exactly one moderation placement: the overflow menu on `OtherUserProfileView`, plus the Blocked climbers row in `AccountView`'s Privacy section.
  Long-press menus, inline buttons, and mid-climb affordances are ruled out; reaching moderation from a new surface is a navigation change that routes to that same profile, not a new menu.
- Display names are screened at write time so an objectionable name is never published; photo moderation is deliberately reactive (report, human review, removal) with no automated image scanning.

## Profile Architecture
- Profile has two display modes: `OwnProfileView` and `OtherUserProfileView`. Own profile keeps empty sections visible as activation moments; other-user profile hides empty sections entirely unless a comparison state needs to explain why comparison is unavailable.
- The profile tab entry point remains `ProfileView`, but it should delegate to the own-profile surface rather than owning all profile layout and business logic directly.
- Profile sections render in this order: identity hero, other-user comparison, Active Standings, Activity + Streak, Collection, Achievements, First Ascents, Records, Trends, Recent Workouts.
- Active Standings stays above Activity because active competition is more urgent than long-arc history. First Ascents stay above Records because permanent competitive prestige is more aspirational than personal records. Trends sit between Records and Recent Workouts.
- Collection on Profile is a 3-card preview, never the full Pokedex. Card composition adapts to claimed climbs: 0 claimed shows 3 recommended unclaimed; 1 claimed shows 1 claimed + 2 recommended unclaimed; 2 claimed shows 2 claimed + 1 recommended unclaimed; 3+ claimed shows the 3 most recent claimed.
- Claimed climbs retain the Climb action. A small checkmark badge overlay on the thumbnail signals claimed state; the action button is never replaced or hidden by completion.
- Recommended unclaimed Collection cards sort by tier ascending, then step count ascending, and exclude climbs the user has already claimed. The full collection grid lives behind the `View all` link as a separate page.
- Public profile reads must use public-safe documents/subcollections such as public profile, cached profile stats, achievements, and public workout summaries. Never read private workout backups to render another user's profile.
- Business logic for profile section visibility, achievement counting, ranking subtitles, comparison state, and stat derivation belongs in models/services that can be unit tested without a SwiftUI view tree.

## Related
- Bodyweight is a single profile-level value editable in settings - see `ascend-onboarding`.
- Adding a profile field is a Firestore schema-change tripwire and a privacy-manifest tripwire. See `ascend-firebase-data` and `ascend-privacy-manifest`.
