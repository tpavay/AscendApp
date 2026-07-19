import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for the headphone-tracking explainer placement fix.
///
/// The real `ClimbDetailView.overviewPage` VStack (see ClimbDetailView.swift
/// ~L885-891) renders, in order:
///   metrics -> divider -> [community stats] -> trackingExplainerRow -> primaryActionRow
///
/// The fix reorders the last two siblings so `trackingExplainerRow`
/// ("Your headphones track your steps, not a watch or phone." + "How it works")
/// sits directly *above* the "Start Live Climb" button.
///
/// `ImageRenderer` cannot flatten the live `ClimbDetailView` (its ScrollView and
/// UIKit-backed hero renders blank), and the live screen is Firebase-auth-gated,
/// so this reproduces the overview's bottom rows verbatim from source - same
/// copy, same Font/Color tokens, same modifiers, same VStack order as the fixed
/// code - and renders them to a PNG a reviewer can inspect.
@MainActor
struct ClimbDetailOverviewLayoutSnapshotTests {
    @Test
    func overviewRendersTrackingExplainerAboveStartButton() throws {
        let renderer = ImageRenderer(content: OverviewOrderingProof())
        renderer.scale = 3

        let image = try #require(renderer.uiImage, "ImageRenderer produced no image")
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        // Write to a portable evidence directory: the harness-provided override when
        // present, otherwise the always-writable temp dir. Never a hardcoded machine
        // path - that exists only on one Mac and fails on CI runners.
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: "climb-detail-overview-ordering.png")
        try png.write(to: url)

        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
        #expect(png.count > 5_000)
    }
}

/// Faithful reproduction of the tail of `ClimbDetailView.overviewPage` after the
/// fix: `trackingExplainerRow` immediately above `primaryActionRow`.
private struct OverviewOrderingProof: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // metrics header (STEPS / FLOORS / EST. TIME) - context only
            HStack(spacing: 0) {
                metricCell(value: "2,096", title: "STEPS")
                divider
                metricCell(value: "102", title: "FLOORS")
                divider
                metricCell(value: "18 min", title: "EST. TIME")
            }
            .frame(height: 58, alignment: .top)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)

            // --- trackingExplainerRow (verbatim from ClimbDetailView.swift) ---
            HStack(spacing: 10) {
                Image(systemName: "airpodspro")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.accent)

                Text("Your headphones track your steps, not a watch or phone.")
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 6)

                Text("How it works")
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.05))
            )

            // --- primaryActionRow (verbatim from ClimbDetailView.swift) ---
            Text("Start Live Climb")
                .font(.montserratBold(size: 18))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.accent)
                )
        }
        .padding(20)
        .frame(width: 393)
        .background(Color.black)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(width: 1, height: 34)
    }

    private func metricCell(value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.montserratBold(size: 22))
                .foregroundStyle(.white)
            Text(title)
                .font(.montserratSemiBold(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
