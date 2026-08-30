import Foundation
import RevenueCat
import SuperwallKit
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Reviewer-facing pixels for the Guideline 2.1(b) rejection of build 2026081401 (#506).
///
/// `AppReviewSandboxEntitlementTests` holds the rule; this photographs what App Review actually
/// looks at. One entitlement - the reviewer's: active, RevenueCat-verified, bought in whichever
/// StoreKit environment is *not* the one `BundleSandboxEnvironmentDetector` reads off this binary
/// - is run twice through the shipped `RevenueCatPurchaseExecutor` and `AppAccessRestoreService`:
/// once resolved with the deleted `Set(entitlements.activeInCurrentEnvironment.keys)` line, once
/// with the shipped `appAccessEntitlementState`. The alert copy and the gate's restore line in the
/// PNGs are the ones those production calls returned, not strings this file wrote.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct AppReviewSandboxEntitlementEvidenceTests {
    private static let entitlementID = "app_access"
    private static let productID = "ascend_yearly"

    /// The purchase half: what Apple screenshotted, beside what a reviewer buying today gets.
    @Test
    func photographsThePurchaseAlertTheRejectionWasAbout() async throws {
        let entitlements = try #require(
            Self.crossEnvironmentEntitlements(),
            "RevenueCat no longer filters by environment, so there is no reviewer case to photograph"
        )

        let rejected = await Self.purchase(resolving: Self.oldRuleState(for: entitlements))
        let shipped = await Self.purchase(resolving: entitlements.appAccessEntitlementState)

        let alertMessage = try #require(
            Self.failureAlertMessage(rejected.result),
            "The old filter is what raised the purchase-failure alert; got \(rejected.result)"
        )
        #expect(alertMessage == "Ascend couldn't confirm your subscription. Check your connection and try again.")
        #expect(rejected.events.contains("revenuecat_purchase_failed"))

        #expect(Self.isPurchased(shipped.result))
        #expect(Self.failureAlertMessage(shipped.result) == nil)
        #expect(shipped.events.contains("revenuecat_purchase_completed"))

        let before = try await Self.captureAlert(message: alertMessage)
        let after = try await Self.captureAlert(message: nil)

        try Self.write(
            PurchaseAlertProof(
                subtitle: Self.environmentSubtitle(for: entitlements),
                before: before,
                beforeCaption: "Build 2026081401 · rejected",
                beforeDetail: "Superwall .failed → \(alertMessage)",
                beforeEvents: rejected.events,
                after: after,
                afterCaption: "This build",
                afterDetail: "Superwall .purchased → no alert presented, paywall dismisses, app unlocks",
                afterEvents: shipped.events
            ),
            named: "app-review-purchase-alert-before-after"
        )
    }

    /// The restore half: the reviewer's own workaround, which produced a second error.
    @Test
    func photographsTheGateRestoreLineTheReviewerWouldHaveHitNext() async throws {
        let entitlements = try #require(Self.crossEnvironmentEntitlements())

        let rejected = await Self.restore(resolving: Self.oldRuleState(for: entitlements))
        let shipped = await Self.restore(resolving: entitlements.appAccessEntitlementState)

        #expect(rejected.state == .noPurchasesFound)
        #expect(
            rejected.state.statusMessage
                == "No active Ascend subscription was found for this Apple ID."
        )
        #expect(rejected.events.contains("revenuecat_restore_not_found"))

        #expect(shipped.state == .restored)
        #expect(shipped.state.statusMessage == nil)
        #expect(shipped.events.contains("revenuecat_restore_completed"))

        let manager = MonetizationManager(
            entitlementService: EntitlementServiceStub(),
            paywallPresenter: PaywallPresenterSpy(),
            telemetry: makeTestTelemetry(sink: InMemoryTelemetrySink(destination: .analytics))
        )

        try Self.write(
            GateRestoreProof(
                monetizationManager: manager,
                before: .init(
                    caption: "Build 2026081401 · rejected",
                    detail: "AppAccessRestoreService → .notFound",
                    state: rejected.state,
                    events: rejected.events
                ),
                after: .init(
                    caption: "This build",
                    detail: "AppAccessRestoreService → .restored([app_access])",
                    state: shipped.state,
                    events: shipped.events
                )
            ),
            named: "app-review-gate-restore-before-after"
        )
    }

    /// The analyst's view of the same two runs, plus the diagnostic pair that was missing when this
    /// had to be diagnosed from a rejection notice. Written as a transcript rather than asserted
    /// field by field, because what was missing was a readable stream, not a value.
    @Test
    func writesTheReviewersEventTranscriptWithTheEnvironmentPair() async throws {
        let entitlements = try #require(Self.crossEnvironmentEntitlements())
        let diagnostics = StoreKitEnvironmentDiagnostics(
            receiptName: { StoreKitReceiptEnvironment.receiptName },
            telemetry: makeTestTelemetry(sink: InMemoryTelemetrySink(destination: .analytics))
        )
        diagnostics.record(holdsSandboxEntitlement: entitlements.holdsSandboxEntitlement)

        var lines: [String] = [
            "App Review sandbox entitlement · #506",
            "",
            "One entitlement, read twice.",
            "",
            "  entitlement            app_access, active, ascend_yearly trial, isSandbox=\(entitlements.holdsSandboxEntitlement)",
            "  device, per the SDK    \(entitlements.holdsSandboxEntitlement ? "production" : "sandbox") (a simulator reads itself as sandbox)",
            "  storekit_receipt_name  \(StoreKitReceiptEnvironment.receiptName)",
            "",
            "The two disagree, which is what an App Review install produces and exactly what",
            "activeInCurrentEnvironment refuses. This host mirrors the reviewer's direction of it.",
            "",
            "Events below are the ones the shipped RevenueCatPurchaseExecutor and",
            "AppAccessRestoreService emitted, read back off the telemetry sink.",
            ""
        ]

        for run in [
            (title: "OLD RULE - Set(entitlements.activeInCurrentEnvironment.keys)", state: Self.oldRuleState(for: entitlements)),
            (title: "SHIPPED RULE - entitlements.appAccessEntitlementState", state: entitlements.appAccessEntitlementState)
        ] {
            let purchase = await Self.purchase(resolving: run.state)
            let restore = await Self.restore(resolving: run.state)

            lines.append(String(repeating: "-", count: 78))
            lines.append(run.title)
            lines.append("resolved entitlement state   \(run.state)")
            lines.append("")
            lines.append("BUY")
            lines.append(contentsOf: purchase.records.map { "  " + Self.describe($0) })
            lines.append("  climber sees               \(Self.failureAlertMessage(purchase.result) ?? "no alert - purchase completes")")
            lines.append("")
            lines.append("RESTORE")
            lines.append(contentsOf: restore.records.map { "  " + Self.describe($0) })
            lines.append("  climber sees               \(restore.state.statusMessage ?? "\"\(restore.state.buttonTitle(isRevenueCatConfigured: true))\" - gate unlocks")")
            lines.append("")
        }

        // The sink above ran against the process-wide diagnostics, which no test may drive into
        // having heard from RevenueCat without changing what every other suite's events carry. So
        // the answered case is rendered through `record(diagnostics:)` - the same function
        // `TelemetryManager.track` calls - on this suite's own instance.
        lines.append(String(repeating: "-", count: 78))
        lines.append("SAME EVENTS ONCE REVENUECAT HAS ANSWERED - PaywallAnalyticsEvent.record(diagnostics:)")
        lines.append("")
        for event in Self.diagnosticEvents {
            lines.append("  " + Self.describe(event.record(diagnostics: diagnostics)))
        }
        lines.append("")

        let transcript = lines.joined(separator: "\n")
        print(transcript)

        let url = Self.evidenceDirectory.appending(path: "app-review-sandbox-entitlement-transcript.txt")
        try Data(transcript.utf8).write(to: url)
        print("ASCEND_EVIDENCE_FILE: \(url.path())")

        #expect(transcript.contains("storekit_receipt_name"))
        #expect(transcript.contains("holds_sandbox_entitlement=\(entitlements.holdsSandboxEntitlement)"))
    }
}

