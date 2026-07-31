import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for the app-access gate, cited by
/// `docs/quality/contracts/returning-subscriber.md` as the AC-6 artifact.
///
/// This renders the real `AppAccessPaywallPlaceholderView` - not a copy of its markup - through
/// `ImageRenderer`, with a `MonetizationManager` built from the shared `EntitlementServiceStub` and
/// `PaywallPresenterSpy` doubles. Each row seeds one presentation state the view can actually be in,
/// so the PNG cannot drift from the shipped surface.
///
/// `ImageRenderer` does run the view's `onAppear`, so the only row that reaches the automatic
/// hand-off is the seeded `.presenting` one, and its registration lands on `PaywallPresenterSpy`,
/// which never presents anything. Every other row renders the state it was seeded with.
///
/// Each row is the user-visible surface for one real Superwall outcome:
///   presenting   -> cold-start hand-off, paywall opening
///   presented    -> hosted paywall covering the gate
///   ready        -> purchase or restore succeeded
///   readyToRetry -> dismissed without purchase or onSkip
///   failed       -> configuration failure or onError
/// The first two draw the neutral loading surface with no lock wall, no "Access Required" headline,
/// and no control at all - so there is nothing visible the user cannot press. The last three draw
/// the recovery stack, where every control is enabled.
@MainActor
struct AppAccessPaywallPlaceholderSnapshotTests {
    @Test
    func rendersEveryGateStateFromTheRealView() throws {
        let manager = MonetizationManager(
            entitlementService: EntitlementServiceStub(),
            paywallPresenter: PaywallPresenterSpy()
        )
        let renderer = ImageRenderer(content: AppAccessGateStatesProof(monetizationManager: manager))
        renderer.scale = 2

        let image = try #require(renderer.uiImage, "ImageRenderer produced no image")
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: "app-access-paywall-fallback-states.png")
        try png.write(to: url)

        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
        #expect(png.count > 5_000)
    }

    @Test
    func theHandOffStatesDrawNoControls() {
        #expect(AppAccessPaywallPresentationState.presenting.showsRecoveryActions == false)
        #expect(AppAccessPaywallPresentationState.presented.showsRecoveryActions == false)
        #expect(
            gateScenarios.map(\.state)
                == [.presenting, .presented, .ready, .readyToRetry, .failed]
        )
    }
}

/// The outcome that lands the gate in each state, paired with the real state value.
private struct GateScenario: Identifiable {
    let id: String
    let outcome: String
    let state: AppAccessPaywallPresentationState
}

private let gateScenarios: [GateScenario] = [
    .init(id: "presenting", outcome: "Cold-start hand-off · paywall opening", state: .presenting),
    .init(id: "presented", outcome: "Hosted paywall covering the gate", state: .presented),
    .init(id: "ready", outcome: "Purchase or restore succeeded", state: .ready),
    .init(id: "retry", outcome: "Dismissed without purchase · onSkip", state: .readyToRetry),
    .init(id: "failed", outcome: "Configuration failure · onError", state: .failed)
]

private struct AppAccessGateStatesProof: View {
    let monetizationManager: MonetizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("App access gate · every presentation state")
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(gateScenarios) { scenario in
                VStack(alignment: .leading, spacing: 10) {
                    Text(scenario.outcome.uppercased())
                        .font(.montserratSemiBold(size: 11))
                        .foregroundStyle(Color.ascendAccent.opacity(0.9))

                    AppAccessPaywallPlaceholderView(
                        initialPresentationState: scenario.state
                    )
                    .environment(monetizationManager)
                    .frame(width: 340, height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white.opacity(0.05))
                )
            }
        }
        .padding(28)
        .frame(width: 428)
        .background(Color.black)
    }
}
