import SwiftUI

/// The app's one loading treatment for a value that is genuinely in flight: the surrounding label
/// and layout stay put, and only the value slot shimmers. Introduced by the head-to-head comparison
/// surface; shared so every "label visible, value loading" moment reads the same.
enum AscendSkeletonStyle {
    static let fill = Color.white.opacity(0.16)
}

struct AscendSkeletonText: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: min(height / 2, 6), style: .continuous)
            .fill(AscendSkeletonStyle.fill)
            .frame(width: width, height: height)
            .ascendSkeletonShimmer()
            .accessibilityHidden(true)
    }
}

struct AscendSkeletonCircle: View {
    let size: CGFloat
    let tint: Color

    var body: some View {
        Circle()
            .fill(AscendSkeletonStyle.fill)
            .frame(width: size, height: size)
            .ascendSkeletonShimmer()
            .overlay(Circle().stroke(tint.opacity(0.45), lineWidth: 2))
            .accessibilityHidden(true)
    }
}

private struct AscendSkeletonShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isActive = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        let width = max(proxy.size.width, 1)
                        let height = max(proxy.size.height, 1)

                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.22),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: width * 0.72, height: height * 2.2)
                        .rotationEffect(.degrees(18))
                        .offset(
                            x: isActive ? width * 1.35 : -width * 0.95,
                            y: -height * 0.58
                        )
                    }
                    .blendMode(.plusLighter)
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                isActive = false
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    isActive = true
                }
            }
    }
}

extension View {
    func ascendSkeletonShimmer() -> some View {
        modifier(AscendSkeletonShimmer())
    }
}
