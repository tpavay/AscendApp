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

    @Test("Treats every model as a user record except the named derived caches", .bug(id: 348))
    func userRecordModelsAreTheLiveSchemaMinusTheNamedDerivedCaches() {
        let live = Set(AscendLocalStore.models.map { String(describing: $0) })
        let derivedCaches = Set(AscendLocalStore.derivedCacheModels.map { String(describing: $0) })
        let userRecords = Set(AscendLocalStore.userRecordModels.map { String(describing: $0) })

        #expect(derivedCaches.isSubset(of: live))
        #expect(userRecords == live.subtracting(derivedCaches))
    }

    @Test("Names only the Best Effort caches as recomputable", .bug(id: 348))
    func derivedCachesAreOnlyTheBestEffortCaches() {
        let derivedCaches = Set(AscendLocalStore.derivedCacheModels.map { String(describing: $0) })
        let userRecords = Set(AscendLocalStore.userRecordModels.map { String(describing: $0) })

        #expect(derivedCaches == ["BestEffortCacheEntry", "BestEffortCacheMetadata"])

        // An unfinished session is a record the climber made, not something Ascend can recompute,
        // so it stays on the side the ownership gate blocks on.
        #expect(userRecords.contains("ActiveHeadphoneWorkoutDraft"))
    }
}
