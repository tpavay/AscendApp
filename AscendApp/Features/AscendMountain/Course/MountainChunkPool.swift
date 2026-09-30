import Foundation

/// Which course piece each of a fixed set of render slots is showing (spec 9, 25).
///
/// The renderer owns exactly `slotCount` chunk entities for the life of the scene. As the
/// climber moves on, the slot holding the piece that fell out of the window behind is
/// reassigned to the piece entering the window ahead - reconfigured, never destroyed and
/// re-created - so a 60-minute climb allocates no more entities than its first second did.
struct MountainChunkPool: Equatable, Sendable {
    static let chunksBehind = 2
    /// Far enough ahead that the stairs and mountainside are built well before they can be seen.
    static let chunksAhead = 6
    static var windowSize: Int { chunksBehind + 1 + chunksAhead }

    /// How much of the course is built around the climber.
    struct Reach: Equatable, Sendable {
        let behind: Int
        let ahead: Int

        static let standard = Reach(behind: MountainChunkPool.chunksBehind, ahead: MountainChunkPool.chunksAhead)
        /// While the camera lifts over a gate: far enough both ways that the risen view sees the
        /// stairs wind on up the mountain and back down it, instead of stopping.
        static let lift = Reach(behind: 5, ahead: 18)

        var size: Int { behind + 1 + ahead }
    }

    struct Assignment: Equatable, Sendable {
        let slot: Int
        let chunkIndex: Int
    }

    /// The piece each slot shows, or `nil` while the slot has never been used.
    private(set) var slotChunkIndices: [Int?]
    /// How many times a slot has been handed a new piece, for the debug overlay.
    private(set) var recycleCount = 0

    init(slotCount: Int = MountainChunkPool.windowSize) {
        slotChunkIndices = Array(repeating: nil, count: max(slotCount, MountainChunkPool.windowSize))
    }

    var slotCount: Int { slotChunkIndices.count }

    var activeSlotCount: Int {
        slotChunkIndices.compactMap(\.self).count
    }

    /// Slots currently holding no piece, ready to be configured.
    var idleSlotCount: Int {
        slotCount - activeSlotCount
    }

    static func window(around currentChunk: Int, reach: Reach = .standard) -> ClosedRange<Int> {
        (currentChunk - reach.behind)...(currentChunk + reach.ahead)
    }

    /// Moves the window to `currentChunk` and returns only the slots whose piece changed, so the
    /// renderer touches nothing that is already in place. A pool with more slots than the reach
    /// needs keeps the rest for a wider reach, and a piece a wider reach built stays standing
    /// until its slot is wanted.
    mutating func update(currentChunk: Int, reach: Reach = .standard) -> [Assignment] {
        let window = Self.window(around: currentChunk, reach: reach)
        let kept = Set(slotChunkIndices.compactMap { index in
            index.flatMap { window.contains($0) ? $0 : nil }
        })
        let missing = window.filter { !kept.contains($0) }
        guard !missing.isEmpty else { return [] }

        // Oldest pieces are released first, so a slot always recycles the piece furthest behind;
        // a slot that has never held a piece is taken only once none is left to recycle.
        let reusableSlots = slotChunkIndices.indices
            .filter { slot in slotChunkIndices[slot].map { !window.contains($0) } ?? true }
            .sorted { lhs, rhs in
                (slotChunkIndices[lhs] ?? .max) < (slotChunkIndices[rhs] ?? .max)
            }

        var assignments: [Assignment] = []
        for (slot, chunkIndex) in zip(reusableSlots, missing) {
            if slotChunkIndices[slot] != nil {
                recycleCount += 1
            }
            slotChunkIndices[slot] = chunkIndex
            assignments.append(Assignment(slot: slot, chunkIndex: chunkIndex))
        }
        return assignments
    }
}
