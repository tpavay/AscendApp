import Foundation

/// One climber's completion history on one climb, as the finish card needs it.
///
/// Read once from the local store and handed to `PersonalClimbPlacing`, which
/// owns the arithmetic. Every number here is stated about the *other*
/// completions, so the completion being placed is counted exactly once and only
/// by the placing itself.
struct PersonalClimbCompletionHistory: Equatable, Sendable {
    /// Completions recorded on this climb other than the one being placed.
    ///
    /// Counted in completions, not in stored rows: a reinstall rebuilds a
    /// climber's whole history on a tower as one row carrying the count, so
    /// counting rows told a climber with six finishes that they had two.
    let otherCompletionsCount: Int

    /// The durations known for those completions.
    ///
    /// Shorter than `otherCompletionsCount` on a restored install, which keeps
    /// only the best duration of the history it rebuilt. The placing counts what
    /// it can see as faster and claims nothing about the rest.
    let otherCompletionDurationsSeconds: [Int]

    /// Whether the completion being placed is the earliest the climber has
    /// recorded here.
    ///
    /// Permanent, which is the point: climbing the tower again never changes
    /// which run came first. A First Ascent is resolved from this rather than
    /// from "this is my only climb here", which expires.
    let isEarliestCompletionHere: Bool

    /// The climber's finisher order on this climb, as the server reported it, or
    /// nil where this device has never been told one. `1` means they took the
    /// tower's First Ascent.
    let globalCompletionOrder: Int?

    static let none = PersonalClimbCompletionHistory(
        otherCompletionsCount: 0,
        otherCompletionDurationsSeconds: [],
        isEarliestCompletionHere: false,
        globalCompletionOrder: nil
    )

    /// Whether this completion is the one that claimed the tower's First Ascent.
    ///
    /// Two permanent halves: the climber holds the tower's First Ascent, and this
    /// is the first run of theirs on it. A finisher order this device has never
    /// been told says nothing either way, so it does not veto the claim - the
    /// caller has already established that nobody else had finished.
    var claimsFirstAscent: Bool {
        isEarliestCompletionHere && (globalCompletionOrder ?? 1) == 1
    }
}
