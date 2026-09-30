import Foundation

/// One published climb as a path up the stairs: how many steps it had taken at each moment of
/// its own clock, learned a checkpoint at a time from the race board.
///
/// The board publishes a climb as cumulative steps at the end of each ten-second bucket, and a
/// live session reads the bucket it is in every few seconds, so the checkpoints arrive in order
/// as the race goes on. Between two known points the climber is drawn on the straight line
/// joining them; beyond the last one they head for their finish at the pace that gets them
/// there. The steps can only rise, so a ghost never walks backwards.
struct MountainRivalCurve: Equatable, Sendable {
    struct Checkpoint: Equatable, Sendable {
        let seconds: Double
        let steps: Double
    }

    /// Where the climb ended, in steps.
    let finalSteps: Double
    /// When the climb ended on its own clock, or nil where the board does not say.
    let finishSeconds: Double?
    /// Known points strictly between the start and the finish, in time order.
    private(set) var checkpoints: [Checkpoint] = []

    init(finalSteps: Double, finishSeconds: Double?) {
        self.finalSteps = max(finalSteps, 0)
        self.finishSeconds = finishSeconds.flatMap { $0 > 0 ? $0 : nil }
    }

    /// Adds what the board said this climb had reached at `seconds`, held between the points
    /// either side of it so the path keeps rising.
    mutating func record(steps: Double, atSeconds seconds: Double) {
        guard seconds > 0, steps.isFinite else { return }
        if let finishSeconds, seconds >= finishSeconds { return }

        let floor = checkpoints.last { $0.seconds < seconds }?.steps ?? 0
        let ceiling = checkpoints.first { $0.seconds > seconds }?.steps ?? finalSteps
        let checkpoint = Checkpoint(seconds: seconds, steps: min(max(steps, floor), max(ceiling, floor)))

        if let existing = checkpoints.firstIndex(where: { $0.seconds == seconds }) {
            checkpoints[existing] = checkpoint
        } else {
            checkpoints.insert(checkpoint, at: checkpoints.firstIndex { $0.seconds > seconds } ?? checkpoints.endIndex)
        }
    }

    /// Keeps the path exactly where it is drawn at `seconds`, whatever is learned after: a point
    /// learned later then bends the path from here instead of moving where it stands now.
    mutating func pin(atSeconds seconds: Double) {
        guard seconds > 0 else { return }
        record(steps: steps(at: seconds), atSeconds: seconds)
    }

    /// Steps taken `seconds` into the climb.
    func steps(at seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        if let finishSeconds, seconds >= finishSeconds { return finalSteps }

        // Read every frame for every racer on the board, so found by halving, not by scanning.
        let next = firstCheckpoint(after: seconds)
        let before = next > 0 ? checkpoints[next - 1] : Checkpoint(seconds: 0, steps: 0)
        if next < checkpoints.count {
            return Self.interpolate(before, checkpoints[next], at: seconds)
        }
        if let finishSeconds {
            return Self.interpolate(before, Checkpoint(seconds: finishSeconds, steps: finalSteps), at: seconds)
        }
        // No finish time: carry on at the pace the climb has shown so far.
        guard before.seconds > 0 else { return 0 }
        return min(before.steps + before.steps / before.seconds * (seconds - before.seconds), finalSteps)
    }

    /// The index of the first checkpoint later than `seconds`, or the count when none is.
    private func firstCheckpoint(after seconds: Double) -> Int {
        var low = 0, high = checkpoints.count
        while low < high {
            let middle = (low + high) / 2
            if checkpoints[middle].seconds > seconds { high = middle } else { low = middle + 1 }
        }
        return low
    }

    private static func interpolate(_ from: Checkpoint, _ to: Checkpoint, at seconds: Double) -> Double {
        let span = to.seconds - from.seconds
        guard span > 0 else { return to.steps }
        return from.steps + (to.steps - from.steps) * (seconds - from.seconds) / span
    }
}
