import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for the Superwall app-access handoff states.
///
/// The live `AppAccessPaywallPlaceholderView` depends on a `MonetizationManager`
/// environment and `ImageRenderer` cannot flatten the live Firebase-auth-gated
/// screen. This proof renders the same neutral loading state and recovery actions
/// to a single PNG a reviewer can inspect.
///
/// The loading state has no button or access-denied message. Recovery states retain
/// actionable retry and Restore Purchases controls after a Superwall outcome.
@MainActor
struct AppAccessPaywallPlaceholderSnapshotTests {
    @Test
    func rendersNeutralLoadingAndActionableRecoveryStates() throws {
        let renderer = ImageRenderer(content: AppAccessHandoffProof())
        renderer.scale = 3

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
}

/// The outcome that lands the gate in each state, paired with the real state value.
private struct FallbackScenario: Identifiable {
    let id: String
    let outcome: String
    let state: AppAccessPaywallPresentationState
}

private let fallbackScenarios: [FallbackScenario] = [
    .init(id: "ready", outcome: "First presentation or restored", state: .ready),
    .init(id: "retry", outcome: "Dismissed without purchase", state: .readyToRetry),
    .init(id: "failed", outcome: "Configuration failure", state: .failed),
]

private struct AppAccessHandoffProof: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("App access handoff")
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)

            loadingState

            ForEach(fallbackScenarios) { scenario in
                VStack(alignment: .leading, spacing: 10) {
                    Text(scenario.outcome.uppercased())
                        .font(.montserratSemiBold(size: 11))
                        .foregroundStyle(Color.ascendAccent.opacity(0.9))

                    actionStack(for: scenario.state)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.05))
                )
            }
        }
        .padding(28)
        .frame(width: 380)
        .background(Color.black)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            Image("AppIconInternalAccent")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)

            Text("Preparing your climb field")
                .font(.montserratBold(size: 22))
                .foregroundStyle(.white)

            Text("Checking your access...")
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.white.opacity(0.68))

            ProgressView()
                .tint(Color.ascendAccent)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.05))
        )
    }

    private func actionStack(for state: AppAccessPaywallPresentationState) -> some View {
        VStack(spacing: 12) {
            Text(state.primaryButtonTitle)
                .font(.montserratBold(size: 16))
                .foregroundStyle(.black.opacity(0.9))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.ascendAccent)
                )

            if let statusMessage = state.statusMessage {
                Text(statusMessage)
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(AppAccessRestoreState.idle.buttonTitle(isRevenueCatConfigured: true))
                .font(.montserratSemiBold(size: 15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                )
        }
    }
}
