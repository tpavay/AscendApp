import Foundation
import SwiftData
import Testing
@testable import AscendApp

@MainActor
struct AscendLocalStoreTests {

    @Test("Deletion order covers the whole live schema exactly once", .bug(id: 348))
    func deletionOrderCoversEveryModelExactlyOnce() {
        let ordered = AscendLocalStore.modelsInCascadeSafeDeletionOrder.map { String(describing: $0) }

        #expect(Set(ordered) == Set(AscendLocalStore.models.map { String(describing: $0) }))
        #expect(ordered.count == AscendLocalStore.models.count)
    }

    @Test("Deletes cascade children before the model that cascades to them", .bug(id: 348))
    func deletionOrderPutsCascadeChildrenBeforeTheirOwner() throws {
        let ordered = AscendLocalStore.modelsInCascadeSafeDeletionOrder.map { String(describing: $0) }

        // Derived from the schema, so this asserts the derivation actually resolved names rather
        // than silently producing schema order. `Workout` cascades to both.
        let workoutIndex = try #require(ordered.firstIndex(of: "Workout"))
        let participationIndex = try #require(ordered.firstIndex(of: "WorkoutParticipation"))
        let sourceLinkIndex = try #require(ordered.firstIndex(of: "WorkoutSourceLink"))

        #expect(participationIndex < workoutIndex)
        #expect(sourceLinkIndex < workoutIndex)
    }
}
