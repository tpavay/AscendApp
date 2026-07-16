import SwiftUI

struct OnboardingValueImageBackground: View {
    let imageName: String
    var dimmingOpacity: Double = 0.24
    var topReadabilityOpacity: Double = 0.55

    var body: some View {
        GeometryReader { geometry in
            imageLayer(in: geometry)
        }
        .ignoresSafeArea()
    }

    private func imageLayer(in geometry: GeometryProxy) -> some View {
        Image(imageName)
            .resizable()
            .scaledToFill()
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .overlay {
                Color.black.opacity(dimmingOpacity)
            }
            .overlay {
                vignette(in: geometry)
            }
            .overlay {
                readabilityGradient
            }
            .overlay {
                OnboardingValueNoiseOverlay()
                    .opacity(0.36)
            }
    }

    private func vignette(in geometry: GeometryProxy) -> some View {
        RadialGradient(
            colors: [
                .clear,
                Color.black.opacity(0.5)
            ],
            center: .center,
            startRadius: geometry.size.width * 0.28,
            endRadius: geometry.size.height * 0.68
        )
    }

    private var readabilityGradient: some View {
        LinearGradient(
            stops: [
                .init(color: Color.black.opacity(topReadabilityOpacity), location: 0),
                .init(color: .clear, location: 0.24),
                .init(color: Color.black.opacity(0.34), location: 0.58),
                .init(color: Color.black.opacity(0.92), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct OnboardingValueNoiseOverlay: View {
    private let dotCount = 120

    var body: some View {
        Canvas { context, size in
            for index in 0..<dotCount {
                let x = size.width * normalized(index * 37 + 11)
                let y = size.height * normalized(index * 61 + 19)
                let side = CGFloat(index % 3 == 0 ? 1.1 : 0.7)
                let opacity = 0.035 + Double(index % 5) * 0.006
                let rect = CGRect(x: x, y: y, width: side, height: side)

                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(.white.opacity(opacity))
                )
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    private func normalized(_ value: Int) -> CGFloat {
        CGFloat(value % 101) / 100
    }
}
