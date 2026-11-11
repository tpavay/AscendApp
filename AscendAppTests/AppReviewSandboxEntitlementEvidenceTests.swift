import Foundation
import RevenueCat
import SuperwallKit
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Reviewer-facing evidence for the Guideline 2.1(b) rejection of build 2026081401 (#506).
///
/// `AppReviewSandboxEntitlementTests` holds the rule; this reproduces what App Review actually
/// looked at. One entitlement - the reviewer's: active, RevenueCat-verified, bought in whichever
/// StoreKit environment is *not* the one `BundleSandboxEnvironmentDetector` reads off this binary
/// - is run twice through the shipped `RevenueCatPurchaseExecutor` and `AppAccessRestoreService`:
/// once resolved with the deleted `Set(entitlements.activeInCurrentEnvironment.keys)` line, once
/// with the shipped `appAccessEntitlementState`. The purchase alert's copy and the restore alert's
/// are the ones those production calls and the shipped Superwall options returned, not strings
/// this file wrote. The photographs of both are taken through `RenderedScreen` only when
/// `ASCEND_EVIDENCE_DIR` is set.
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
        #expect(alertMessage == "Ascend couldn't confirm your purchase. Check your connection and try again.")
        #expect(rejected.events.contains("revenuecat_purchase_failed"))

        #expect(Self.isPurchased(shipped.result))
        #expect(Self.failureAlertMessage(shipped.result) == nil)
        #expect(shipped.events.contains("revenuecat_purchase_completed"))

        guard RenderedScreen.isPhotographing else { return }

        let subtitle = Self.environmentSubtitle(for: entitlements)
        try await Self.photographAlert(
            message: alertMessage,
            annotation: .init(
                subtitle: subtitle,
                caption: "Build 2026081401 · rejected",
                detail: "Superwall .failed → \(alertMessage)",
                events: rejected.events
            ),
            named: "app-review-purchase-alert-before"
        )
        try await Self.photographAlert(
            message: nil,
            annotation: .init(
                subtitle: subtitle,
                caption: "This build",
                detail: "Superwall .purchased → no alert presented, paywall dismisses, app unlocks",
                events: shipped.events
            ),
            named: "app-review-purchase-alert-after"
        )
    }

    /// The restore half: the reviewer's own workaround, which produced a second error.
    ///
    /// Restore lives on the hosted paywall, so this runs the paywall's own restore - the shipped
    /// `RevenueCatPurchaseController.restorePurchases()` - and reads the alert Superwall raises
    /// for a failed one out of the shipped options.
    @Test
    func photographsTheRestoreAlertTheReviewerWouldHaveHitNext() async throws {
        let entitlements = try #require(Self.crossEnvironmentEntitlements())

        let rejected = await Self.restore(resolving: Self.oldRuleState(for: entitlements))
        let shipped = await Self.restore(resolving: entitlements.appAccessEntitlementState)

        #expect(Self.isRestoreFailed(rejected.result))
        #expect(rejected.events.contains("revenuecat_restore_not_found"))
        let alert = Self.restoreFailedAlert
        #expect(alert.title == "Nothing Restored")
        #expect(alert.message.contains("no active subscription or Lifetime purchase"))

        #expect(Self.isRestored(shipped.result))
        #expect(shipped.events.contains("revenuecat_restore_completed"))

        guard RenderedScreen.isPhotographing else { return }

        let subtitle = Self.environmentSubtitle(for: entitlements)
        let heading = "App Review taps Restore on the paywall · what the reviewer sees"
        try await Self.photographAlert(
            heading: heading,
            alertTitle: alert.title,
            message: alert.message,
            annotation: .init(
                subtitle: subtitle,
                caption: "Build 2026081401 · rejected",
                detail: "Superwall .failed → its restore-failed alert",
                events: rejected.events
            ),
            named: "app-review-restore-alert-before"
        )
        try await Self.photographAlert(
            heading: heading,
            alertTitle: alert.title,
            message: nil,
            annotation: .init(
                subtitle: subtitle,
                caption: "This build",
                detail: "Superwall .restored → no alert presented, paywall dismisses, app unlocks",
                events: shipped.events
            ),
            named: "app-review-restore-alert-after"
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
            lines.append("  climber sees               \(Self.isRestored(restore.result) ? "no alert - paywall dismisses, app unlocks" : "\"\(Self.restoreFailedAlert.title)\" - \(Self.restoreFailedAlert.message)")")
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

        if let directory = RenderedScreen.evidenceDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "app-review-sandbox-entitlement-transcript.txt")
            try Data(transcript.utf8).write(to: url)
            print("ASCEND_EVIDENCE_FILE: \(url.path())")
        }

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
        let result: SuperwallKit.RestorationResult
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
        let identity = MonetizationIdentityTransition(
            revision: 1,
            userID: "sandbox-evidence-user"
        )
        let telemetry = makeTestTelemetry(sink: sink)
        telemetry.setUserId("sandbox-evidence-user")
        let executor = RevenueCatPurchaseExecutor(
            telemetry: telemetry,
            transactionContextStore: PaywallTransactionContextStore(),
            entitlementID: entitlementID,
            applySubscriptionStatus: { _ in },
            refreshEntitlementState: { .refreshed(state) },
            currentIdentityGeneration: { identity },
            adoptEntitlementState: { _, candidate in candidate == identity }
        )

        let result = await executor.executePurchase(productID: productID) {
            RevenueCatPurchaseExecutor.PurchaseResponse(userCancelled: false)
        }

        return PurchaseRun(result: result, records: sink.records)
    }

    static func restore(resolving state: MonetizationEntitlementState) async -> RestoreRun {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        telemetry.setUserId("sandbox-evidence-user")
        let service = AppAccessRestoreService(
            telemetry: telemetry,
            entitlementID: entitlementID,
            restorer: { RestorerStub(state: state) }
        )
        // The hosted paywall's Restore, exactly as Superwall calls it.
        let controller = RevenueCatPurchaseController(
            applySuperwallStatus: { _ in },
            restoreService: service,
            restoreAnalyticsContext: {
                .hostedPaywall(
                    placement: SuperwallPlacement.appAccessGate.rawValue,
                    presentationID: "review-presentation",
                    gateAttemptID: "review-gate"
                )
            },
            isPurchasesConfigured: { true }
        )

        return RestoreRun(result: await controller.restorePurchases(), records: sink.records)
    }

    /// The alert Superwall raises for every failed restore, read out of the options Ascend
    /// configures it with. Superwall discards the error it was handed, so this copy is the whole
    /// of what the reviewer was told.
    static var restoreFailedAlert: (title: String, message: String) {
        let options = SuperwallPaywallPresenter.makeOptions(
            configuration: MonetizationConfiguration(infoDictionary: [:])
        )
        return (options.paywalls.restoreFailed.title, options.paywalls.restoreFailed.message)
    }

    static func isRestored(_ result: SuperwallKit.RestorationResult) -> Bool {
        if case .restored = result { return true }
        return false
    }

    static func isRestoreFailed(_ result: SuperwallKit.RestorationResult) -> Bool {
        if case .failed = result { return true }
        return false
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
                context: .hostedPaywall(
                    placement: "app_access_gate",
                    presentationID: nil,
                    gateAttemptID: "review-gate"
                ),
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

// MARK: - Photographs

private extension AppReviewSandboxEntitlementEvidenceTests {
    /// An alert is a UIKit presentation rather than a subview, so it is photographed off a live
    /// window. `message: nil` presents nothing, which is precisely the "after" surface: a reviewer
    /// who buys today is shown no alert at all. Called only when this run keeps photographs.
    static func photographAlert(
        heading: String = "App Review buys app_access · what the reviewer sees",
        alertTitle: String = "An error occurred",
        message: String?,
        annotation: PurchaseAlertHost.Annotation,
        named name: String
    ) async throws {
        let controller = UIHostingController(
            rootView: PurchaseAlertHost(
                heading: heading,
                alertTitle: alertTitle,
                message: message,
                annotation: annotation
            )
        )

        try await RenderedScreen.host(
            controller,
            size: CGSize(width: 393, height: 852),
            settle: .until { _ in message == nil || controller.presentedViewController != nil }
        ) { screen in
            if message != nil {
                try #require(
                    controller.presentedViewController != nil,
                    "The alert never presented"
                )
            }

            // Presented is not drawn: the alert fades and scales in, and a mid-animation capture
            // photographs a ghost of the copy rather than the copy.
            try await screen.settle(.turns(18))
            try screen.photograph(named: name)
        }
    }
}

// MARK: - Views

/// A stand-in for the paywall behind one of Superwall's failure alerts, captioned with the run it
/// stands for so each photograph carries its own evidence. The backdrop is a mid grey: the alert
/// is a translucent system material, and over pure black it would render black on black.
private struct PurchaseAlertHost: View {
    struct Annotation {
        let subtitle: String
        let caption: String
        let detail: String
        let events: [String]
    }

    @State private var message: String?
    let heading: String
    let alertTitle: String
    let annotation: Annotation

    init(heading: String, alertTitle: String, message: String?, annotation: Annotation) {
        _message = State(initialValue: message)
        self.heading = heading
        self.alertTitle = alertTitle
        self.annotation = annotation
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(white: 0.22)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                Text(heading)
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(.white)

                Text(annotation.subtitle)
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                Text(annotation.caption.uppercased())
                    .font(.montserratSemiBold(size: 11))
                    .foregroundStyle(Color.ascendAccent.opacity(0.9))

                Text(annotation.detail)
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)

                EventList(events: annotation.events)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert(
            alertTitle,
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
