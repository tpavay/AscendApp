import Foundation
import Testing
import UserNotifications
@testable import AscendApp

/// Guideline 5.1.1(iv): a custom message that appears before a system permission request must always
/// be followed by the request.
///
/// Apple rejected 1.3.0 (build 2026111701) on 2026-11-19 because onboarding's Health connect screen
/// carried a Skip. A message that can be closed without reaching the request is the defect, so every
/// screen in the app that explains a permission before iOS asks has one forward action, and the
/// climber's no is the iOS sheet's own Don't Allow. A new screen of this kind joins `messages` below.
struct PrePermissionMessagesHaveNoWayOutTests {
    /// Every screen that explains a system permission before asking, and the words that would let a
    /// climber close it without the request.
    private static let messages: [(name: String, path: String)] = [
        ("Health connect, onboarding 06", "AscendApp/Features/Onboarding/V3/Health/OnboardingHealthConnectScreen.swift"),
        ("Health sheet picture, onboarding 06b", "AscendApp/Features/Onboarding/V3/Health/OnboardingHealthPermissionScreen.swift"),
        ("Notification primer, onboarding 12", "AscendApp/Features/Onboarding/V3/Notifications/OnboardingNotificationPrimerScreen.swift"),
        ("Notification primer's view model", "AscendApp/Features/Onboarding/V3/Notifications/NotificationPrimerViewModel.swift"),
        ("Health connect, Climb sheet and Settings", "AscendApp/Features/Integrations/AppleHealth/Views/AppleHealthConnectView.swift")
    ]

    private static let wayOutWords = [
        "\"Skip\"", "\"Not now\"", "\"Not Now\"", "\"NOT NOW\"", "\"Maybe later\"", "\"No thanks\"",
        "onSkip:", "declineHealth", "func notNow"
    ]

    @Test
    func noPermissionMessageNamesAWayPastTheRequest() throws {
        for message in Self.messages {
            let text = try source(at: message.path)
            // The connect view draws "Not now" only after a failed request, through `offersExit`.
            let allowed = message.path.hasSuffix("AppleHealthConnectView.swift") ? ["\"Not now\""] : []
            for word in Self.wayOutWords where text.contains(word) && !allowed.contains(word) {
                Issue.record("\(message.name) offers \(word), a way past the iOS request")
            }
        }
    }

    @Test
    func theConnectViewDrawsItsOnlyExitAfterAFailedRequest() throws {
        let text = try source(at: "AscendApp/Features/Integrations/AppleHealth/Views/AppleHealthConnectView.swift")

        #expect(text.contains("private var offersExit: Bool { chrome == .closeButton && errorMessage != nil }"))
        #expect(text.contains("secondaryTitle: offersExit ? \"Not now\" : nil"))
        #expect(text.contains("isShown: offersExit)"))
        let code = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        #expect(code.filter { $0.contains("\"Not now\"") }.count == 1, "Not now is drawn in one place, behind offersExit")
    }

    @Test(arguments: [OnboardingV3Step.healthConnect, .healthPermission, .notificationPrimer])
    func thePermissionStepsOfferNoSkipExit(step: OnboardingV3Step) {
        #expect(!step.alternateExits.contains { $0.analyticsAction == .skip })
        #expect(step.primaryDestination != nil, "the one forward action leads somewhere")
    }

    /// The header's Skip is drawn only when a screen hands it an `onSkip`; none of the permission
    /// screens may, and each keeps the header's Back, which leaves earlier screens and not the request.
    @Test
    func thePermissionScreensHeadersCarryBackAndNoSkip() throws {
        let screens = [
            ("AscendApp/Features/Onboarding/V3/Health/OnboardingHealthPermissionScreen.swift", "OnboardingProgressHeader(step: .healthPermission)"),
            ("AscendApp/Features/Onboarding/V3/Notifications/OnboardingNotificationPrimerScreen.swift", "OnboardingProgressHeader(step: .notificationPrimer)"),
            ("AscendApp/Features/Integrations/AppleHealth/Views/AppleHealthConnectView.swift", "OnboardingProgressHeader(step: .healthConnect)")
        ]
        for (path, header) in screens {
            let text = try source(at: path)
            #expect(text.contains(header), "\(path) draws the header with Back and no Skip")
        }
    }

    /// Declining in the iOS sheet, or a request that cannot be made, must never leave 06b or the
    /// primer as a screen with nothing to press: both move the climber on whatever the answer is.
    @MainActor
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

    private var projectRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(at relativePath: String) throws -> String {
        try String(contentsOf: projectRoot.appending(path: relativePath), encoding: .utf8)
    }
}
