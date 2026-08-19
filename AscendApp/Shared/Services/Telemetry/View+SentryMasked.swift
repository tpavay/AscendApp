import SwiftUI

extension View {
    /// Paints this subtree out of every Sentry screenshot and session replay
    /// frame.
    ///
    /// Reach for it whenever a surface renders health data, identity, or user
    /// media in a way the SDK's own text and image masking cannot see -
    /// Swift Charts marks and axis labels, `Canvas` and `Shape` drawing that
    /// encodes a measurement, and `AVPlayerLayer`-backed video. Plain `Text` and
    /// `Image` need nothing: `SentryReplayMaskingEvidenceTests` proves the SDK
    /// already covers those.
    func sentryMasked() -> some View {
        overlay {
            SentryMaskedRegion()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Places a `SentryMaskedRegionView` over the modified subtree.
private struct SentryMaskedRegion: UIViewRepresentable {
    func makeUIView(context: Context) -> SentryMaskedRegionView {
        SentryMaskedRegionView()
    }

    func updateUIView(_ uiView: SentryMaskedRegionView, context: Context) {}
}