// MARK: - Production runs

private extension AppReviewSandboxEntitlementEvidenceTests {
    struct PurchaseRun {
        let result: SuperwallKit.PurchaseResult
        let records: [EnvelopedTelemetryRecord]
        var events: [String] { records.map(\.name) }
    }

    struct RestoreRun {
        let state: AppAccessRestoreState
        let records: [EnvelopedTelemetryRecord]
        var events: [String] { records.map(\.name) }
    }

    /// The deleted line, verbatim, so the "before" column is the shipped-and-rejected reading
    /// rather than a description of it.
    static func oldRuleState(
        for entitlements: RevenueCat.EntitlementInfos
    ) -> MonetizationEntitlementState {
        let entitlementIDs = Set(entitlements.activeInCurrentEnvironment.keys)

        return entitlementIDs.isEmpty ? .inactive : .active(entitlementIDs)
    }

    static func purchase(resolving state: MonetizationEntitlementState) async -> PurchaseRun {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let executor = RevenueCatPurchaseExecutor(
            telemetry: makeTestTelemetry(sink: sink),
            transactionContextStore: PaywallTransactionContextStore(),
            entitlementID: entitlementID,
            applySubscriptionStatus: { _ in },
            refreshEntitlementState: { .refreshed(state) }
        )

        let result = await executor.executePurchase(productID: productID) {
            RevenueCatPurchaseExecutor.PurchaseResponse(userCancelled: false)
        }

        return PurchaseRun(result: result, records: sink.records)
    }

