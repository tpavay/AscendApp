import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for the entitlement-resolution wait, cited by
/// `docs/quality/contracts/returning-subscriber.md` for the loading row of the state matrix and AC-9.
///
/// This hosts the real `AppAccessResolvingView` - not a copy of its markup - through
/// `RenderedScreen`, driven by a `MonetizationManager` built on the shared `EntitlementServiceStub`
/// and `PaywallPresenterSpy` doubles, and photographs it only when `ASCEND_EVIDENCE_DIR` is set.
/// It is hosted in a window rather than drawn off screen because the wait is the system spinner,
/// which an off-screen renderer replaces with a placeholder glyph.
/// Both rows are seeded through the shipped identity transition API, so what the PNG shows is
/// what the routing layer can actually put on screen:
///   waiting  -> `prepareIdentity` has published `.unknown` and the answer is still outstanding
///   stalled  -> the matching identify resolved without an answer, so recovery takes over
@MainActor
@Suite(.serialized, .hostsAWindow)
struct AppAccessResolvingSnapshotTests {
    @Test
    func rendersTheWaitAndRecoverySurfacesFromTheRealView() async throws {
        let waiting = makeManager()
        waiting.prepareIdentity(.climber("returning-subscriber"))

        let stalled = makeManager(identityResolution: .unknown)
        let transition = stalled.prepareIdentity(.climber("returning-subscriber"))
        await stalled.identify(.climber("returning-subscriber"), transition: transition)

        #expect(waiting.entitlementState == .unknown)
        #expect(waiting.hasFailedIdentityResolution == false)
        #expect(stalled.hasFailedIdentityResolution)

        let proof = AppAccessResolvingStatesProof(waiting: waiting, stalled: stalled)
        try await RenderedScreen.host(proof, size: CGSize(width: 428, height: 1_130)) { screen in
            // The wait is the same spinner the gate draws, with no words of its own.
            #expect(
                await gateWaitUntil(timeout: .seconds(10)) { screen.isGateSpinnerMounted },
                "The wait never drew the system spinner"
            )
            let copy = try await screen.copy { $0.contains("access check stalled") }
            #expect(copy.contains("access check stalled"))
            #expect(copy.contains("try again"))
            #expect(copy.contains("sign out"))
            #expect(!copy.contains("checking your access"))
            try screen.photograph(named: "app-access-resolving-states", scale: 2)
        }
    }
}

@MainActor
private func makeManager(
    identityResolution: MonetizationEntitlementState = .inactive
) -> MonetizationManager {
    let entitlementService = EntitlementServiceStub()
    entitlementService.identityResolution = identityResolution

    return MonetizationManager(
        entitlementService: entitlementService,
        paywallPresenter: PaywallPresenterSpy(),
        telemetry: makeTestTelemetry(sink: InMemoryTelemetrySink(destination: .analytics))
    )
}

private struct AppAccessResolvingStatesProof: View {
    let waiting: MonetizationManager
    let stalled: MonetizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Entitlement resolution · what a returning subscriber waits on")
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            surface(
                caption: "Identity outstanding · unknown entitlement",
                manager: waiting
            )

            surface(
                caption: "Resolution never answered · caller-driven recovery",
                manager: stalled
            )
        }
        .padding(28)
        .frame(width: 428)
        .background(Color.black)
    }

    private func surface(caption: String, manager: MonetizationManager) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(caption.uppercased())
                .font(.montserratSemiBold(size: 11))
                .foregroundStyle(Color.ascendAccent.opacity(0.9))

            AppAccessResolvingView(onSignOut: {})
                .environment(manager)
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
