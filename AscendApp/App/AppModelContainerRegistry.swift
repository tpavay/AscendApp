import Foundation
import SwiftData

/// The one `ModelContainer` the app opened at launch, for code that runs before any view exists.
///
/// SwiftUI hands the container down the view tree, which is the right path for everything a
/// screen does. The HealthKit workout relaunch is the exception: iOS starts the process in the
/// background with no scene content, and the session has to be resumed from the draft before the
/// climber ever opens the app. That path reads the container from here.
@MainActor
final class AppModelContainerRegistry {
    static let shared = AppModelContainerRegistry()

    private(set) var container: ModelContainer?

    private init() {}

    func register(_ container: ModelContainer) {
        self.container = container
    }
}