    static func restore(resolving state: MonetizationEntitlementState) async -> RestoreRun {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let service = AppAccessRestoreService(
            telemetry: makeTestTelemetry(sink: sink),
            entitlementID: entitlementID,
            restorer: { RestorerStub(state: state) }
        )

        return RestoreRun(
            state: AppAccessRestoreState(outcome: await service.restore()),
            records: sink.records
        )
    }

    /// The reviewer's entitlement on whichever host runs the suite: active, and in the environment
    /// this binary is not. Exactly one of the two qualifies, so this cannot degrade into a
    /// tautology, and `nil` means RevenueCat stopped filtering rather than that the proof passed.
    static func crossEnvironmentEntitlements() -> RevenueCat.EntitlementInfos? {
        let matches = [true, false]
            .map { isSandbox in
                EntitlementInfo(
                    identifier: entitlementID,
                    isActive: true,
                    willRenew: true,
                    periodType: .trial,
                    store: .appStore,
                    productIdentifier: productID,
                    isSandbox: isSandbox,
                    ownershipType: .purchased
                )
            }
            .filter { !$0.isActiveInCurrentEnvironment }

        guard matches.count == 1, let match = matches.first else { return nil }

        return EntitlementInfos(entitlements: [entitlementID: match])
    }

    /// States the disagreement this host actually reproduces rather than asserting App Review's
    /// direction of it. A simulator reads itself as sandbox, so here the entitlement is the
    /// production one and the device is the sandbox one - the mirror of the reviewer's device, and
    /// the same disagreement `activeInCurrentEnvironment` refuses.
    static func environmentSubtitle(for entitlements: RevenueCat.EntitlementInfos) -> String {
        let entitlementEnvironment = entitlements.holdsSandboxEntitlement ? "sandbox" : "production"
        let deviceEnvironment = entitlements.holdsSandboxEntitlement ? "production" : "sandbox"

        return """
        One active, RevenueCat-verified app_access entitlement bought in \(entitlementEnvironment), \
        on a device the RevenueCat SDK reads as \(deviceEnvironment) - the disagreement App Review's \
        install produces - run through the shipped RevenueCatPurchaseExecutor under both readings.
        """
    }

    static func isPurchased(_ result: SuperwallKit.PurchaseResult) -> Bool {
        if case .purchased = result { return true }
        return false
    }

    /// Superwall renders the error it is handed verbatim in its purchase-failure alert, so this is
    /// the sentence on Apple's screenshot.
    static func failureAlertMessage(_ result: SuperwallKit.PurchaseResult) -> String? {
        guard case .failed(let error) = result else { return nil }

        return error.localizedDescription
    }

    /// One event from each surface the reviewer touched.
    static var diagnosticEvents: [PaywallAnalyticsEvent] {
        let context = RevenueCatPurchaseAnalyticsContext(
            placement: "app_access_gate",
            presentationID: nil
        )

        return [
            .revenueCatPurchaseCompleted(
                productID: productID,
                entitlementID: entitlementID,
                context: context
            ),
            .revenueCatPurchaseFailed(
                productID: productID,
                errorType: .noActiveEntitlement,
                attribution: .purchaseStarted(context)
            ),
            .revenueCatRestoreNotFound(
                entitlementID: entitlementID,
                context: .appAccessGate(gateAttemptID: "review-gate"),
                identityMatches: true
            )
        ]
    }

    static func describe(_ name: String, _ parameters: [String: TelemetryValue]) -> String {
        let rendered = parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(describe($0.value))" }
            .joined(separator: " ")

        return name.padding(toLength: max(name.count, 28), withPad: " ", startingAt: 0) + " " + rendered
    }

    static func describe(_ record: EnvelopedTelemetryRecord) -> String {
        describe(record.name, record.parameters)
    }

    static func describe(_ record: TelemetryRecord) -> String {
        describe(record.name, record.parameters)
    }

    static func describe(_ value: TelemetryValue) -> String {
        switch value {
        case .string(let string): return string
        case .bool(let bool): return String(bool)
        case .int(let int): return String(int)
        case .double(let double): return String(double)
        }
    }
}

// MARK: - Capture

private extension AppReviewSandboxEntitlementEvidenceTests {
    static var evidenceDirectory: URL {
        URL(
            filePath: ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
                ?? NSTemporaryDirectory()
        )
    }

    static func write(_ proof: some View, named name: String) throws {
        let renderer = ImageRenderer(content: proof)
        renderer.scale = 2

        let image = try #require(renderer.uiImage, "ImageRenderer produced no image")
        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        let url = evidenceDirectory.appending(path: "\(name).png")
        try png.write(to: url)

        #expect(png.count > 5_000)
        print("ASCEND_EVIDENCE_FILE: \(url.path())")
    }

