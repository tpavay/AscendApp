import Foundation

/// Chooses the endless sequence of course pieces from a seed (spec 14).
///
/// The same seed always yields the same climb, which is what lets a rebuilt scene, a ghost and
/// the climber all stand on one staircase. The sequence is not meant to be random; it is meant
/// to read as a believable mountain path:
///
/// - a break (landing or turn) is always followed by a flight, and at most two flights run
///   back to back before a break;
/// - turns keep the net heading within a quarter turn of the start, so the path zig-zags up
///   the mountain and can never curl back over itself - a left turn is always answered by a
///   right one before another left is allowed.
struct MountainCourseGenerator: Equatable, Sendable {
    let seed: UInt64

    /// Index of the next piece `next()` returns.
    private(set) var nextIndex = 0
    private var consecutiveFlights = 0
    /// Net quarter turns so far: +1 after an unanswered left, -1 after an unanswered right.
    private var netQuarterTurns = 0

    init(seed: UInt64) {
        self.seed = seed
    }

    mutating func next() -> MountainChunkKind {
        let index = nextIndex
        nextIndex += 1

        let kind = chooseKind(index: index)
        if kind.isFlight {
            consecutiveFlights += 1
        } else {
            consecutiveFlights = 0
        }
        switch kind {
        case .leftTurn:
            netQuarterTurns += 1
        case .rightTurn:
            netQuarterTurns -= 1
        case .shortFlight, .mediumFlight, .longFlight, .landing:
            break
        }
        return kind
    }

    private func chooseKind(index: Int) -> MountainChunkKind {
        // The climb opens on a flight so the first real step is visibly a stair.
        guard index > 0 else { return .mediumFlight }

        let roll = Self.unitRandom(seed: seed, index: index, salt: 0)
        let mustBreak = consecutiveFlights >= 2
        let mayBreak = consecutiveFlights >= 1

        if mayBreak && (mustBreak || roll < 0.55) {
            return chooseBreak(index: index)
        }
        return chooseFlight(index: index)
    }

    private func chooseFlight(index: Int) -> MountainChunkKind {
        let roll = Self.unitRandom(seed: seed, index: index, salt: 1)
        if roll < 0.35 { return .shortFlight }
        if roll < 0.75 { return .mediumFlight }
        return .longFlight
    }

    private func chooseBreak(index: Int) -> MountainChunkKind {
        let roll = Self.unitRandom(seed: seed, index: index, salt: 2)
        guard roll < 0.6 else { return .landing }

        switch netQuarterTurns {
        case 1...:
            return .rightTurn
        case ...(-1):
            return .leftTurn
        default:
            return Self.unitRandom(seed: seed, index: index, salt: 3) < 0.5 ? .leftTurn : .rightTurn
        }
    }

    /// A uniform value in `[0, 1)` that depends only on its inputs (SplitMix64).
    static func unitRandom(seed: UInt64, index: Int, salt: UInt64) -> Double {
        var state = seed &+ UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9_7F4A_7C15 &+ salt &* 0xD1B5_4A32_D192_ED03
        state = (state ^ (state >> 30)) &* 0xBF58_476D_1CE4_E5B9
        state = (state ^ (state >> 27)) &* 0x94D0_49BB_1331_11EB
        state ^= state >> 31
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}
