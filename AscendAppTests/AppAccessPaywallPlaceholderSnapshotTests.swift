import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

@MainActor
@Suite(.serialized, .hostsAWindow)
struct AppAccessPaywallPlaceholderSnapshotTests {
    @Test
    func evidenceCoversEveryRealGatePhaseAcrossAppearanceDeviceAndTextVariants() async throws {
        #expect(gateScenarios.map(\.phase) == AppAccessGatePhase.allCases)

        for surface in evidenceSurfaces {
            for scenario in gateScenarios {
                try await render(
                    scenario: scenario,
                    restoreState: .idle,
                    plans: snapshotPlans,
                    surface: surface,
                    evidenceName: "app-access-\(surface.id)-\(scenario.id)"
                )
            }
        }
    }

    @Test
    func evidenceCoversEveryRestoreStateWithoutContradictingSuccessfulAccess() async throws {
        #expect(restoreScenarios.map(\.state) == AppAccessRestoreState.allCases)

        for scenario in restoreScenarios {
            try await render(
                scenario: scenario.gateScenario,
                restoreState: scenario.state,
                plans: snapshotPlans,
                surface: restoreSurface,
                evidenceName: "app-access-restore-\(scenario.id)"
            )
        }
    }

    @Test
    func evidenceNamesOnlyTheActuallyLoadedSinglePlanAndUsesItsTruthfulAction() async throws {
        let catalogs: [(String, [NativeSubscriptionPlan], String, String)] = [
            ("annual-only", [snapshotAnnualPlan], "Annual is available", "Start 7-day free trial"),
            ("monthly-only", [snapshotMonthlyPlan], "Monthly is available", "Subscribe with Apple")
        ]

        for (id, plans, status, action) in catalogs {
            let scenario = GateScenario(
                id: id,
                phase: .nativeReady,
                status: "\(status). Cancel anytime in Apple subscriptions.",
                expectedHeadline: "Choose your Ascend plan",
                reachableLabels: [status, plans[0].title, action, "Restore Purchases"],
                forbiddenLabels: plans[0].id == "annual" ? ["Monthly"] : ["Annual", "free trial"],
                includesRecovery: true
            )
            try await render(
                scenario: scenario,
                restoreState: .idle,
                plans: plans,
                surface: restoreSurface,
                evidenceName: "app-access-catalog-\(id)"
            )
        }
    }

    @Test
    func accountDeletionDismissalReassertsVoiceOverFocusOnTheDeleteAction() async throws {
        let probe = FocusRestorationProbe()
        let manager = makeManager()
        let content = AccountDeletionFocusHarness(manager: manager, probe: probe)

        try await withAccessibilityAutomation {
            try await host(content, surface: restoreSurface) { window in
                _ = try await settledAccessibilityElements(under: window) { elements in
                    elements.contains { $0.accessibilityLabel == "Simulate account deletion dismissal" }
                }
                try activateAccessibilityElement(
                    labelled: "Simulate account deletion dismissal",
                    in: window
                )
                await probe.waitUntilRestored()
                #expect(probe.restoreCount == 1)
                let delete = try await reachableElement(labelled: "Delete account", in: window)
                #expect(delete.accessibilityLabel == "Delete account")
            }
        }
    }