    /// An alert is a UIKit presentation rather than a subview, so it is photographed off a live
    /// window. `message: nil` presents nothing, which is precisely the "after" surface: a reviewer
    /// who buys today is shown no alert at all.
    static func captureAlert(message: String?) async throws -> UIImage {
        let bounds = CGRect(x: 0, y: 0, width: 393, height: 852)
        let window = UIWindow(frame: bounds)
        window.windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        window.rootViewController = UIHostingController(rootView: PurchaseAlertHost(message: message))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }

        if message != nil {
            for _ in 0..<120 {
                try await Task.sleep(for: .milliseconds(20))
                if window.rootViewController?.presentedViewController != nil { break }
            }

            try #require(
                window.rootViewController?.presentedViewController != nil,
                "The purchase-failure alert never presented"
            )
        }

        // Presented is not drawn: the alert fades and scales in, and a mid-animation capture
        // photographs a ghost of the copy rather than the copy.
        try await Task.sleep(for: .milliseconds(900))

        let band = CGRect(x: 0, y: bounds.midY - 190, width: bounds.width, height: 380)
        return UIGraphicsImageRenderer(size: band.size).image { _ in
            window.drawHierarchy(
                in: CGRect(origin: CGPoint(x: 0, y: -band.minY), size: bounds.size),
                afterScreenUpdates: true
            )
        }
    }
}

// MARK: - Views

/// A stand-in for the paywall behind Superwall's purchase-failure alert. The alert is a translucent
/// system material, so photographing it over pure black would render it black on black.
private struct PurchaseAlertHost: View {
    @State private var message: String?

    init(message: String?) {
        _message = State(initialValue: message)
    }

    var body: some View {
        Color(white: 0.22)
            .ignoresSafeArea()
            .alert(
                "An error occurred",
                isPresented: .constant(message != nil),
                presenting: message
            ) { _ in
                Button("OK") {}
            } message: { message in
                Text(message)
            }
    }
}

private struct EventList: View {
    let events: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(events, id: \.self) { event in
                Text(event)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

private struct ProofColumn<Content: View>: View {
    let caption: String
    let detail: String
    let events: [String]
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(caption.uppercased())
                .font(.montserratSemiBold(size: 11))
                .foregroundStyle(Color.ascendAccent.opacity(0.9))

            content

            Text(detail)
                .font(.montserratMedium(size: 12))
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            EventList(events: events)
        }
        .padding(16)
        .frame(width: 372, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.05))
        )
    }
}

private struct ProofSheet<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.montserratMedium(size: 13))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 16) { content }
        }
        .padding(28)
        .frame(width: 828, alignment: .topLeading)
        .background(Color.black)
    }
}

private struct PurchaseAlertProof: View {
    let subtitle: String
    let before: UIImage
    let beforeCaption: String
    let beforeDetail: String
    let beforeEvents: [String]
    let after: UIImage
    let afterCaption: String
    let afterDetail: String
    let afterEvents: [String]

    var body: some View {
        ProofSheet(
            title: "App Review buys app_access · what the reviewer sees",
            subtitle: subtitle
        ) {
            ProofColumn(caption: beforeCaption, detail: beforeDetail, events: beforeEvents) {
                shot(before)
            }
            ProofColumn(caption: afterCaption, detail: afterDetail, events: afterEvents) {
                shot(after)
            }
        }
    }

    private func shot(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 340)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct GateRestoreProof: View {
    struct Column {
        let caption: String
        let detail: String
        let state: AppAccessRestoreState
        let events: [String]
    }

    let monetizationManager: MonetizationManager
    let before: Column
    let after: Column

    var body: some View {
        ProofSheet(
            title: "App Review taps Restore Purchases · what the reviewer sees",
            subtitle: "The real AppAccessPaywallPlaceholderView, seeded with the AppAccessRestoreState the shipped AppAccessRestoreService returned for the same entitlement under each reading."
        ) {
            column(before)
            column(after)
        }
    }

    private func column(_ column: Column) -> some View {
        ProofColumn(caption: column.caption, detail: column.detail, events: column.events) {
            AppAccessPaywallPlaceholderView(
                initialPhase: .failed,
                initialRestoreState: column.state,
                onDeleteAccount: {}
            )
            .environment(monetizationManager)
            .frame(width: 340, height: 520)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

@MainActor
private final class RestorerStub: PurchaseRestoring {
    let isRevenueCatConfigured = true
    let identityGeneration: MonetizationIdentityTransition? = MonetizationIdentityTransition(
        revision: 1,
        userID: "sandbox-evidence-user"
    )
    private let state: MonetizationEntitlementState

    init(state: MonetizationEntitlementState) {
        self.state = state
    }

    func restorePurchases() async throws -> MonetizationEntitlementState {
        state
    }
}
