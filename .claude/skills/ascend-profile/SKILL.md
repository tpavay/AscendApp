---
name: ascend-profile
description: Use when working on Ascend profiles - own vs other-user profile surfaces, profile section order and visibility, the Collection preview, profile demographics (age, gender, weight, location), public profile mirrors, or profile stat derivation. Covers why public reads must use public-safe mirrors and where profile business logic belongs.
paths:
  - AscendApp/Features/Profile/**
---

# Profile

## Profile Demographics
- Post-auth onboarding captures display name and declared demographics on `users/{uid}`. Age must stay a bounded integer from 13 through 120, and gender must use the `ProfileGender` raw values: `woman`, `man`, `non_binary`, or `prefer_not_to_say`.
- Profile demographics for V1 are public by default with no per-field opt-out: age, gender, body weight, country/region, and joined date may appear on profiles and leaderboard-adjacent surfaces. Email and authentication/provider data remain private.
- Custom display names and profile photos are **not public** at launch (App Store Guideline 1.2): other users see only a stable UID-derived system handle (`Climber XXXXXX`) and a generic avatar, while self-only screens keep the owner's custom name and photo.
  `PublicClimberIdentity` (`AscendApp/Shared/Models/`) is the single reversible policy seam that resolves every public presentation; never publish account-authored identity to a public document.
  Public profile mirrors and leaderboard rows store the pinned values `displayName: "Climber"` and empty `photoURL` (`firestore.rules` rejects anything else), the server-owned replay subtree is sanitized the same way by the Cloud Function, and only entries carrying the server-owned `isSynthetic` marker keep authored fixture identity.
  Sanitizing pre-existing records and reversibility: `docs/public-identity-sanitization-runbook.md`.
- Firestore does not support field-level read masking on a document. Keep `users/{uid}` owner-readable because it contains private account fields, and mirror only public-safe profile fields into public profile documents/subcollections for other-user profile reads.

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
