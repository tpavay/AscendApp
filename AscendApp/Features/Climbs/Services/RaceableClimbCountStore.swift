import Foundation
import Observation

/// The raceable landmark count behind purchase-inducing copy.
///
/// It resolves from the hosted catalogue - the same manifest and catalogue file
/// the Superwall paywall reads - so the two surfaces cannot promise different
/// numbers in one session. Resolution is async and happens off the render path;
/// copy reads only the in-memory answer, and `nil` means the count is not known
/// yet, which the copy states without a number rather than guessing one.
@MainActor
@Observable
final class RaceableClimbCountStore {
    static let shared = RaceableClimbCountStore()

    private(set) var count: Int?

    private let climbService: ClimbService
    private var resolveTask: Task<Void, Never>?

    init(climbService: ClimbService = .shared) {
        self.climbService = climbService
    }

    func resolve() async {
        if let resolveTask {
            await resolveTask.value
            return
        }

        let task = Task { @MainActor [climbService] in
            // The hosted catalogue is the shared source. Offline, the device's
            // cached or bundled copy still answers rather than blanking the copy.
            _ = try? await climbService.refreshCatalogIfNeeded()
            let resolved = climbService.raceableClimbCount
            count = resolved > 0 ? resolved : nil
        }

        resolveTask = task
        await task.value
        resolveTask = nil
    }
}
