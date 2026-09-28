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

    static func window(around currentChunk: Int) -> ClosedRange<Int> {
        (currentChunk - chunksBehind)...(currentChunk + chunksAhead)
    }

    /// Moves the window to `currentChunk` and returns only the slots whose piece changed, so the
    /// renderer touches nothing that is already in place.
    mutating func update(currentChunk: Int) -> [Assignment] {
        let window = Self.window(around: currentChunk)
        let kept = Set(slotChunkIndices.compactMap { index in
            index.flatMap { window.contains($0) ? $0 : nil }
        })
        let missing = window.filter { !kept.contains($0) }
        guard !missing.isEmpty else { return [] }

        // Oldest pieces are released first, so a slot always recycles the piece furthest behind.
        let reusableSlots = slotChunkIndices.indices
            .filter { slot in slotChunkIndices[slot].map { !window.contains($0) } ?? true }
            .sorted { lhs, rhs in
                (slotChunkIndices[lhs] ?? .min) < (slotChunkIndices[rhs] ?? .min)
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
