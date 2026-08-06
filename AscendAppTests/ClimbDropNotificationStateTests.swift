import SwiftUI
import Testing
import UIKit
import UserNotifications
@testable import AscendApp

@MainActor
struct ClimbDropNotificationStateTests {
    @Test("Enabled notifications suppress prompts on the first render", .bug(id: 397))
    func enabledSuppressesPromptBeforeAndAfterAuthorizationRefresh() async {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .authorized,
            isPreferenceEnabled: true
        )
        let state = ClimbDropNotificationState(client: client, observesPreferenceChanges: false)

        #expect(state.shouldPromptForEnablement == false)

        await state.refresh()

        #expect(state.isEnabled)
        #expect(state.shouldPromptForEnablement == false)
    }

    @Test("Denied notifications keep prompts visible", .bug(id: 397))
    func deniedShowsPrompt() async {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .denied,
            isPreferenceEnabled: false
        )
        let state = ClimbDropNotificationState(client: client, observesPreferenceChanges: false)

        await state.refresh()

        #expect(state.isEnabled == false)
        #expect(state.shouldPromptForEnablement)
    }

    @Test("Notifications that have not been requested keep prompts visible", .bug(id: 397))
    func notDeterminedShowsPrompt() async {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .notDetermined,
            isPreferenceEnabled: false
        )
        let state = ClimbDropNotificationState(client: client, observesPreferenceChanges: false)

        await state.refresh()

        #expect(state.isEnabled == false)
        #expect(state.shouldPromptForEnablement)
    }

    @Test("An off climb-drop preference keeps prompts visible even with iOS permission", .bug(id: 397))
    func disabledPreferenceShowsPrompt() async {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .authorized,
            isPreferenceEnabled: false
        )
        let state = ClimbDropNotificationState(client: client, observesPreferenceChanges: false)

        await state.refresh()

        #expect(state.isEnabled == false)
        #expect(state.shouldPromptForEnablement)
    }

    @Test("Granting permission updates shared state without a relaunch", .bug(id: 397))
    func notDeterminedTransitionsToEnabled() async {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .notDetermined,
            isPreferenceEnabled: false
        )
        let state = ClimbDropNotificationState(client: client, observesPreferenceChanges: false)
        await state.refresh()
        #expect(state.shouldPromptForEnablement)

        let result = await state.enable()

        #expect(result == .authorized)
        #expect(state.authorizationStatus == .authorized)
        #expect(state.isPreferenceEnabled)
        #expect(state.isEnabled)
        #expect(state.shouldPromptForEnablement == false)
    }
}

@MainActor
@Suite(.hostsAWindow)
struct ClimbDropNotificationPromptHostingTests {
    @Test("Both notification prompts disappear live after permission is granted", .bug(id: 397))
    func bothPromptsFollowTheSharedStateTransition() async throws {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .notDetermined,
            isPreferenceEnabled: false
        )
        let state = ClimbDropNotificationState(client: client, observesPreferenceChanges: false)
        await state.refresh()

        let host = try await hostPromptSurfaces(notificationState: state)
        defer { host.window.isHidden = true }

        #expect(notificationPromptCount(in: host.controller.view) == 2)

        await state.enable()
        await renderNextUpdate(in: host.controller.view)

        #expect(notificationPromptCount(in: host.controller.view) == 0)
    }

    @Test("Both notification prompts stay hidden on an enabled first render", .bug(id: 397))
    func bothPromptsAreHiddenOnEnabledFirstRender() async throws {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .authorized,
            isPreferenceEnabled: true
        )
        let state = ClimbDropNotificationState(client: client, observesPreferenceChanges: false)

        let host = try await hostPromptSurfaces(notificationState: state)
        defer { host.window.isHidden = true }

        #expect(notificationPromptCount(in: host.controller.view) == 0)
    }

    @Test("Both notification prompts remain visible when permission is denied", .bug(id: 397))
    func bothPromptsRemainVisibleWhenDenied() async throws {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .denied,
            isPreferenceEnabled: false
        )
        let state = ClimbDropNotificationState(client: client, observesPreferenceChanges: false)
        await state.refresh()

        let host = try await hostPromptSurfaces(notificationState: state)
        defer { host.window.isHidden = true }

        #expect(notificationPromptCount(in: host.controller.view) == 2)
    }

    private func hostPromptSurfaces(
        notificationState: ClimbDropNotificationState
    ) async throws -> (window: UIWindow, controller: UIHostingController<NotificationPromptSurfaceHarness>) {
        setAccessibilityAutomationEnabled(true)

        let size = CGSize(width: 402, height: 874)
        let controller = UIHostingController(
            rootView: NotificationPromptSurfaceHarness(notificationState: notificationState)
        )
        controller.view.frame = CGRect(origin: .zero, size: size)

        let window = UIWindow(frame: controller.view.frame)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        window.makeKeyAndVisible()

        await renderNextUpdate(in: controller.view)
        return (window, controller)
    }

    private func renderNextUpdate(in view: UIView) async {
        for _ in 0..<4 {
            await Task.yield()
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    private func notificationPromptCount(in root: UIView) -> Int {
        accessibilityElements(under: root).count {
            $0.accessibilityLabel == "Turn on notifications"
        }
    }

    private func setAccessibilityAutomationEnabled(_ isEnabled: Bool) {
        typealias SetAutomationEnabled = @convention(c) (Bool) -> Void

        guard
            let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
            let symbol = dlsym(library, "_AXSSetAutomationEnabled")
        else {
            Issue.record("The accessibility runtime could not be started")
            return
        }

        unsafeBitCast(symbol, to: SetAutomationEnabled.self)(isEnabled)
    }

    private func accessibilityElements(under root: UIView) -> [NSObject] {
        var found: [NSObject] = []

        func visit(_ node: NSObject) {
            let count = node.accessibilityElementCount()
            if count != NSNotFound {
                for index in 0..<count {
                    guard let child = node.accessibilityElement(at: index) as? NSObject else {
                        continue
                    }

                    found.append(child)
                    visit(child)
                }
            }

            if let view = node as? UIView {
                for subview in view.subviews {
                    visit(subview)
                }
            }
        }

        visit(root)
        return found
    }
}

private struct NotificationPromptSurfaceHarness: View {
    let notificationState: ClimbDropNotificationState

    var body: some View {
        VStack(spacing: 24) {
            PrestigeSection(
                held: [],
                open: [],
                achievements: .zero,
                achievementRecords: [],
                mode: .own,
                notificationState: notificationState
            )

            ClimbsCollectionView(
                collection: ProfileCollectionSummary(
                    collectedCount: 0,
                    catalogCount: 0,
                    previewCards: [],
                    launchedCards: [],
                    comingSoonClimbs: []
                ),
                mode: .own,
                notificationState: notificationState
            )
        }
        .frame(width: 402, height: 874)
        .background(ProfileVisualStyle.background)
    }
}

@MainActor
private final class StubClimbDropNotificationStateClient: ClimbDropNotificationStateClient {
    var isPreferenceEnabled: Bool
    private var status: UNAuthorizationStatus

    init(
        authorizationStatus: UNAuthorizationStatus,
        isPreferenceEnabled: Bool
    ) {
        status = authorizationStatus
        self.isPreferenceEnabled = isPreferenceEnabled
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestDuringOnboarding() async -> UNAuthorizationStatus {
        await enable()
    }

    func enable() async -> UNAuthorizationStatus {
        status = .authorized
        isPreferenceEnabled = true
        return status
    }

    func disable() async {
        isPreferenceEnabled = false
    }

    func openSystemNotificationSettings() {}
}
