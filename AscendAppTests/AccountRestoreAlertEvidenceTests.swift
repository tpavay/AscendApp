import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Pixel evidence for the second restore surface: the alert account settings raises when the
/// climber taps Restore Purchases.
///
/// `AccountView` owns its `RestorePurchasesViewModel` in a private `@State`, so the shipped screen
/// cannot be seeded into a restore outcome from a test. What decides every pixel in that alert is
/// the production `RestorePurchasesViewModel.Result`, so this hosts the same `.alert(item:)`
/// presentation `AccountView` applies, seeded with each real `Result`, in a live `UIWindow` and
/// photographs what iOS actually draws. `theAlertProofReadsItsCopyFromProduction` pins the rendered
/// strings back to the production type so this proof cannot drift into its own copy.
@MainActor
struct AccountRestoreAlertEvidenceTests {
    @Test
    func rendersTheAccountRestoreAlertForEveryOutcome() throws {
        let shots = try Self.outcomes.map { outcome in
            (outcome, try Self.captureAlert(for: outcome.result))
        }

        let sheet = ImageRenderer(
            content: AccountRestoreAlertProof(
                shots: shots.map { .init(id: $0.0.id, caption: $0.0.caption, image: $0.1) }
            )
        )
        sheet.scale = 2

        let image = try #require(sheet.uiImage, "ImageRenderer produced no image")
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        try png.write(to: URL(filePath: directory).appending(path: "account-settings-restore-alerts.png"))

        #expect(png.count > 5_000)
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

    /// Presents the alert in a live window and photographs the screen, because an alert is a UIKit
    /// presentation rather than a subview - `ImageRenderer` alone would draw the empty screen behind it.
    static func captureAlert(for result: RestorePurchasesViewModel.Result) throws -> UIImage {
        let bounds = CGRect(x: 0, y: 0, width: 393, height: 852)
        let window = UIWindow(frame: bounds)
        window.windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        window.rootViewController = UIHostingController(
            rootView: AccountRestoreAlertHost(result: result)
        )
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        // The presentation is driven by SwiftUI's state pipeline, so the run loop has to turn before
        // the alert exists. Stop as soon as it is on screen rather than sleeping a fixed budget.
        for _ in 0..<80 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            if window.rootViewController?.presentedViewController != nil { break }
        }

        try #require(
            window.rootViewController?.presentedViewController != nil,
            "The restore alert never presented"
        )

        // Presented is not yet drawn: the alert fades and scales in, and photographing mid-animation
        // would produce a ghost of the copy rather than the copy. Let the transition settle first.
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))

        // The alert is centred in the window, so the proof frames the band around it rather than
        // a phone-height picture that is mostly empty backdrop.
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

private struct AlertShot: Identifiable {
    let id: String
    let caption: String
    let image: UIImage
}

private struct AccountRestoreAlertProof: View {
    let shots: [AlertShot]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Account settings · restore alert per outcome")
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)

            HStack(alignment: .top, spacing: 16) {
                ForEach(shots) { shot in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(shot.caption.uppercased())
                            .font(.montserratSemiBold(size: 10))
                            .foregroundStyle(Color.ascendAccent.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Image(uiImage: shot.image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(14)
                    .frame(width: 328)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.white.opacity(0.05))
                    )
                }
            }
        }
        .padding(28)
        .background(Color.black)
    }
}
