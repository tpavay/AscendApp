import SwiftUI

/// Ascend's own glyph for the Strava integration. Strava's marks appear only
/// where its guidelines allow them - the Connect button - never as an icon.
struct StravaIntegrationGlyph: View {
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Image(systemName: "arrow.up.forward.app.fill")
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(Color.ascendAccent)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.ascendAccent.opacity(0.14))
            )
            .accessibilityHidden(true)
    }
}
