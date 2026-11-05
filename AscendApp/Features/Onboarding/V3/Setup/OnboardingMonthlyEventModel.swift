import Foundation
import Observation

/// Where screen 11 gets its event: the hosted unlock catalogue the in-app event page reads, so the
/// screen changes by itself each month with no app update.
///
/// Onboarding runs signed out on a fresh install, so the catalogue is fetched when the flow opens
/// (Hosting needs no sign-in) and the screen starts from the cached or bundled copy, which a slow
/// or failed fetch simply leaves in place. The landmark catalogue loads the same way for the
/// neutral version's count and photograph.
@MainActor
@Observable
final class OnboardingMonthlyEventModel {
    static let shared = OnboardingMonthlyEventModel()

    private(set) var catalog: UnlockCatalog
    private(set) var landmarks: ClimbCatalogSnapshot?

    @ObservationIgnored private let unlockRepository: any UnlockCatalogRepository
    @ObservationIgnored private let climbRepository: any ClimbCatalogRepository
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?

    init(
        unlockRepository: any UnlockCatalogRepository = HostedUnlockCatalogRepository(),
        climbRepository: any ClimbCatalogRepository = HostedClimbCatalogRepository()
    ) {
        self.unlockRepository = unlockRepository
        self.climbRepository = climbRepository
        catalog = unlockRepository.loadInitialCatalog()
        landmarks = try? climbRepository.loadInitialCatalog()
    }

    /// What screen 11 shows at `now`.
    func presentation(now: Date = .now, calendar: Calendar = .current) -> OnboardingMonthlyEvent {
        OnboardingMonthlyEvent.resolve(catalog: catalog, now: now, calendar: calendar)
    }

    /// How many real landmarks a climber can pick from, for the neutral version. Nil until the
    /// landmark catalogue has answered, and the copy then drops the number rather than guess it.
    var availableLandmarkCount: Int? {
        landmarks.map { $0.availableClimbs.count }.flatMap { $0 > 0 ? $0 : nil }
    }

    /// The landmark whose photograph tops the screen: the catalogue's featured climb when it is
    /// open to climb, else its first open one.
    var heroLandmark: Climb? {
        guard let landmarks else { return nil }
        let available = landmarks.availableClimbs
        return available.first { $0.id == landmarks.featuredClimbId } ?? available.first
    }

    /// Starts both refreshes once. Calling it again, from every setup screen and from the flow's
    /// first screen, costs nothing.
    func prefetch() {
        guard prefetchTask == nil else { return }

        prefetchTask = Task { [unlockRepository, climbRepository] in
            async let freshCatalog = try? unlockRepository.refreshCatalog()
            async let freshLandmarks = try? climbRepository.refreshCatalog()
            let (catalog, landmarks) = await (freshCatalog, freshLandmarks)

            if let catalog { self.catalog = catalog }
            if let landmarks { self.landmarks = landmarks }
        }
    }
}
