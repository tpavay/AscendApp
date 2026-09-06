import SwiftUI
import Testing
import UIKit
@testable import AscendApp

@MainActor
struct LiveHeartRateStatusChipSnapshotTests {
    @Test("Live header renders every chest-strap state")
    func rendersEveryStatus() throws {
        // Laid out at 1x for the size facts; the 3x photograph is written only under
        // `ASCEND_EVIDENCE_DIR`.
        try RenderedScreen.withOffscreenPixels(of: statusProof) { pixels in
            #expect(pixels.size.width > 0)
            #expect(pixels.size.height > 0)
        }

        try RenderedScreen.photograph(statusProof, named: "live-heart-rate-statuses")
    }

    private var statusProof: some View {
        VStack(alignment: .trailing, spacing: 12) {
            LiveHeartRateStatusChip(status: .connecting)
            LiveHeartRateStatusChip(
                status: .connected(beatsPerMinute: 148, zone: .aerobic)
            )
            LiveHeartRateStatusChip(status: .reconnecting)
            LiveHeartRateStatusChip(status: .signalLost)
            LiveHeartRateStatusChip(status: .failed)
        }
        .padding(24)
        .frame(width: 220, alignment: .trailing)
        .background(Color.black)
    }
}
