import Foundation
import SwiftUI
import Testing
import UserNotifications
@testable import AscendApp

/// Guideline 5.1.1(iv): a custom message that appears before a system permission request must always
/// be followed by the request.
///
/// Apple rejected 1.3.0 (build 2026111701) on 2026-11-19 because onboarding's Health connect screen
/// carried a Skip. A message that can be closed without reaching the request is the defect, so every
/// screen in the app that explains a permission before iOS asks has one forward action, and the
/// climber's no is the iOS sheet's own Don't Allow. A new screen of this kind joins this suite.
@MainActor
@Suite(.hostsAWindow)
struct PrePermissionMessagesHaveNoWayOutTests {
    private func flow(at step: OnboardingV3Step) -> OnboardingV3FlowView {
        let defaults = UserDefaults(suiteName: "pre-permission-\(UUID().uuidString)")!
        return OnboardingV3FlowView(
            coordinator: OnboardingV3Coordinator(store: PreAuthOnboardingStore(userDefaults: defaults), startingAt: step)
        )
    }

    /// The words that would let a climber leave a permission message without the request.
    private static let wayOutLabels = ["skip", "not now", "maybe later", "no thanks", "close"]

    @Test(arguments: [OnboardingV3Step.healthConnect, .healthPermission, .notificationPrimer])
    func theOnboardingPermissionScreensDrawNoWayPastTheRequest(step: OnboardingV3Step) async throws {
        try await RenderedScreen.host(flow(at: step), settle: .turns(40)) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("back"), "Back leaves the earlier screens and stays: \(copy)")
            for label in Self.wayOutLabels {
                #expect(!copy.contains(label), "\(step) offers \(label): \(copy)")
            }
        }
    }

    @Test
    func theConnectScreenOpenedLaterDrawsNoWayOutUntilARequestHasFailed() async throws {
        try await RenderedScreen.host(AppleHealthConnectView(onConnect: {}), settle: .turns(40)) { screen in
            let copy = try await screen.copy { $0.contains("connect apple health") }
            for label in Self.wayOutLabels {
                #expect(!copy.contains(label), "offers \(label) before any request: \(copy)")
            }
        }
        try await RenderedScreen.host(
            AppleHealthConnectView(errorMessage: "Apple Health did not connect. Try again.", onConnect: {}, onClose: {}),
            settle: .turns(40)
        ) { screen in
            let copy = try await screen.copy { $0.contains("connect apple health") }
            #expect(copy.contains("close"), "a failed request earns the way out: \(copy)")
            #expect(copy.contains("not now"), "\(copy)")
        }
    }

    @Test(arguments: [OnboardingV3Step.healthConnect, .healthPermission, .notificationPrimer])
    func thePermissionStepsOfferNoSkipExit(step: OnboardingV3Step) {
        #expect(!step.alternateExits.contains { $0.analyticsAction == .skip })
        #expect(step.primaryDestination != nil, "the one forward action leads somewhere")
    }

    /// Declining in the iOS prompt must never leave the primer as a screen with nothing to press.
    @Test(arguments: [UNAuthorizationStatus.denied, .authorized])
    func theNotificationPrimerMovesOnForEveryAnswerIOSGives(status: UNAuthorizationStatus) async {
        let defaults = UserDefaults(suiteName: "pre-permission-\(UUID().uuidString)")!
        let coordinator = OnboardingV3Coordinator(
            store: PreAuthOnboardingStore(userDefaults: defaults),
            startingAt: .notificationPrimer
        )
        let model = NotificationPrimerViewModel(
            coordinator: coordinator,
            loadCatalog: { .empty },
            requestAuthorization: { status },
            track: { _ in }
        )

        await model.turnOn()

        #expect(coordinator.step == .auth)
    }
}
