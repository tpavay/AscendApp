import Foundation

/// Whether a climb counts toward leaderboards, as this device last concluded.
///
/// A record, never an instruction. The server derives eligibility again from the workout's own
/// `source`, `steps` and `durationSeconds` (`functions/src/leaderboardStats.ts`) and never reads
/// this value, because a client cannot be trusted to rate its own entry. What this drives is
/// everything on the device that has to agree with that verdict: the optimistic board overlay,
/// Best Efforts, and the note that tells a climber why a climb is not ranked.
///
/// Stored as a raw value so it can appear in a `#Predicate`.
///
/// There is no review state: the automatic checks are the only gate. A climb the pace check excludes
/// returns to the boards the moment an edit brings it back inside the ceiling; one the join-date
/// rule excludes stays off whatever its pace, until its date moves after the account's creation.
enum LeaderboardStatus: String, CaseIterable, Codable, Sendable {
    case eligible
    case excluded
}
