//
//  PersistentModel+LocalStore.swift
//  AscendApp
//

import Foundation
import SwiftData

/// Whole-type store operations a caller can drive from `any PersistentModel.Type`.
///
/// `AscendLocalStore.models` is a list of existential metatypes, so a caller cannot write
/// `FetchDescriptor<Model>` against an element of it directly. A static member binds `Self` per
/// element, which is what lets a sweep iterate the live schema instead of naming types by hand.
extension PersistentModel {

    /// Deletes every stored instance of this type without saving.
    ///
    /// Staged rather than committed: `ModelContext.delete(model:)` is shorter but writes
    /// immediately, and account deletion has to roll the whole sweep back if the auth account
    /// refuses to go away.
    static func stageDeletionOfAll(in context: ModelContext) throws {
        for instance in try context.fetch(FetchDescriptor<Self>()) {
            context.delete(instance)
        }
    }

    static func storedCount(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Self>())
    }
}