    private func render(
        scenario: GateScenario,
        restoreState: AppAccessRestoreState,
        plans: [NativeSubscriptionPlan],
        surface: EvidenceSurface,
        evidenceName: String
    ) async throws {
        let content = AppAccessPaywallPlaceholderView(
            initialPhase: scenario.phase,
            initialRestoreState: restoreState,
            initialPlans: plans,
            initialStatusMessage: scenario.status,
            automaticallyStarts: false,
            onDeleteAccount: {},
            onSignOut: {}
        )
        .environment(makeManager())
        .environment(\.dynamicTypeSize, surface.dynamicTypeSize)
        .environment(\.colorScheme, surface.style == .dark ? .dark : .light)
        .transaction { $0.disablesAnimations = true }

        try await withAccessibilityAutomation {
            try await host(content, surface: surface) { window in
                let elements = try await settledAccessibilityElements(under: window) { elements in
                    elements.contains {
                        $0.accessibilityLabel?.localizedCaseInsensitiveContains(
                            scenario.expectedHeadline
                        ) == true && $0.accessibilityFrame.height > 0
                    }
                }
                let labels = elements.compactMap(\.accessibilityLabel)
                for forbidden in scenario.forbiddenLabels {
                    #expect(labels.allSatisfy {
                        !$0.localizedCaseInsensitiveContains(forbidden)
                    })
                }

                for required in scenario.reachableLabels {
                    _ = try await reachableElement(labelled: required, in: window)
                }
                if scenario.includesRecovery {
                    for label in recoveryLabels {
                        _ = try await reachableElement(labelled: label, in: window)
                    }
                    try writeEvidence(
                        try capture(window),
                        named: "\(evidenceName)-recovery"
                    )
                }

                try await settleScrollAtTop(in: window)
                let settledAtTop = try await settledAccessibilityElements(under: window) { elements in
                    elements.contains {
                        $0.accessibilityLabel?.localizedCaseInsensitiveContains(
                            scenario.expectedHeadline
                        ) == true && window.bounds.intersects($0.accessibilityFrame)
                    }
                }
                let headline = try #require(settledAtTop.first {
                    $0.accessibilityLabel?.localizedCaseInsensitiveContains(
                        scenario.expectedHeadline
                    ) == true
                })
                expectVisibleFrame(headline, in: window, label: scenario.expectedHeadline)

                let image = try capture(window)
                let recognized = try await recognizedText(in: image)
                #expect(
                    recognized.contains(scenario.expectedHeadline.lowercased()),
                    "OCR could not find \(scenario.expectedHeadline) in \(evidenceName)"
                )
                try writeEvidence(image, named: evidenceName)
            }
        }
    }

    private func host<Content: View>(
        _ content: Content,
        surface: EvidenceSurface,
        body: (UIWindow) async throws -> Void
    ) async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let controller = UIHostingController(rootView: content)
        let window = UIWindow(windowScene: scene)
        let bounds = CGRect(origin: .zero, size: surface.size)
        controller.overrideUserInterfaceStyle = surface.style
        controller.view.frame = bounds
        window.frame = bounds
        window.overrideUserInterfaceStyle = surface.style
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        window.layoutIfNeeded()
        await Task.yield()
        try await Task.sleep(for: .milliseconds(20))
        controller.view.layoutIfNeeded()
        window.layoutIfNeeded()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await body(window)
    }

    private func reachableElement(labelled label: String, in window: UIWindow) async throws -> NSObject {
        let scrollView = try #require(findScrollView(in: window))
        let maximumOffset = max(
            0,
            scrollView.contentSize.height + scrollView.adjustedContentInset.bottom
                - scrollView.bounds.height
        )
        var attempts = 0
        while attempts < 20 {
            window.layoutIfNeeded()
            let elements = accessibilityElements(under: window)
            if let match = elements.first(where: {
                $0.accessibilityLabel?.localizedCaseInsensitiveContains(label) == true
            }), window.bounds.intersects(match.accessibilityFrame),
               match.accessibilityFrame.width > 0,
               match.accessibilityFrame.height > 0 {
                expectVisibleFrame(match, in: window, label: label)
                return match
            }
            let nextOffset = min(
                maximumOffset,
                scrollView.contentOffset.y + max(80, scrollView.bounds.height * 0.55)
            )
            if nextOffset == scrollView.contentOffset.y { break }
            scrollView.setContentOffset(CGPoint(x: 0, y: nextOffset), animated: false)
            scrollView.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
            attempts += 1
        }
        let found = accessibilityElements(under: window).compactMap(\.accessibilityLabel)
        Issue.record("\(label) never reached the viewport. Published labels: \(found)")
        return try #require(accessibilityElements(under: window).first {
            $0.accessibilityLabel?.localizedCaseInsensitiveContains(label) == true
        })
    }

    private func expectVisibleFrame(_ element: NSObject, in window: UIWindow, label: String) {
        #expect(element.accessibilityFrame.width > 0, "\(label) has no width")
        #expect(element.accessibilityFrame.height > 0, "\(label) has no height")
        #expect(window.bounds.intersects(element.accessibilityFrame), "\(label) is outside the viewport")
    }

    private func findScrollView(in root: UIView) -> UIScrollView? {
        if let scrollView = root as? UIScrollView { return scrollView }
        for subview in root.subviews {
            if let found = findScrollView(in: subview) { return found }
        }
        return nil
    }

    private func settleScrollAtTop(in window: UIWindow) async throws {
        let scrollView = try #require(findScrollView(in: window))
        let top = CGPoint(x: 0, y: -scrollView.adjustedContentInset.top)
        for _ in 0..<3 {
            scrollView.setContentOffset(top, animated: false)
            scrollView.setNeedsLayout()
            scrollView.layoutIfNeeded()
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(abs(scrollView.contentOffset.y - top.y) < 0.5)
    }

    private func capture(_ window: UIWindow) throws -> UIImage {
        var didDraw = false
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            didDraw = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        #expect(didDraw, "The live window hierarchy must render without a layer fallback")
        return image
    }

    private func recognizedText(in image: UIImage) async throws -> String {
        let cgImage = try #require(image.cgImage)
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        return try await request.perform(on: cgImage)
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .lowercased()
    }

    private func writeEvidence(_ image: UIImage, named name: String) throws {
        let png = try #require(image.pngData())
        let sourceRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"].map {
            URL(filePath: $0, directoryHint: .isDirectory)
        } ?? sourceRoot.appending(path: ".build/issue554-evidence", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(name).png")
        try png.write(to: url)
        #expect(png.count > 5_000)
        print("evidence: \(url.path())")
    }

    private func makeManager() -> MonetizationManager {
        MonetizationManager(
            entitlementService: EntitlementServiceStub(),
            paywallPresenter: PaywallPresenterSpy(),
            telemetry: makeTestTelemetry(
                sink: InMemoryTelemetrySink(destination: .analytics)
            )
        )
    }
}

