import Foundation

/// One course piece placed on the mountain: which piece it is, which real steps cross it, and
/// where it starts in course space.
struct MountainChunkPlacement: Equatable, Sendable {
    let index: Int
    let kind: MountainChunkKind
    /// Steps climbed before this piece begins.
    let firstStep: Int
    let entry: MountainPose
    let entryAltitude: Double

    var stepCount: Int { kind.stepCount }

    /// The first step that belongs to the next piece.
    var endStep: Int { firstStep + stepCount }

    var exit: MountainPose {
        entry.composed(with: kind.exitPose)
    }

    var exitAltitude: Double {
        entryAltitude + kind.altitudeGain(atProgress: Double(stepCount))
    }

    func contains(step: Int) -> Bool {
        step >= firstStep && step < endStep
    }
}

/// Where a climber conceptually is on the course for a given step count (spec 31).
///
/// The live climber and, later, every ghost and pacer resolve through this one model, so the
/// distance drawn between two athletes is exactly the difference in their steps.
struct MountainCourseProgress: Equatable, Sendable {
    let totalSteps: Double
    /// Metres climbed: the stair rise of every flight step, never the flat ground of a landing.
    let virtualAltitude: Double
    let chunkIndex: Int
    /// How far across the current piece, in `0..<1`.
    let progressWithinChunk: Double
    let pose: MountainPose
}

/// The endless course for one seed, generated forward on demand.
///
/// Only a sliding window of placements is held, so memory stays flat however far the climb
/// goes; asking for a step behind the window regenerates from the start, which only a
/// downward step correction or a rebuilt scene ever does. Steps below zero resolve onto a
/// straight lead-in flight below the start, so the staircase already runs down behind the
/// climber before their first step.
struct MountainCourse: Sendable {
    /// Ascend Mountain is one mountain: every climber, and later every ghost, climbs the same
    /// staircase, so the seed is fixed rather than drawn per session.
    static let ascendMountainSeed: UInt64 = 0xA5CE_4D00_2026_0927

    static let leadInKind = MountainChunkKind.mediumFlight
    /// Placements kept behind the most recently resolved one.
    static let retainedPlacementsBehind = 32

    let seed: UInt64
    private var generator: MountainCourseGenerator
    private var placements: [MountainChunkPlacement] = []

    init(seed: UInt64) {
        self.seed = seed
        self.generator = MountainCourseGenerator(seed: seed)
    }

    /// Number of placements currently held, for the debug overlay and the memory tests.
    var retainedPlacementCount: Int { placements.count }

    mutating func placement(at index: Int) -> MountainChunkPlacement {
        guard index >= 0 else { return Self.leadInPlacement(at: index) }

        if let first = placements.first, index < first.index {
            rewind()
        }
        extend { $0.index >= index }

        return placements[index - placements[0].index]
    }

    mutating func placement(containingStep step: Int) -> MountainChunkPlacement {
        guard step >= 0 else {
            let leadInSteps = Self.leadInKind.stepCount
            return Self.leadInPlacement(at: -((-step - 1) / leadInSteps) - 1)
        }

        if let first = placements.first, step < first.firstStep {
            rewind()
        }
        extend { $0.endStep > step }

        let position = searchPosition(containingStep: step)
        let placement = placements[position]
        trim(keepingFrom: placement.index - Self.retainedPlacementsBehind)
        return placement
    }

    /// Where a marker for `step` stands. A gate cannot stand across a turn, where the path bends
    /// beneath it, so a step inside a turn stands at the turn's exit: the first straight stair,
    /// never before the climber's count has reached the number it shows.
    mutating func markerStep(for step: Int) -> Int {
        let placement = placement(containingStep: step)
        switch placement.kind {
        case .leftTurn, .rightTurn:
            return step == placement.firstStep ? step : placement.endStep
        default:
            return step
        }
    }

    mutating func progress(atSteps steps: Double) -> MountainCourseProgress {
        let safeSteps = steps.isFinite ? steps : 0
        let wholeStep = Int(safeSteps.rounded(.down))
        let placement = placement(containingStep: wholeStep)
        let local = safeSteps - Double(placement.firstStep)

        return MountainCourseProgress(
            totalSteps: safeSteps,
            virtualAltitude: placement.entryAltitude + placement.kind.altitudeGain(atProgress: local),
            chunkIndex: placement.index,
            progressWithinChunk: local / Double(placement.stepCount),
            pose: placement.entry.composed(with: placement.kind.localPose(atProgress: local))
        )
    }

    private mutating func rewind() {
        generator = MountainCourseGenerator(seed: seed)
        placements.removeAll(keepingCapacity: true)
    }

    /// Generates forward until `isSatisfied` holds for the newest placement.
    private mutating func extend(until isSatisfied: (MountainChunkPlacement) -> Bool) {
        if placements.isEmpty {
            placements.append(
                MountainChunkPlacement(
                    index: 0,
                    kind: generator.next(),
                    firstStep: 0,
                    entry: .origin,
                    entryAltitude: 0
                )
            )
        }

        while let last = placements.last, !isSatisfied(last) {
            placements.append(
                MountainChunkPlacement(
                    index: last.index + 1,
                    kind: generator.next(),
                    firstStep: last.endStep,
                    entry: last.exit,
                    entryAltitude: last.exitAltitude
                )
            )
            // A long seek (a rebuilt scene deep into a climb) must not hold every piece it passed.
            if placements.count > Self.retainedPlacementsBehind * 8 {
                trim(keepingFrom: placements[placements.count - 1].index - Self.retainedPlacementsBehind)
            }
        }
    }

    private mutating func trim(keepingFrom index: Int) {
        guard let first = placements.first, index > first.index else { return }
        placements.removeFirst(min(index - first.index, placements.count - 1))
    }

    private func searchPosition(containingStep step: Int) -> Int {
        var low = 0
        var high = placements.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if placements[middle].firstStep <= step {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    /// The straight flights below the start, each ending where the next begins.
    private static func leadInPlacement(at index: Int) -> MountainChunkPlacement {
        let kind = leadInKind
        let flightsBelow = Double(-index)
        let rise = Double(kind.stepCount) * MountainStairGeometry.rise
        let run = Double(kind.stepCount) * MountainStairGeometry.run

        return MountainChunkPlacement(
            index: index,
            kind: kind,
            firstStep: index * kind.stepCount,
            entry: MountainPose(position: SIMD3(0, -rise * flightsBelow, run * flightsBelow), heading: 0),
            entryAltitude: -rise * flightsBelow
        )
    }
}
