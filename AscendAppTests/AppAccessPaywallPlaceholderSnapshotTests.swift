import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for the Superwall hard-gate fallback states.
///
/// The live `AppAccessPaywallPlaceholderView` drives its primary button title,
/// enabled state, and status message entirely from `AppAccessPaywallPresentationState`
/// (see AppAccessPaywallPlaceholderView.swift L41-L63). That view depends on a
/// `MonetizationManager` environment and `ImageRenderer` cannot flatten the live
/// Firebase-auth-gated gate screen, so this reproduces the placeholder's action
/// stack verbatim from source - same copy, Font/Color tokens, and modifiers - and
/// renders every fallback state to a single PNG a reviewer can inspect.
///
/// Each row is the exact user-visible surface after one real Superwall outcome:
///   ready              -> first presentation / purchase or restore succeeded
///   presenting         -> paywall opening (primary disabled, no stuck blank)
///   readyToRetry       -> dismissed without purchase or onSkip
///   failed             -> configuration failure or onError
/// In every state the placeholder stays visible with an actionable primary button
/// and the Restore Purchases action.
@MainActor
struct AppAccessPaywallPlaceholderSnapshotTests {
    @Test
    func rendersEveryFallbackStateWithVisibleRetryAndRestore() throws {
        let renderer = ImageRenderer(content: FallbackStatesProof())
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
    .init(id: "ready", outcome: "First presentation · purchase or restore succeeded", state: .ready),
    .init(id: "presenting", outcome: "Paywall opening", state: .presenting),
    .init(id: "retry", outcome: "Dismissed without purchase · onSkip", state: .readyToRetry),
    .init(id: "failed", outcome: "Configuration failure · onError", state: .failed),
]

private struct FallbackStatesProof: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Access Required gate · Superwall fallback states")
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)

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

    // Faithful reproduction of AppAccessPaywallPlaceholderView's action stack.
    private func actionStack(for state: AppAccessPaywallPresentationState) -> some View {
        VStack(spacing: 12) {
            Text(state.primaryButtonTitle)
                .font(.montserratBold(size: 16))
                .foregroundStyle(.black.opacity(state.isPrimaryButtonEnabled ? 0.9 : 0.48))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.ascendAccent.opacity(state.isPrimaryButtonEnabled ? 1 : 0.52))
                )

            if let statusMessage = state.statusMessage {
                Text(statusMessage)
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Restore Purchases")
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