private let snapshotAnnualPlan = NativeSubscriptionPlan(
    id: "annual",
    title: "Annual",
    localizedPrice: "$49.99",
    renewalDescription: "Renews annually",
    trialDescription: "7 days free",
    trialActionDescription: "Start 7-day free trial"
)

private let snapshotMonthlyPlan = NativeSubscriptionPlan(
    id: "monthly",
    title: "Monthly",
    localizedPrice: "$7.99",
    renewalDescription: "Renews monthly",
    trialDescription: nil
)

private let snapshotPlans = [snapshotAnnualPlan, snapshotMonthlyPlan]
private let recoveryLabels = [
    "Manage Subscription", "Terms", "Privacy", "Support", "Delete account", "Sign Out"
]

private struct GateScenario {
    let id: String
    let phase: AppAccessGatePhase
    let status: String?
    let expectedHeadline: String
    let reachableLabels: [String]
    let forbiddenLabels: [String]
    let includesRecovery: Bool
}

private let gateScenarios: [GateScenario] = [
    .init(id: "opening", phase: .openingHosted, status: nil, expectedHeadline: "Loading subscription options", reachableLabels: ["Loading subscription options"], forbiddenLabels: ["Subscribe", "Restore Purchases"], includesRecovery: false),
    .init(id: "hosted", phase: .hostedPresented, status: nil, expectedHeadline: "Loading subscription options", reachableLabels: ["Loading subscription options"], forbiddenLabels: ["Subscribe", "Restore Purchases"], includesRecovery: false),
    .init(id: "loading-native", phase: .loadingNative, status: nil, expectedHeadline: "Loading subscription options", reachableLabels: ["Loading subscription options", "Restore Purchases"], forbiddenLabels: ["Annual", "Monthly", "Subscribe with Apple"], includesRecovery: true),
    .init(id: "native-ready", phase: .nativeReady, status: "Choose from Annual and Monthly. Cancel anytime in Apple subscriptions.", expectedHeadline: "Choose your Ascend plan", reachableLabels: ["Annual", "Monthly", "Start 7-day free trial", "Restore Purchases"], forbiddenLabels: [], includesRecovery: true),
    .init(id: "purchasing", phase: .purchasing, status: "Complete your purchase in Apple checkout.", expectedHeadline: "Opening Apple checkout", reachableLabels: ["Opening Apple checkout", "Restore Purchases"], forbiddenLabels: ["Subscribe with Apple", "Start 7-day free trial"], includesRecovery: true),
    .init(id: "verifying", phase: .verifying, status: nil, expectedHeadline: "Checking your subscription access", reachableLabels: ["Checking your subscription access", "Restore Purchases"], forbiddenLabels: ["Subscribe with Apple", "RevenueCat"], includesRecovery: true),
    .init(id: "verification", phase: .verificationUnavailable, status: "Payment may still be processing. Do not purchase again.", expectedHeadline: "Checking your subscription access", reachableLabels: ["Check Access", "Restore Purchases"], forbiddenLabels: ["Subscribe with Apple", "RevenueCat"], includesRecovery: true),
    .init(id: "pending", phase: .pendingApproval, status: "Apple approval is pending. Do not purchase again.", expectedHeadline: "Approval is pending", reachableLabels: ["Check Access", "Restore Purchases"], forbiddenLabels: ["Subscribe with Apple"], includesRecovery: true),
    .init(id: "confirmed", phase: .accessConfirmed, status: nil, expectedHeadline: "Access confirmed", reachableLabels: ["Access confirmed", "Opening Ascend"], forbiddenLabels: ["Subscribe", "Restore", "Delete account", "Sign Out"], includesRecovery: false),
    .init(id: "failed", phase: .failed, status: "Subscription options took too long to load. Try again.", expectedHeadline: "Choose your Ascend plan", reachableLabels: ["Try Subscription Options Again", "Restore Purchases"], forbiddenLabels: ["Subscribe with Apple"], includesRecovery: true),
    .init(id: "back-unavailable", phase: .backUnavailable, status: "Ascend couldn't reopen the previous step. Try subscription options again, restore, manage your subscription, or contact support.", expectedHeadline: "Couldn't go back", reachableLabels: ["Try Subscription Options Again", "Restore Purchases", "Delete account"], forbiddenLabels: ["Choose your Ascend plan", "Subscribe with Apple"], includesRecovery: true)
]

