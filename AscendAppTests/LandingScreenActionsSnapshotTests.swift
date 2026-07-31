import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for AC-1 of `docs/quality/contracts/returning-subscriber.md`: the signed-out
/// welcome screen carries a direct route back to authentication.
///
/// This renders the real `LandingScreen` through `ImageRenderer` at the default text size and at the
/// largest accessibility size, because the returning-user row shares the bottom safe-area inset with
/// GET STARTED and the two must not collide when the text grows.
@MainActor
struct LandingScreenActionsSnapshotTests {
    @Test
    func rendersTheReturningUserActionAtDefaultAndAccessibilityTextSizes() throws {
        let renderer = ImageRenderer(content: LandingScreenActionsProof())
        renderer.scale = 2

        let image = try #require(renderer.uiImage, "ImageRenderer produced no image")
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: "welcome-sign-in-affordance-type-sizes.png")
        try png.write(to: url)

        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
        #expect(png.count > 5_000)
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

                    // Rendered without a NavigationStack: `ImageRenderer` cannot draw one, and the
                    // screen's own layout - not its navigation - is what this evidence is about.
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
