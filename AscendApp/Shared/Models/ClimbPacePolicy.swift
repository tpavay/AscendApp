import Foundation

/// The automatic plausibility check for a climb Ascend did not measure itself.
///
/// A live climb is read off the headphones' motion sensor and keeps its own gate
/// (`WorkoutPlausibilityPolicy`, 220 steps/min). A climb the climber typed in has no sensor behind
/// it, so its pace is the only evidence there is, and this is the whole of the check. There is no
/// report button, no review queue and no hold on a top placing - the number decides, and it runs
/// at exactly two moments: when the climb is saved, and when its steps or time are edited.
///
/// Pace is average steps per minute. Two thresholds cut it into three outcomes:
///
/// - **Within the ceiling** (up to and including 200): counts everywhere.
/// - **Above the ceiling, below absurd**: the climb is saved and counts for history, streak and
///   goals, and stays off leaderboards and the Best Efforts that feed them. Editing the steps or
///   time re-runs the check and puts it on or takes it off.
/// - **Absurd** (300 and up): the save is refused with a message, because no stair stepper
///   produces it and the likeliest explanation is a typo.
///
/// The ceiling is above the machines and well above the measured climbers. StairMaster's fastest
/// console setting is 190 steps/min (`SPMMappingService.levelToSPM`), and the fastest of the 104
/// production climbs measured when this was set (2026-10-30) averaged 127. 200 keeps a margin
/// over the machine's top setting so an honest, hard climb is never excluded, while still sitting
/// far below what a fabricated number would need to be to take a board.
///
/// The server applies the same two numbers again - `functions/src/leaderboardStats.ts` for the
/// ceiling and `isPhysicallyPossibleClimb` in `firestore.rules` for the absurd bound - and
/// `SharedTestVectors/climb-pace-policy-vector.json` holds all three to the same answers.
enum ClimbPacePolicy {
    /// The fastest average cadence a climb Ascend did not measure can carry and still rank.
    static let leaderboardCeilingStepsPerMinute: Double = 200

    /// The average cadence at which a save is refused outright.
    ///
    /// Equal to `firestore.rules`' `isPhysicallyPossibleClimb` bound of five steps a second, so
    /// every climb this lets through is one the cloud accepts: a refused write is a climb that can
    /// never back up.
    static let absurdStepsPerMinute: Double = 300

    /// The most steps one climb can hold. Equal to `isPhysicallyPossibleClimb`'s per-submission
    /// cap in `firestore.rules`, just above the 24-hour StairMaster record, so a typed climb the
    /// app saves is never one the cloud refuses.
    static let maximumSteps = 120_000

    /// The longest single climb that can be logged. The server will not score a session past a
    /// day either (`MAX_WORKOUT_DURATION_SECONDS`), so a longer one would save and never rank.
    static let maximumDuration: TimeInterval = 24 * 60 * 60

    enum Verdict: Equatable, Sendable {
        /// At or under the ceiling. Counts everywhere.
        case withinCeiling
        /// Over the ceiling and under the absurd line. Saves, but stays off the boards.
        case aboveCeiling(stepsPerMinute: Double)
        /// At or over the absurd line. The save is refused.
        case absurd(stepsPerMinute: Double)

        var isSaveable: Bool {
            if case .absurd = self { return false }
            return true
        }

        var leaderboardStatus: LeaderboardStatus {
            switch self {
            case .withinCeiling:
                return .eligible
            case .aboveCeiling, .absurd:
                return .excluded
            }
        }
    }

    /// Average steps per minute, or nil when either input cannot describe a pace.
    static func stepsPerMinute(steps: Int, duration: TimeInterval) -> Double? {
        guard steps > 0, duration > 0 else { return nil }
        return Double(steps) / (duration / 60)
    }

    /// The verdict for a climb's totals.
    ///
    /// A climb with no steps has no pace to judge, so it is never refused: the Add steps prompt,
    /// not this check, is what asks for them. `leaderboardStatus` is where it is kept off the
    /// boards.
    static func verdict(steps: Int, duration: TimeInterval) -> Verdict {
        guard let pace = stepsPerMinute(steps: steps, duration: duration) else {
            return .withinCeiling
        }
        if pace >= absurdStepsPerMinute {
            return .absurd(stepsPerMinute: pace)
        }
        if pace > leaderboardCeilingStepsPerMinute {
            return .aboveCeiling(stepsPerMinute: pace)
        }
        return .withinCeiling
    }

    /// What this device concludes about a climb's leaderboard standing.
    ///
    /// A live climb keeps today's behaviour: every one is `eligible` here, and the 220 gate plus
    /// the server's own derivation are what bound it. Anything else is judged on pace, and a climb
    /// with no steps has none - it is an entry still waiting for its number, and the server will
    /// not count it either (`parseEligibleWorkout`).
    static func leaderboardStatus(
        origin: ClimbOrigin,
        steps: Int,
        duration: TimeInterval
    ) -> LeaderboardStatus {
        guard origin != .live else { return .eligible }
        guard stepsPerMinute(steps: steps, duration: duration) != nil else { return .excluded }
        return verdict(steps: steps, duration: duration).leaderboardStatus
    }
}
