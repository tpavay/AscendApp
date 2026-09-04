import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Evidence for the second restore surface: the alert account settings raises when the climber
/// taps Restore Purchases.
///
/// `AccountView` owns its `RestorePurchasesViewModel` in a private `@State`, so the shipped screen
/// cannot be seeded into a restore outcome from a test. What decides every word in that alert is
/// the production `RestorePurchasesViewModel.Result`, so this hosts the same `.alert(item:)`
/// presentation `AccountView` applies, seeded with each real `Result`, in a live window through
/// `RenderedScreen`, reads the presented alert's title and message back off UIKit, and photographs
/// what iOS draws when `ASCEND_EVIDENCE_DIR` is set. `theAlertProofReadsItsCopyFromProduction` pins
/// the strings back to the production type so this proof cannot drift into its own copy.
@MainActor
@Suite(.hostsAWindow)
struct AccountRestoreAlertEvidenceTests {
    @Test
    func rendersTheAccountRestoreAlertForEveryOutcome() async throws {
        for outcome in Self.outcomes {
            try await Self.hostingAlert(for: outcome)
        }
    }

    /// Every word the alert draws comes from the production result type - the proof supplies no copy
    /// of its own, so a wording change in the app is a wording change in this evidence.
    @Test
    func theAlertProofReadsItsCopyFromProduction() {
        #expect(Self.outcomes.map(\.result) == [.restored, .noPurchasesFound, .failed])
        #expect(
            RestorePurchasesViewModel.Result.noPurchasesFound.title
                == "No active Ascend subscription was found for this Apple ID."
        )
        #expect(RestorePurchasesViewModel.Result.noPurchasesFound.message == nil)
        #expect(RestorePurchasesViewModel.Result.failed.title == "Restore Failed")
        #expect(
            RestorePurchasesViewModel.Result.failed.message
                == "Ascend couldn't restore your purchases. Check your connection and try again."
        )
    }
}

// MARK: - Outcomes

private extension AccountRestoreAlertEvidenceTests {
    struct Outcome {
        let id: String
        let caption: String
        let result: RestorePurchasesViewModel.Result
    }

    static let outcomes: [Outcome] = [
        .init(
            id: "restored",
            caption: "app_access restored · revenuecat_restore_completed",
            result: .restored
        ),
        .init(
            id: "notFound",
            caption: "Conclusive negative · revenuecat_restore_not_found",
            result: .noPurchasesFound
        ),
        .init(
            id: "failed",
            caption: "Unresolved · revenuecat_restore_failed",
            result: .failed
        )
    ]

    /// Presents the alert in a live window, because an alert is a UIKit presentation rather than a
    /// subview - laid out off screen, only the empty screen behind it would exist. The presented
    /// `UIAlertController` is the fact read back: its title and message are what iOS draws.
    static func hostingAlert(for outcome: Outcome) async throws {
        let controller = UIHostingController(rootView: AccountRestoreAlertHost(result: outcome.result))

        try await RenderedScreen.host(
            controller,
            size: CGSize(width: 393, height: 852),
            // The presentation is driven by SwiftUI's state pipeline, so the run loop has to turn
            // before the alert exists. Stop as soon as it is on screen rather than sleeping a budget.
            settle: .until { _ in controller.presentedViewController != nil }
        ) { screen in
            let presented = try #require(
                controller.presentedViewController,
                "The restore alert never presented"
            )
            let alert = try #require(
                presented as? UIAlertController,
                "SwiftUI's alert presents a UIAlertController; \(type(of: presented)) presented instead"
            )
            #expect(alert.title == outcome.result.title)
            #expect(alert.message == outcome.result.message)

            // Presented is not yet drawn: the alert fades and scales in, and photographing
            // mid-animation would produce a ghost of the copy rather than the copy. Only a run that
            // keeps the photograph waits for the transition to settle.
            if RenderedScreen.isPhotographing {
                try await screen.settle(.turns(18))
                try screen.photograph(named: "account-settings-restore-alert-\(outcome.id)")
            }
        }
    }
}

// MARK: - Views

/// The same `.alert(item:)` presentation `AccountView` applies to its restore result.
private struct AccountRestoreAlertHost: View {
    @State private var result: RestorePurchasesViewModel.Result?

    init(result: RestorePurchasesViewModel.Result) {
        _result = State(initialValue: result)
    }

    var body: some View {
        // A stand-in for the Settings screen behind the alert. The alert itself is a translucent
        // system material, so photographing it over pure black would render it as black on black.
        Color(white: 0.22)
            .ignoresSafeArea()
            .alert(item: $result) { result in
                Alert(
                    title: Text(result.title),
                    message: result.message.map { Text($0) },
                    dismissButton: .default(Text("Done"))
                )
            }
    }
}