private struct RestoreScenario {
    let id: String
    let state: AppAccessRestoreState
    let expectedButtonOrSuccess: String

    var gateScenario: GateScenario {
        if state == .restored {
            return GateScenario(
                id: id,
                phase: .accessConfirmed,
                status: nil,
                expectedHeadline: "Access confirmed",
                reachableLabels: ["Access confirmed", "Opening Ascend"],
                forbiddenLabels: ["Restore", "Try Subscription Options Again", "Subscribe"],
                includesRecovery: false
            )
        }
        return GateScenario(
            id: id,
            phase: .nativeReady,
            status: "Choose from Annual and Monthly. Cancel anytime in Apple subscriptions.",
            expectedHeadline: "Choose your Ascend plan",
            reachableLabels: [expectedButtonOrSuccess] + (state.statusMessage.map { [$0] } ?? []),
            forbiddenLabels: ["Restore Failed"],
            includesRecovery: true
        )
    }
}

private let restoreScenarios: [RestoreScenario] = [
    .init(id: "idle", state: .idle, expectedButtonOrSuccess: "Restore Purchases"),
    .init(id: "restoring", state: .restoring, expectedButtonOrSuccess: "Restoring"),
    .init(id: "restored", state: .restored, expectedButtonOrSuccess: "Opening Ascend"),
    .init(id: "not-found", state: .noPurchasesFound, expectedButtonOrSuccess: "Restore Purchases"),
    .init(id: "offline", state: .offline, expectedButtonOrSuccess: "Try Restore Again"),
    .init(id: "timed-out", state: .timedOut, expectedButtonOrSuccess: "Try Restore Again"),
    .init(id: "cancelled", state: .cancelled, expectedButtonOrSuccess: "Try Restore Again"),
    .init(id: "failed", state: .failed, expectedButtonOrSuccess: "Try Restore Again")
]

private struct EvidenceSurface {
    let id: String
    let size: CGSize
    let dynamicTypeSize: DynamicTypeSize
    let style: UIUserInterfaceStyle
}

private let evidenceSurfaces: [EvidenceSurface] = [
    .init(id: "compact-dark", size: CGSize(width: 375, height: 667), dynamicTypeSize: .large, style: .dark),
    .init(id: "large-light-system-forced-dark", size: CGSize(width: 430, height: 932), dynamicTypeSize: .large, style: .light),
    .init(id: "accessibility-dark", size: CGSize(width: 430, height: 932), dynamicTypeSize: .accessibility3, style: .dark)
]

private let restoreSurface = EvidenceSurface(
    id: "large-dark",
    size: CGSize(width: 430, height: 932),
    dynamicTypeSize: .large,
    style: .dark
)

@MainActor
private final class FocusRestorationProbe {
    private(set) var restoreCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func record() {
        restoreCount += 1
        waiters.forEach { $0.resume() }
        waiters = []
    }

    func waitUntilRestored() async {
        guard restoreCount == 0 else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private struct AccountDeletionFocusHarness: View {
    let manager: MonetizationManager
    let probe: FocusRestorationProbe
    @State private var dismissalRevision: UInt = 0

    var body: some View {
        VStack(spacing: 0) {
            Button("Simulate account deletion dismissal") {
                dismissalRevision &+= 1
            }
            AppAccessPaywallPlaceholderView(
                initialPhase: .failed,
                initialPlans: snapshotPlans,
                initialStatusMessage: "Subscription options are unavailable.",
                automaticallyStarts: false,
                accountDeletionDismissalRevision: dismissalRevision,
                onAccountDeletionFocusRestored: probe.record,
                onDeleteAccount: {},
                onSignOut: {}
            )
        }
        .environment(manager)
    }
}
