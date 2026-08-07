import SwiftUI
import Testing
import UIKit
@testable import AscendApp

@MainActor
@Suite(.serialized, .hostsAWindow)
struct AppUpdateSheetHostingTests {
    private static let iPhone16ProSize = CGSize(width: 402, height: 874)

    @Test(
        "Parent-presented update sheets enforce their action and dismissal contracts",
        .bug(id: 319),
        arguments: [AppUpdatePresentation.required, .recommended]
    )
    func presentedSheetEnforcesItsContract(
        presentation: AppUpdatePresentation
    ) async throws {
        try await withAccessibilityAutomation {
            let recorder = AppUpdateSheetActionRecorder()
            let controller = UIHostingController(
                rootView: AppUpdateSheetPresentationHarness(
                    presentation: presentation,
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
            let modalElement = try #require(elements.first { $0.accessibilityViewIsModal })

            #expect(buttonLabels.contains("Update on the App Store"))
            #expect(buttonLabels.contains("Later") == presentation.showsLaterAction)
            #expect(buttonLabels.count == (presentation.showsLaterAction ? 2 : 1))

            #expect(
                sheetController.isModalInPresentation
                    == (presentation.allowsInteractiveDismissal == false)
            )

            try captureEvidence(
                window: window,
                sheetController: sheetController,
                presentation: presentation,
                contrast: .normal
            )
            try captureEvidence(
                window: window,
                sheetController: sheetController,
                presentation: presentation,
                contrast: .high
            )

            try activateAccessibilityElement(
                labelled: "Update on the App Store",
                in: sheetController.view
            )
            #expect(recorder.appStoreOpenCount == 1)

            if presentation == .required {
                #expect(modalElement.accessibilityPerformEscape() == false)
                #expect(controller.presentedViewController === sheetController)
                #expect(recorder.laterCount == 0)
            } else {
                try activateAccessibilityElement(labelled: "Later", in: sheetController.view)
                await recorder.waitForDismissal()
                #expect(controller.presentedViewController == nil)
                #expect(recorder.laterCount == 1)
            }
        }
    }

    private func captureEvidence(
        window: UIWindow,
        sheetController: UIViewController,
        presentation: AppUpdatePresentation,
        contrast: UIAccessibilityContrast
    ) throws {
        sheetController.traitOverrides.accessibilityContrast = contrast
        #expect(sheetController.traitCollection.accessibilityContrast == contrast)

        sheetController.view.setNeedsLayout()
        sheetController.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        var didDraw = false
        let image = UIGraphicsImageRenderer(
            size: Self.iPhone16ProSize,
            format: format
        ).image { _ in
            didDraw = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let png = try #require(image.pngData(), "Update sheet evidence did not encode as PNG")

        let directory = URL(
            filePath: ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
                ?? "/tmp/ascend-issue-319-evidence",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let contrastName = contrast == .high ? "increased-contrast" : "normal-contrast"
        let url = directory.appending(
            path: "app-update-\(presentation.rawValue)-dark-AXXXL-\(contrastName).png"
        )
        try png.write(to: url)

        #expect(didDraw)
        #expect(png.count > 5_000)
        print("Issue #319 update sheet evidence: \(url.path())")
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

private struct AppUpdateSheetPresentationHarness: View {
    @State private var presentation: AppUpdatePresentation?
    let recorder: AppUpdateSheetActionRecorder

    init(
        presentation: AppUpdatePresentation,
        recorder: AppUpdateSheetActionRecorder
    ) {
        _presentation = State(initialValue: presentation)
        self.recorder = recorder
    }

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .sheet(item: $presentation, onDismiss: recorder.recordDismissal) { presentation in
                AppUpdateSheet(
                    presentation: presentation,
                    onOpenAppStore: recorder.recordAppStoreOpen,
                    onLater: {
                        recorder.recordLater()
                        self.presentation = nil
                    }
                )
                .onAppear {
                    recorder.recordAppearance(of: presentation)
                }
            }
    }
}
