import SwiftUI
import Testing
import UIKit
@testable import AscendApp

@MainActor
@Suite(.serialized, .hostsAWindow)
struct AppUpdateSheetHostingTests {
    private static let iPhone16ProSize = CGSize(width: 402, height: 874)

    @Test(
        "The recommended nudge keeps its dismissible sheet and its Later action",
        .bug(id: 319)
    )
    func presentedSheetEnforcesItsContract() async throws {
        try await withAccessibilityAutomation {
            let presentation = AppUpdatePresentation.recommended
            let recorder = AppUpdateSheetActionRecorder()
            let controller = UIHostingController(
                rootView: AppUpdateSheetPresentationHarness(
                    gateState: AppVersionGateState(presentation: presentation),
                    recorder: recorder
                )
            )
            controller.overrideUserInterfaceStyle = .dark
            controller.traitOverrides.preferredContentSizeCategory =
                .accessibilityExtraExtraExtraLarge

            let windowScene = try #require(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            )
            let window = UIWindow(windowScene: windowScene)
            window.frame = CGRect(origin: .zero, size: Self.iPhone16ProSize)
            window.overrideUserInterfaceStyle = .dark
            window.rootViewController = controller

            let animationsWereEnabled = UIView.areAnimationsEnabled
            UIView.setAnimationsEnabled(false)
            defer {
                UIView.setAnimationsEnabled(animationsWereEnabled)
                window.isHidden = true
                window.rootViewController = nil
                window.windowScene = nil
            }

            window.makeKeyAndVisible()
            #expect(controller.viewIfLoaded?.window === window)
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

            try captureEvidence(
                window: window,
                controller: sheetController,
                name: "app-update-\(presentation.rawValue)",
                contrast: .normal
            )
            try captureEvidence(
                window: window,
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

    /// The escalation an incident actually performs: arm the recommendation, then the minimum.
    /// The lockout is a route now, so escalating has to take the dismissible prompt - and its Later
    /// button - off the screen entirely rather than leaving two update surfaces stacked.
    @Test("Escalating to the lockout retires the nudge sheet", .bug(id: 429))
    func escalatingToTheLockoutRetiresTheNudgeSheet() async throws {
        try await withAccessibilityAutomation {
            let recorder = AppUpdateSheetActionRecorder()
            let gateState = AppVersionGateState(presentation: .recommended)
            let controller = UIHostingController(
                rootView: AppUpdateSheetPresentationHarness(
                    gateState: gateState,
                    recorder: recorder
                )
            )
            controller.overrideUserInterfaceStyle = .dark

            let windowScene = try #require(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            )
            let window = UIWindow(windowScene: windowScene)
            window.frame = CGRect(origin: .zero, size: Self.iPhone16ProSize)
            window.overrideUserInterfaceStyle = .dark
            window.rootViewController = controller

            let animationsWereEnabled = UIView.areAnimationsEnabled
            UIView.setAnimationsEnabled(false)
            defer {
                UIView.setAnimationsEnabled(animationsWereEnabled)
                window.isHidden = true
                window.rootViewController = nil
                window.windowScene = nil
            }

            window.makeKeyAndVisible()
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

    /// The lockout as it actually ships: a full screen, one action, and no way past it. Hosted with
    /// nothing presenting over it, because as a route there is no presenter left to occlude it.
    @Test("The lockout owns the whole screen and offers only the App Store", .bug(id: 429))
    func lockoutRouteOffersOnlyTheAppStoreAction() async throws {
        try await withAccessibilityAutomation {
            let recorder = AppUpdateSheetActionRecorder()
            let controller = UIHostingController(
                rootView: AppUpdateRequiredView(onOpenAppStore: recorder.recordAppStoreOpen)
            )
            controller.overrideUserInterfaceStyle = .dark
            controller.traitOverrides.preferredContentSizeCategory =
                .accessibilityExtraExtraExtraLarge

            let windowScene = try #require(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            )
            let window = UIWindow(windowScene: windowScene)
            window.frame = CGRect(origin: .zero, size: Self.iPhone16ProSize)
            window.overrideUserInterfaceStyle = .dark
            window.rootViewController = controller

            let animationsWereEnabled = UIView.areAnimationsEnabled
            UIView.setAnimationsEnabled(false)
            defer {
                UIView.setAnimationsEnabled(animationsWereEnabled)
                window.isHidden = true
                window.rootViewController = nil
                window.windowScene = nil
            }

            window.makeKeyAndVisible()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()

            // Nothing is presented over the root: the refusal *is* the root.
            #expect(controller.presentedViewController == nil)

            let elements = try await settledAccessibilityElements(under: controller.view) {
                $0.contains { $0.accessibilityTraits.contains(.button) }
            }
            let buttonLabels = elements
                .filter { $0.accessibilityTraits.contains(.button) }
                .compactMap(\.accessibilityLabel)

            // Deduplicated: the scroll container republishes the controls it holds, so the same
            // button legitimately appears twice in the tree. What matters is that no *other*
            // action exists - there is exactly one way off this screen.
            #expect(Set(buttonLabels) == ["Update on the App Store"])

            let labels = elements.compactMap(\.accessibilityLabel)
            #expect(labels.contains(AppUpdatePresentation.required.title))
            #expect(labels.contains(AppUpdatePresentation.required.message))

            try captureEvidence(
                window: window,
                controller: controller,
                name: "app-update-lockout-route",
                contrast: .normal
            )
            try captureEvidence(
                window: window,
                controller: controller,
                name: "app-update-lockout-route",
                contrast: .high
            )

            try activateAccessibilityElement(
                labelled: "Update on the App Store",
                in: controller.view
            )
            #expect(recorder.appStoreOpenCount == 1)
        }
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

    private func captureEvidence(
        window: UIWindow,
        controller: UIViewController,
        name: String,
        contrast: UIAccessibilityContrast
    ) throws {
        controller.traitOverrides.accessibilityContrast = contrast
        #expect(controller.traitCollection.accessibilityContrast == contrast)

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        var didDraw = false
        let image = UIGraphicsImageRenderer(
            size: Self.iPhone16ProSize,
            format: format
        ).image { _ in
            didDraw = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let png = try #require(image.pngData(), "Update surface evidence did not encode as PNG")

        let directory = URL(
            filePath: ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
                ?? "/tmp/ascend-issue-319-evidence",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let contrastName = contrast == .high ? "increased-contrast" : "normal-contrast"
        let url = directory.appending(path: "\(name)-dark-AXXXL-\(contrastName).png")
        try png.write(to: url)

        #expect(didDraw)
        #expect(png.count > 5_000)
        print("Update surface evidence: \(url.path())")
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
