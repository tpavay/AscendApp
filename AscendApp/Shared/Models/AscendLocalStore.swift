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

    /// The store shape the app writes today. A new `AscendSchemaV3` changes this one line, plus
    /// its stage in `AscendMigrationPlan`.
    static var currentSchema: any VersionedSchema.Type { AscendSchemaV2.self }

    static var models: [any PersistentModel.Type] { currentSchema.models }

    static var schema: Schema { Schema(versionedSchema: currentSchema) }

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
