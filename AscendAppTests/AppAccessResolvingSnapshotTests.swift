import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for the entitlement-resolution wait, cited by
/// `docs/quality/contracts/returning-subscriber.md` for the loading row of the state matrix and AC-9.
///
/// This lays out the real `AppAccessResolvingView` - not a copy of its markup - off screen through
/// `RenderedScreen`, driven by a `MonetizationManager` built on the shared `EntitlementServiceStub`
/// and `PaywallPresenterSpy` doubles, and photographs it only when `ASCEND_EVIDENCE_DIR` is set.
/// Both rows are seeded through the shipped identity transition API, so what the PNG shows is
/// what the routing layer can actually put on screen:
///   waiting  -> `prepareIdentity` has published `.unknown` and the answer is still outstanding
///   stalled  -> the matching identify resolved without an answer, so recovery takes over
@MainActor
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
        // A size is a 1x fact; the bitmap is released before the photograph is considered.
        try RenderedScreen.withOffscreenPixels(of: proof) { pixels in
            #expect(pixels.size.width > 0)
            #expect(pixels.size.height > 0)
        }
        try RenderedScreen.photograph(proof, named: "app-access-resolving-states", scale: 2)
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
