import SwiftUI
import Testing
import UIKit
@testable import AscendApp

@MainActor
@Suite(.serialized, .hostsAWindow)
struct AppUpdateSheetHostingTests {
    @Test(
        "The recommended nudge keeps its dismissible sheet and its Later action",
        .bug(id: 319)
    )
    func presentedSheetEnforcesItsContract() async throws {
        let presentation = AppUpdatePresentation.recommended
        let recorder = AppUpdateSheetActionRecorder()
        let controller = UIHostingController(
            rootView: AppUpdateSheetPresentationHarness(
                gateState: AppVersionGateState(presentation: presentation),
                recorder: recorder
            )
        )
        controller.traitOverrides.preferredContentSizeCategory =
            .accessibilityExtraExtraExtraLarge

        try await withoutAnimations {
            try await RenderedScreen.host(controller) { screen in
                #expect(controller.viewIfLoaded?.window === screen.window)
                await recorder.waitForAppearance(of: presentation)

                let sheetController = try #require(controller.presentedViewController)
                sheetController.view.setNeedsLayout()
                sheetController.view.layoutIfNeeded()

                let elements = try await settledAccessibilityElements(under: sheetController.view) {
                    $0.contains { $0.accessibilityViewIsModal }
                }
                let buttonLabels = elements
                    .filter { $0.accessibilityTraits.contains(.button) }
                    .compactMap(\.accessibilityLabel)

                #expect(buttonLabels.contains("Update on the App Store"))
                #expect(buttonLabels.contains("Later"))
                #expect(buttonLabels.count == 2)
                #expect(sheetController.isModalInPresentation == false)

                try photograph(
                    screen,
                    controller: sheetController,
                    name: "app-update-\(presentation.rawValue)",
                    contrast: .normal
                )
                try photograph(
                    screen,
                    controller: sheetController,
                    name: "app-update-\(presentation.rawValue)",
                    contrast: .high
                )

                try activateAccessibilityElement(
                    labelled: "Update on the App Store",
                    in: sheetController.view
                )
                #expect(recorder.appStoreOpenCount == 1)

                try activateAccessibilityElement(labelled: "Later", in: sheetController.view)
                await recorder.waitForDismissal()
                #expect(controller.presentedViewController == nil)
                #expect(recorder.laterCount == 1)
            }
        }
    }

