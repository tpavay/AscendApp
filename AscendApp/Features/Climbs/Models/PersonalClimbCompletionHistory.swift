import Foundation

/// One climber's completion history on one climb, as the finish card needs it.
///
/// Read once from the local store and handed to `PersonalClimbPlacing`, which
/// owns the arithmetic. Every number here is stated about the *other*
/// completions, so the completion being placed is counted exactly once and only
/// by the placing itself.
struct PersonalClimbCompletionHistory: Equatable, Sendable {
    /// How much of the climber's history on this tower this device can account
    /// for, run by run.
    ///
    /// The device holds two different kinds of evidence and they are not
    /// interchangeable. Normally every completion is a row of its own, restored
    /// workout by workout - so its duration and its date are both exact. But a
    /// climb whose workouts could not be restored is rebuilt by
    /// `ClimbCompletionRepository.reconcile` as a single stand-in row carrying an
    /// aggregate count and the climber's best duration, and nothing else. The
    /// count is trustworthy; the order inside it is not, and neither is which run
    /// came first. Stating that difference is what keeps a claim off the evidence
    /// that cannot carry it.
    enum DurationEvidence: Equatable, Sendable {
        /// Every other completion is on hand with its own duration and its own
        /// date.
        case complete
        /// At least one completion is represented only by a collapsed stand-in.
        case partial
    }

    /// Completions recorded on this climb other than the one being placed.
    ///
    /// Counted in completions, not in stored rows: a collapsed row carries the
    /// count of the history it stands for, so counting rows told a climber with
    /// six finishes that they had two.
    let otherCompletionsCount: Int

    /// The durations known for those completions.
    ///
    /// Shorter than `otherCompletionsCount` wherever `durationEvidence` is
    /// `.partial`.
    let otherCompletionDurationsSeconds: [Int]

    /// Whether the durations above account for every one of those completions.
    let durationEvidence: DurationEvidence

    /// Whether the completion being placed is the earliest the climber has
    /// recorded here.
    ///
    /// Permanent, which is the point: climbing the tower again never changes
    /// which run came first. Never true where a collapsed stand-in is in play -
    /// it cannot say which of the runs it stands for came first, so it refuses
    /// rather than guesses. A completion this device recorded without a usable
    /// duration still carries its own exact date and does not refuse.
    let isEarliestCompletionHere: Bool

    /// The climber's finisher order on this climb, as the server reported it, or
    /// nil where this device has never been told one. `1` means they took the
    /// tower's First Ascent.
    let globalCompletionOrder: Int?

    /// Whether this completion is the one that claimed the tower's First Ascent.
    ///
    /// Both halves demand positive evidence. A finisher order this device was
    /// never told is not evidence of holding one, and a claim the design calls
    /// permanent and unreclaimable withholds rather than grants.
    var claimsFirstAscent: Bool {
        isEarliestCompletionHere && globalCompletionOrder == 1
    }
}
