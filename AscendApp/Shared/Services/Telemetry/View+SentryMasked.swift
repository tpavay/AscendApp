import SwiftUI

extension View {
    /// Paints this subtree out of every Sentry crash screenshot.
    ///
    /// Reach for it whenever a surface renders health data, identity, or user
    /// media in a way the SDK's own text and image masking cannot see -
    /// Swift Charts marks and axis labels, `Canvas` and `Shape` drawing that
    /// encodes a measurement, and `AVPlayerLayer`-backed video. Plain `Text` and
    /// `Image` need nothing: `SentryMaskingEvidenceTests` proves the SDK
    /// already covers those.
    func sentryMasked() -> some View {
        overlay {
            SentryMaskedRegion()
                .padding(-sentryMaskBleed)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// How far the mask reaches past the surface it covers.
///
/// A layout frame is not a drawing bound. Swift Charts strokes its marks with a
/// round cap, so the first and last point of a trend line paint about a point
/// outside the chart's own frame; a mask sized exactly to that frame left one
/// column of the climber's trace showing at each edge, which is enough to read
/// the first and last plotted value off a masked screenshot. Shadows and glows
/// overflow the same way.
///
/// Covering a hair more than the surface costs nothing: the marker refuses every
/// touch that lands on it whatever its size, which
/// `SentryMaskInteractionTests` holds to, and `SentryMaskingEvidenceTests` is
/// what noticed the gap in the first place.
private let sentryMaskBleed: CGFloat = 4

/// Places a `SentryMaskedRegionView` over the modified subtree.
private struct SentryMaskedRegion: UIViewRepresentable {
    func makeUIView(context: Context) -> SentryMaskedRegionView {
        SentryMaskedRegionView()
    }

    func updateUIView(_ uiView: SentryMaskedRegionView, context: Context) {}
}