    /// The escalation an incident actually performs: arm the recommendation, then the minimum.
    /// The lockout is a route now, so escalating has to take the dismissible prompt - and its Later
    /// button - off the screen entirely rather than leaving two update surfaces stacked.
    @Test("Escalating to the lockout retires the nudge sheet", .bug(id: 429))
    func escalatingToTheLockoutRetiresTheNudgeSheet() async throws {
        let recorder = AppUpdateSheetActionRecorder()
        let gateState = AppVersionGateState(presentation: .recommended)
        let controller = UIHostingController(
            rootView: AppUpdateSheetPresentationHarness(
                gateState: gateState,
                recorder: recorder
            )
        )

        try await withoutAnimations {
            try await RenderedScreen.host(controller) { _ in
                await recorder.waitForAppearance(of: .recommended)

                _ = try #require(
                    await presentedSheet(on: controller) { sheet, buttonLabels in
                        buttonLabels.contains("Later") && sheet.isModalInPresentation == false
                    },
                    "The recommended prompt never settled on a dismissible sheet with a Later action"
                )

                gateState.presentation = .required

                #expect(
                    try await settles { controller.presentedViewController == nil },
                    "The nudge sheet outlived the escalation and would have covered the lockout route"
                )
                #expect(gateState.nudgePresentation == nil)
                #expect(gateState.isUpdateRequired)
                #expect(recorder.laterCount == 0)
            }
        }
    }

    /// The lockout as it actually ships above authentication: a full screen, one action, and no way
    /// past it. Hosted with nothing presenting over it, because as a route there is no presenter
    /// left to occlude it. There is no session here, so deletion would be a dead end rather than an
    /// exit - the refusal offers the App Store and nothing else.
    @Test("The lockout owns the whole screen and offers only the App Store", .bug(id: 429))
    func lockoutRouteOffersOnlyTheAppStoreAction() async throws {
        let recorder = AppUpdateSheetActionRecorder()
        try await hostingTheLockout(
            view: AppUpdateRequiredView(onOpenAppStore: recorder.recordAppStoreOpen),
            evidenceName: "app-update-lockout-route"
        ) { controller, buttonLabels, labels in
            // Deduplicated: the scroll container republishes the controls it holds, so the same
            // button legitimately appears twice in the tree. What matters is that no *other*
            // action exists - there is exactly one way off this screen.
            #expect(Set(buttonLabels) == ["Update on the App Store"])

            #expect(labels.contains(AppUpdatePresentation.required.title))
            #expect(labels.contains(AppUpdatePresentation.required.message))

            try activateAccessibilityElement(
                labelled: "Update on the App Store",
                in: controller.view
            )
            #expect(recorder.appStoreOpenCount == 1)
        }
    }

    /// The lockout absorbs the whole app for a signed-in climber, including the declined subscriber
    /// parked at the entitlement gate. Guideline 5.1.1(v) admits no exception, so deletion has to
    /// leave from here too - subordinate to the update, never instead of it.
    @Test("An authenticated lockout also routes to account deletion", .bug(id: 429))
    func lockoutRouteOffersDeletionToAnAuthenticatedClimber() async throws {
        let recorder = AppUpdateSheetActionRecorder()
        let deletionRequests = DeletionRequestRecorder()

        try await hostingTheLockout(
            view: AppUpdateRequiredView(
                onOpenAppStore: recorder.recordAppStoreOpen,
                onDeleteAccount: deletionRequests.record
            ),
            evidenceName: "app-update-lockout-route-authenticated"
        ) { controller, buttonLabels, labels in
            #expect(Set(buttonLabels) == ["Update on the App Store", "Delete account"])

            #expect(labels.contains(AppUpdatePresentation.required.title))
            #expect(labels.contains(AppUpdatePresentation.required.message))

            // The primary action stays reachable at AXXXL: deletion may not push it under the
            // fold, and the screen scrolls rather than truncating either one.
            try activateAccessibilityElement(
                labelled: "Update on the App Store",
                in: controller.view
            )
            #expect(recorder.appStoreOpenCount == 1)

            try activateAccessibilityElement(
                labelled: "Delete account",
                in: controller.view
            )
            #expect(deletionRequests.count == 1)
        }
    }

    /// Hosts `view` full-screen, dark, at AXXXL through `RenderedScreen`, photographs it at both
    /// contrasts when `ASCEND_EVIDENCE_DIR` is set, and hands the settled accessibility tree to
    /// `assertions`.
    private func hostingTheLockout(
        view: AppUpdateRequiredView,
        evidenceName: String,
        assertions: (UIViewController, [String], [String]) throws -> Void
    ) async throws {
        let controller = UIHostingController(rootView: view)
        controller.traitOverrides.preferredContentSizeCategory =
            .accessibilityExtraExtraExtraLarge

        try await withoutAnimations {
            try await RenderedScreen.host(controller) { screen in
                // Nothing is presented over the root: the refusal *is* the root.
                #expect(controller.presentedViewController == nil)

                let elements = try await settledAccessibilityElements(under: controller.view) {
                    $0.contains { $0.accessibilityTraits.contains(.button) }
                }
                let buttonLabels = elements
                    .filter { $0.accessibilityTraits.contains(.button) }
                    .compactMap(\.accessibilityLabel)

                try photograph(screen, controller: controller, name: evidenceName, contrast: .normal)
                try photograph(screen, controller: controller, name: evidenceName, contrast: .high)

                try assertions(controller, buttonLabels, elements.compactMap(\.accessibilityLabel))
            }
        }
    }

    /// Sheets animate in and out; with animations on, a presented sheet's tree and a dismissed
    /// sheet's absence both arrive a transition later than the assertion that reads them.
    private func withoutAnimations(_ body: () async throws -> Void) async throws {
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        try await body()
    }

    /// Whether `condition` holds before the deadline. Bounded so a sheet that never goes away fails
    /// the test rather than hanging it.
    private func settles(
        waitingUpTo timeout: Duration = .seconds(5),
        _ condition: () -> Bool
    ) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while true {
            if condition() { return true }
            if ContinuousClock.now >= deadline { return false }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// The presented sheet once it settles on `isSettled`, or `nil` at the deadline.
    ///
    /// Bounded on purpose: a sheet that never swaps has to fail this test rather than hang it, and
    /// the dismiss-and-re-present pass leaves `presentedViewController` briefly nil. `isSettled`
    /// takes the controller as well as its labels so every property a caller means to assert is
    /// part of the settle condition - a swap publishes the new accessibility tree and the new
    /// `isModalInPresentation` on their own render passes, so asserting either one outside this
    /// loop is a race that fails on a sheet that is correct a frame later.
    private func presentedSheet(
        on controller: UIViewController,
        waitingUpTo timeout: Duration = .seconds(5),
        settlingWhen isSettled: (UIViewController, [String]) -> Bool
    ) async throws -> UIViewController? {
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while true {
            if let presented = controller.presentedViewController {
                presented.view.setNeedsLayout()
                presented.view.layoutIfNeeded()

                let buttonLabels = accessibilityElements(under: presented.view)
                    .filter { $0.accessibilityTraits.contains(.button) }
                    .compactMap(\.accessibilityLabel)

                if isSettled(presented, buttonLabels) {
                    return presented
                }
            }

            if ContinuousClock.now >= deadline {
                return nil
            }

            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Switches the surface to `contrast` - the override has to take, whether or not a photograph
    /// is kept - and writes the 3x photograph only when `ASCEND_EVIDENCE_DIR` is set.
    private func photograph(
        _ screen: HostedScreen,
        controller: UIViewController,
        name: String,
        contrast: UIAccessibilityContrast
    ) throws {
        controller.traitOverrides.accessibilityContrast = contrast
        #expect(controller.traitCollection.accessibilityContrast == contrast)

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let contrastName = contrast == .high ? "increased-contrast" : "normal-contrast"
        try screen.photograph(named: "\(name)-dark-AXXXL-\(contrastName)")
    }
}

@MainActor
private final class DeletionRequestRecorder {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

@MainActor
private final class AppUpdateSheetActionRecorder {
    private(set) var appStoreOpenCount = 0
    private(set) var laterCount = 0
    private var appearedPresentations: Set<AppUpdatePresentation> = []
    private var appearanceWaiters: [
        AppUpdatePresentation: [CheckedContinuation<Void, Never>]
    ] = [:]
    private var didDismiss = false
    private var dismissalWaiters: [CheckedContinuation<Void, Never>] = []

    func recordAppStoreOpen() {
        appStoreOpenCount += 1
    }

    func recordLater() {
        laterCount += 1
    }

    func recordAppearance(of presentation: AppUpdatePresentation) {
        appearedPresentations.insert(presentation)
        let waiters = appearanceWaiters.removeValue(forKey: presentation) ?? []
        waiters.forEach { $0.resume() }
    }

    func waitForAppearance(of presentation: AppUpdatePresentation) async {
        if appearedPresentations.contains(presentation) { return }

        await withCheckedContinuation { continuation in
            appearanceWaiters[presentation, default: []].append(continuation)
        }
    }

    func recordDismissal() {
        didDismiss = true
        let waiters = dismissalWaiters
        dismissalWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitForDismissal() async {
        if didDismiss { return }

        await withCheckedContinuation { continuation in
            dismissalWaiters.append(continuation)
        }
    }
}

/// Bound to the real ``AppVersionGateState`` through the same `nudgePresentation` binding `RootView`
/// uses, so the escalation case proves the lockout leaves the sheet layer rather than joining it.
private struct AppUpdateSheetPresentationHarness: View {
    @Bindable var gateState: AppVersionGateState
    let recorder: AppUpdateSheetActionRecorder

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .sheet(item: $gateState.nudgePresentation, onDismiss: recorder.recordDismissal) { presentation in
                AppUpdateSheet(
                    presentation: presentation,
                    onOpenAppStore: recorder.recordAppStoreOpen,
                    onLater: {
                        recorder.recordLater()
                        gateState.dismissRecommended()
                    }
                )
                .onAppear {
                    recorder.recordAppearance(of: presentation)
                }
            }
    }
}
