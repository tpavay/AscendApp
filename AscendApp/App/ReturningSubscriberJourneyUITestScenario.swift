#if DEBUG
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ReturningSubscriberJourneyProbe {
    private(set) var paywallRegistrationCount = 0

    func recordPaywallRegistration() {
        paywallRegistrationCount += 1
    }
}

@MainActor
enum ReturningSubscriberJourneyUITestScenario {
    struct Configuration {
        let authenticationViewModel: AuthenticationViewModel
        let monetizationManager: MonetizationManager
        let modelContainer: ModelContainer
        let probe: ReturningSubscriberJourneyProbe
    }

    private static let launchArgument = "-uiTestReturningSubscriberJourney"
    private static let userID = "returning-subscriber-ui-test"
    private static let displayName = "Returning Climber"
    private static let workoutName = "Returning Subscriber Workout"

    static func makeIfRequested() -> Configuration? {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else {
            return nil
        }

        guard let modelContainer = try? AscendApp.makeModelContainer(
            isStoredInMemoryOnly: true
        ) else {
            return nil
        }

        let user = AuthenticatedUser(
            uid: userID,
            email: "returning-subscriber@example.com",
            photoURL: nil,
            creationDate: Date(timeIntervalSince1970: 1_704_067_200)
        )
        let authenticationStateObserver = ReturningSubscriberAuthenticationStateObserver(
            currentUser: user
        )
        let authenticationClient = ReturningSubscriberAuthenticationClient(
            stateObserver: authenticationStateObserver,
            user: user
        )
        let profileSessionProvider = ReturningSubscriberProfileSessionProvider(
            displayName: displayName
        )
        let entitlementService = ReturningSubscriberEntitlementService()
        let probe = ReturningSubscriberJourneyProbe()
        let paywallPresenter = ReturningSubscriberPaywallPresenter(probe: probe)
        let monetizationManager = MonetizationManager(
            configuration: MonetizationConfiguration(
                infoDictionary: [
                    MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
                ]
            ),
            entitlementService: entitlementService,
            paywallPresenter: paywallPresenter
        )
        monetizationManager.setDebugForcesAppAccessPaywall(false)

        PostAuthOnboardingStore().reset(for: userID)
        PostAuthOnboardingStore().markComplete(for: userID)
        AccountSessionStore.shared.recordLocalDataOwner(userId: userID)
        seedWorkout(in: modelContainer)

        let authenticationViewModel = AuthenticationViewModel(
            monetizationIdentityManager: monetizationManager,
            authenticationClient: authenticationClient,
            authenticationStateObserver: authenticationStateObserver,
            profileSessionProvider: profileSessionProvider
        )

        return Configuration(
            authenticationViewModel: authenticationViewModel,
            monetizationManager: monetizationManager,
            modelContainer: modelContainer,
            probe: probe
        )
    }

    private static func seedWorkout(in modelContainer: ModelContainer) {
        let workout = Workout(
            name: workoutName,
            date: Date(timeIntervalSince1970: 1_735_689_600),
            duration: 1_800,
            steps: 2_500,
            floors: 167
        )
        workout.markPendingRemoteUpsert(ownerUserId: userID)
        workout.markRemoteSyncSucceeded(
            syncedAt: Date(timeIntervalSince1970: 1_735_689_600),
            heartRateSeries: nil
        )
        modelContainer.mainContext.insert(workout)
        try? modelContainer.mainContext.save()
    }
}

@MainActor
private final class ReturningSubscriberAuthenticationStateObserver: AuthenticationStateObserving {
    private(set) var currentUser: AuthenticatedUser?
    private var listener: (@MainActor (AuthenticatedUser?) -> Void)?

    init(currentUser: AuthenticatedUser) {
        self.currentUser = currentUser
    }

    func observe(
        _ listener: @escaping @MainActor (AuthenticatedUser?) -> Void
    ) -> AuthenticationStateObservation {
        self.listener = listener
        listener(currentUser)
        return AuthenticationStateObservation {}
    }

    func publish(_ user: AuthenticatedUser?) {
        currentUser = user
        listener?(user)
    }
}

@MainActor
private final class ReturningSubscriberAuthenticationClient: AuthenticationClient {
    private let stateObserver: ReturningSubscriberAuthenticationStateObserver
    private let user: AuthenticatedUser

    init(
        stateObserver: ReturningSubscriberAuthenticationStateObserver,
        user: AuthenticatedUser
    ) {
        self.stateObserver = stateObserver
        self.user = user
    }

    func signInWithGoogle() async throws {
        stateObserver.publish(user)
    }

    func signInWithEmail(email: String, password: String) async throws {
        stateObserver.publish(user)
    }

    func signInWithApple() async throws {
        stateObserver.publish(user)
    }

    func signOut() throws {
        stateObserver.publish(nil)
    }

    func updateUserDisplayName(displayName: String) async throws {}
}

@MainActor
private final class ReturningSubscriberProfileSessionProvider: AuthenticationProfileSessionProviding {
    private let remoteDisplayName: String
    private var localDisplayName: String?

    init(displayName: String) {
        remoteDisplayName = displayName
        localDisplayName = displayName
    }

    func cachedDisplayName() -> String? {
        localDisplayName
    }

    func cachedProfilePictureURL() -> String? {
        nil
    }

    func clearCache() {
        localDisplayName = nil
    }

    func saveInitialUser(_ user: AuthenticatedUser) async throws {}

    func displayName(userID: String) async -> String? {
        localDisplayName = remoteDisplayName
        return remoteDisplayName
    }

    func profilePictureURL(userID: String) async -> String? {
        nil
    }
}

@MainActor
@Observable
private final class ReturningSubscriberEntitlementService: EntitlementServicing {
    private(set) var entitlementState: MonetizationEntitlementState = .active(["app_access"])
    let isConfigured = true
    private var revision: UInt = 0
    private var currentTransition: MonetizationIdentityTransition?

    func configure(configuration: MonetizationConfiguration) {}

    func refreshCustomerInfo() async {}

    func prepareIdentity(userId: String) -> MonetizationIdentityTransition {
        prepare(userID: userId)
    }

    func identify(
        userId: String,
        transition: MonetizationIdentityTransition
    ) async {
        guard transition == currentTransition,
              transition.userID == userId else {
            return
        }
        entitlementState = .active(["app_access"])
    }

    func prepareIdentityReset() -> MonetizationIdentityTransition {
        prepare(userID: nil)
    }

    func resetIdentity(transition: MonetizationIdentityTransition) async {
        guard transition == currentTransition,
              transition.userID == nil else {
            return
        }
        entitlementState = .inactive
    }

    func restorePurchases() async throws {}

    private func prepare(userID: String?) -> MonetizationIdentityTransition {
        revision &+= 1
        entitlementState = .unknown
        let transition = MonetizationIdentityTransition(
            revision: revision,
            userID: userID
        )
        currentTransition = transition
        return transition
    }
}

@MainActor
private final class ReturningSubscriberPaywallPresenter: PaywallPresenting {
    let isConfigured = true
    private let probe: ReturningSubscriberJourneyProbe

    init(probe: ReturningSubscriberJourneyProbe) {
        self.probe = probe
    }

    func configure(configuration: MonetizationConfiguration) {}

    func identify(userId: String) {}

    func resetIdentity() {}

    func register(
        placement: SuperwallPlacement,
        params: [String: Any]?,
        onOutcome: @escaping @MainActor (PaywallPresentationOutcome) -> Void
    ) {
        probe.recordPaywallRegistration()
        onOutcome(.presented)
    }
}
#endif
