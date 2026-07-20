import SwiftUI
import Testing
import UIKit
@testable import AscendApp

@MainActor
struct LiveHeartRateStatusChipSnapshotTests {
    @Test("Live header renders every chest-strap state")
    func rendersEveryStatus() throws {
        let renderer = ImageRenderer(content: statusProof)
        renderer.scale = 3

        let image = try #require(renderer.uiImage, "ImageRenderer produced no image")
        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        let url = URL(filePath: NSTemporaryDirectory())
            .appending(path: "live-heart-rate-statuses.png")
        try png.write(to: url)

        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
        #expect(png.count > 5_000)
    }

    private var statusProof: some View {
        VStack(alignment: .trailing, spacing: 12) {
            LiveHeartRateStatusChip(status: .connecting)
            LiveHeartRateStatusChip(
                status: .connected(beatsPerMinute: 148, zone: .aerobic)
            )
            LiveHeartRateStatusChip(status: .signalLost)
            LiveHeartRateStatusChip(status: .failed)
        }
        .padding(24)
        .frame(width: 220, alignment: .trailing)
        .background(Color.black)
    }
}
