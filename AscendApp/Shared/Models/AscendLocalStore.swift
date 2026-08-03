//
//  AscendLocalStore.swift
//  AscendApp
//

import Foundation
import SwiftData

/// The single declaration of what Ascend persists on this device.
///
/// Everything that has to agree on the *whole* model set reads it from here: the `ModelContainer`,
/// account deletion's local sweep, and the sign-in ownership gate. Each of those used to keep its
/// own hand-written list of types, and the lists drifted apart - deletion missed four models that
/// were in the container, so one climber's attempts, cached Best Efforts and in-progress session
/// survived "delete my account" and the next climber to sign in on the device published them as
/// their own (#348).
///
/// Adding a model to the live schema is now all it takes to have it swept and counted.
enum AscendLocalStore {

    /// The store shape the app writes today. A new `AscendSchemaV4` changes this one line, plus
    /// its stage in `AscendMigrationPlan`.
    static var currentSchema: any VersionedSchema.Type { AscendSchemaV3.self }

    static var models: [any PersistentModel.Type] { currentSchema.models }

    static var schema: Schema { Schema(versionedSchema: currentSchema) }

    /// The models that hold nothing anyone entered or earned - rows Ascend recomputes from the
    /// workouts it already has.
    ///
    /// Only the sign-in ownership gate reads this. Deletion never does: "delete my account" means
    /// the store is empty, cache included.
    ///
    /// The exclusion exists because counting a recomputable row as somebody's data turns the
    /// safety mechanism into its own incident. `BestEffortCacheStore.rebuildIfNeeded` writes a
    /// `BestEffortCacheMetadata` row the first time anyone reaches the main tab, before they have
    /// logged anything, so a gate that counted it would send every legitimate account switch on a
    /// shared device to `AccountDataConflictView`, whose only way out is signing out again.
    static var derivedCacheModels: [any PersistentModel.Type] {
        [
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self
        ]
    }

    /// The models that hold real user records: the live schema minus the caches named above.
    ///
    /// Subtraction, not a list of what counts. A model added later is somebody's data until
    /// someone deliberately calls it recomputable - the opposite of the hand-written include-list
    /// that let four models fall out of the gate (#348). An unfinished session is a user record.
    static var userRecordModels: [any PersistentModel.Type] {
        let derivedCacheNames = Set(derivedCacheModels.map { String(describing: $0) })
        return models.filter { !derivedCacheNames.contains(String(describing: $0)) }
    }

    /// The same models, ordered so a cascade child is always deleted before the model that
    /// cascades to it.
    ///
    /// A staged sweep that deletes the owner first lets SwiftData cascade to children the context
    /// never materialised, and `ModelContext.rollback()` then traps trying to snapshot them:
    /// `Unexpected backing data for snapshot creation: _FullFutureBackingData<...>`. Deleting a
    /// `Workout` ahead of its `WorkoutParticipation`s is enough to do it, and that is every Live
    /// Climb and every routine session - so an account deletion that had to roll back would take
    /// the app down with it instead.
    ///
    /// Derived from the schema's own cascade rules rather than written down, so a model added
    /// later is placed correctly without anyone remembering this exists.
    static var modelsInCascadeSafeDeletionOrder: [any PersistentModel.Type] {
        let models = models
        let modelsByName = Dictionary(
            models.map { (String(describing: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let cascadeChildrenByOwnerName = cascadeChildrenByOwnerName()

        var pending = models.map { String(describing: $0) }
        var deleted: Set<String> = []
        var ordered: [String] = []

        while !pending.isEmpty {
            let ready = pending.filter { name in
                (cascadeChildrenByOwnerName[name] ?? []).allSatisfy { child in
                    deleted.contains(child) || modelsByName[child] == nil
                }
            }

            // Only reachable through a cascade cycle, which the store shape cannot currently
            // form. Emitting the remainder in schema order keeps the sweep total: an ordering
            // this cannot solve must still delete everything.
            guard !ready.isEmpty else {
                ordered.append(contentsOf: pending)
                break
            }

            ordered.append(contentsOf: ready)
            deleted.formUnion(ready)
            pending.removeAll { ready.contains($0) }
        }

        return ordered.compactMap { modelsByName[$0] }
    }

    private static func cascadeChildrenByOwnerName() -> [String: Set<String>] {
        var childrenByOwnerName: [String: Set<String>] = [:]

        for entity in schema.entities {
            for relationship in entity.relationshipsByName.values
            where relationship.deleteRule == .cascade && relationship.destination != entity.name {
                childrenByOwnerName[entity.name, default: []].insert(relationship.destination)
            }
        }

        return childrenByOwnerName
    }
}
