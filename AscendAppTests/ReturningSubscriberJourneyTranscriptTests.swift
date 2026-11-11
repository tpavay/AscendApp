import Foundation
import Testing
@testable import AscendApp

/// Journey evidence for `docs/quality/contracts/returning-subscriber.md`.
///
/// The captain's staging repro was a sequence, not a single state: an active subscriber signs out,
/// lands on the welcome screen, signs back in, and is shown the paywall. This walks that exact
/// sequence through the shipped `AuthenticationViewModel` and `MonetizationManager` and records the
/// route the user would land on at every step, so the transcript reads as the journey rather than as
/// an assertion list.
///
/// The decisive step is the one the bug lived in: the instant sign-in publishes an authenticated
/// state, the RevenueCat answer has not arrived yet. The route at that instant must be the wait, and
/// the app-access paywall must never be registered anywhere in the journey.
@MainActor
struct ReturningSubscriberJourneyTranscriptTests {
    @Test
    func aReturningSubscriberNeverSeesThePaywall() async throws {
        let entitlementService = EntitlementServiceStub(initialState: .active(["app_access"]))
        let paywallPresenter = PaywallPresenterSpy()
        let monetization = MonetizationManager(
            entitlementService: entitlementService,
            paywallPresenter: paywallPresenter
        )
        let authentication = AuthenticationViewModel(
            monetizationIdentityManager: monetization,
            observesFirebaseAuth: false
        )

        var transcript: [String] = []
        var routes: [AppRootRoute] = []

        func record(
            _ step: String,
            userId: String?,
            onboarding: PostAuthOnboardingPhase = .complete
        ) {
            let route = AppRootRouteResolver.resolve(
                updatePresentation: nil,
                authenticationState: authentication.authenticationState,
                userId: userId,
                postAuthOnboardingPhase: onboarding,
                entitlementState: monetization.entitlementStateForRouting,
                requiredEntitlementID: "app_access"
            )
            routes.append(route)

            // A paywall route is what actually registers the Superwall placement in `RootView`.
            if route == .paywall {
                monetization.presentPaywall(.appAccessGate, params: ["source": "app_access_gate"])
            }

            transcript.append(
                """
                \(step)
                  entitlement : \(monetization.entitlementStateForRouting)
                  route       : \(describe(route))
                  paywall     : \(paywallPresenter.registrations.isEmpty ? "not registered" : "REGISTERED")
                """
            )
        }

        // 1. The paying subscriber is in the app.
        authentication.authenticationState = .authenticated
        record("1. Active subscriber using the app", userId: "returning-subscriber")

        // 2. They sign out. This is the `Purchases.logOut()` half of the race.
        let signOut = monetization.prepareIdentityReset()
        await monetization.resetIdentity(transition: signOut)
        authentication.authenticationState = .unauthenticated
        record("2. Signs out -> welcome screen", userId: nil)

        // 3. They sign back in. The identity is claimed synchronously, the RevenueCat answer is not
        //    back yet, and routing is evaluated right here - the exact instant the bug fired.
        entitlementService.identityResolution = .active(["app_access"])
        authentication.beginAuthenticatedSession(
            customer: .climber("returning-subscriber"),
            initialState: .authenticated
        )
        record("3. Signs in -> answer still outstanding", userId: "returning-subscriber")

        // 4. The matching identify resolves.
        await Task.yield()
        try await waitForEntitlementResolution(of: monetization)
        record("4. RevenueCat answers: subscription active", userId: "returning-subscriber")

        #expect(routes == [.mainApp, .signedOut, .resolving, .mainApp])
        #expect(paywallPresenter.registrations.isEmpty, "The app-access paywall was registered")

        let rendered = """
            Returning subscriber journey - subscribe -> sign out -> sign in
            Required entitlement: app_access

            \(transcript.joined(separator: "\n\n"))

            Result: the app-access paywall was \
            \(paywallPresenter.registrations.isEmpty ? "never registered" : "REGISTERED")
            """

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        try rendered.write(
            to: URL(filePath: directory).appending(path: "returning-subscriber-journey.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// The onboarding walks a signed-out climber through the setup screens, then sign-in, and ends
    /// there. The paywall that may follow is the app-access gate, and which climbers meet it is
    /// decided by what RevenueCat says about the account that just signed in, never by the order of
    /// the screens.
    private func routesWalkingTheOnboarding(
        accountHolds identityResolution: MonetizationEntitlementState
    ) async throws -> [AppRootRoute] {
        let entitlementService = EntitlementServiceStub(initialState: .inactive)
        let monetization = MonetizationManager(
            entitlementService: entitlementService,
            paywallPresenter: PaywallPresenterSpy()
        )
        let authentication = AuthenticationViewModel(
            monetizationIdentityManager: monetization,
            observesFirebaseAuth: false
        )

        func route(userId: String?) -> AppRootRoute {
            AppRootRouteResolver.resolve(
                updatePresentation: nil,
                authenticationState: authentication.authenticationState,
                userId: userId,
                postAuthOnboardingPhase: .complete,
                entitlementState: monetization.entitlementStateForRouting,
                requiredEntitlementID: "app_access",
                showsPreAuthOnboardingV3: true
            )
        }

        var routes: [AppRootRoute] = []
        authentication.authenticationState = .unauthenticated
        routes.append(route(userId: nil))

        // Sign-in closes the flow; the entitlement answer is still outstanding.
        entitlementService.identityResolution = identityResolution
        authentication.beginAuthenticatedSession(
            customer: .climber("walker"),
            initialState: .authenticated
        )
        routes.append(route(userId: "walker"))

        await Task.yield()
        try await waitForEntitlementResolution(of: monetization)
        routes.append(route(userId: "walker"))
        return routes
    }

    @Test
    func anExistingSubscriberWhoWalksTheOnboardingSkipsThePaywall() async throws {
        let routes = try await routesWalkingTheOnboarding(accountHolds: .active(["app_access"]))

        #expect(routes == [.preAuthOnboarding, .resolving, .mainApp])
    }

    @Test
    func aLapsedSubscriberWhoWalksTheOnboardingMeetsTheAppAccessGateOnceTheAnswerIsIn() async throws {
        let routes = try await routesWalkingTheOnboarding(accountHolds: .inactive)

        #expect(routes == [.preAuthOnboarding, .resolving, .paywall])
    }

    /// Waits on the identity `Task` that `beginAuthenticatedSession` starts. This is polling for a
    /// completion the production code owns, not a delay that hides a race: the assertions above
    /// already pinned the pre-resolution route, and a resolution that never lands fails the test
    /// instead of passing late.
    private func waitForEntitlementResolution(
        of monetization: MonetizationManager
    ) async throws {
        for _ in 0..<1_000 {
            if monetization.entitlementStateForRouting != .unknown { return }
            await Task.yield()
        }

        Issue.record("The identity transition never resolved")
    }

    private func describe(_ route: AppRootRoute) -> String {
        switch route {
        case .updateRequired: "updateRequired (hard update lockout)"
        case .signedOut: "signedOut (welcome screen, with Already have an account? Sign in)"
        case .signedOutHold: "signedOutHold (wordmark, until the launch decides the signed-out route)"
        case .preAuthOnboarding: "preAuthOnboarding (v3 flow, signed out)"
        case .signingIn: "signingIn"
        case .restoringSession: "restoringSession"
        case .resolving: "resolving (the spinner, while access is worked out)"
        case .onboarding(let stage): "onboarding(\(stage))"
        case .paywall: "paywall (app-access gate)"
        case .mainApp: "mainApp"
        }
    }
}
