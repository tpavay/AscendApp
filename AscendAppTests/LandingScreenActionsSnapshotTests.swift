import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for AC-1 of `docs/quality/contracts/returning-subscriber.md`: the signed-out
/// welcome screen carries a direct route back to authentication.
///
/// This lays out the real `LandingScreen` off screen through `RenderedScreen` at the default text
/// size and at the largest accessibility size, because the returning-user row shares the bottom
/// safe-area inset with GET STARTED and the two must not collide when the text grows. The proof
/// sheet is photographed only when `ASCEND_EVIDENCE_DIR` is set.
@MainActor
struct LandingScreenActionsSnapshotTests {
    @Test
    func rendersTheReturningUserActionAtDefaultAndAccessibilityTextSizes() throws {
        let proof = LandingScreenActionsProof()
        // A size is a 1x fact; the bitmap is released before the photograph is considered.
        try RenderedScreen.withOffscreenPixels(of: proof) { pixels in
            #expect(pixels.size.width > 0)
            #expect(pixels.size.height > 0)
        }
        try RenderedScreen.photograph(proof, named: "welcome-sign-in-affordance-type-sizes", scale: 2)
    }
}

private let renderedTypeSizes: [(caption: String, size: DynamicTypeSize)] = [
    ("Default text size", .large),
    ("Accessibility XXXL", .accessibility5)
]

private struct LandingScreenActionsProof: View {
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(renderedTypeSizes, id: \.caption) { entry in
                VStack(alignment: .leading, spacing: 10) {
                    Text(entry.caption.uppercased())
                        .font(.montserratSemiBold(size: 11))
                        .foregroundStyle(Color.ascendAccent.opacity(0.9))

                    // Laid out without a NavigationStack: an offscreen render cannot draw one, and
                    // the screen's own layout - not its navigation - is what this evidence is about.
                    LandingScreen()
                        .dynamicTypeSize(entry.size)
                        .frame(width: 390, height: 844)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .padding(28)
        .background(Color.black)
    }
}
