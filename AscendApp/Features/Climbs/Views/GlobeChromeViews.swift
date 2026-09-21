import SwiftUI

/// The dark gradients that keep chrome legible at the top and bottom of the globe.
struct GlobeEdgeOverlays: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.94),
                    Color.black.opacity(0.58),
                    Color.black.opacity(0.16),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 188)

            Spacer()

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.42), Color.black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 176)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// A round control drawn over the globe: back, help, start.
struct GlobeControlButton: View {
    let systemName: String
    let accessibilityLabel: String
    var fill: Color = Color.black.opacity(0.46)
    var foreground: Color = .white.opacity(0.94)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(fill)
                )
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.36), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// What the globe says while the catalog is loading or could not load.
struct ClimbCatalogStateOverlay: View {
    let loadErrorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            if let loadErrorMessage {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Text("Climbs Unavailable")
                    .font(.montserratSemiBold(size: 18))
                    .foregroundStyle(.white)

                Text(loadErrorMessage)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.05)

                Text("Loading climbs...")
                    .font(.montserratSemiBold(size: 17))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.52))
        )
        .padding(.horizontal, 24)
    }
}
