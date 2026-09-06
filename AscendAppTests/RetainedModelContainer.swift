import Foundation
import SwiftData

/// In-memory model containers for the suites that put a screen in a window.
///
/// A hosted screen that carries a `@Query` - Workout Detail, the completion summary, the share
/// composer, Home behind the tab bar - keeps observing SwiftData after its window is gone: SwiftUI
/// tears the view graph down on its own schedule, and the observer outlives a container that died
/// with the test that hosted it. The next `ModelContext.save()` anywhere in the process then wakes
/// that observer against a dangling context and traps (`EXC_BREAKPOINT` on the main thread,
/// SwiftData -> NotificationCenter -> _SwiftData_SwiftUI), charged to whatever unrelated suite
/// happened to be saving - and when Xcode's crash interception parks the trapped host instead of
/// letting it die, the whole run goes silent until the per-test allowance kills it. Every one-host
/// run of the suite before this file wedged or crashed exactly there.
///
/// So a container a hosted screen reads lives for the process. Each call still returns its own
/// fresh store, so no suite renders against another's fixtures; what is retained is a handful of
/// empty-on-exit in-memory stores, not the screens.
@MainActor
enum RetainedModelContainer {
    private static var retained: [ModelContainer] = []

    /// A fresh in-memory container over `models`, retained for the life of the test process.
    static func inMemory(for models: any PersistentModel.Type...) throws -> ModelContainer {
        try inMemory(schema: Schema(models))
    }

    /// A fresh in-memory container over `schema`, retained for the life of the test process.
    static func inMemory(schema: Schema) throws -> ModelContainer {
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        retained.append(container)
        return container
    }
}
