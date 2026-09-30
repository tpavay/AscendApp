import SwiftUI

/// One title's crown art, with the single shine a crown gets when it first appears.
///
/// Crowns are otherwise still: nothing loops, so a board of crowned pictures costs no
/// per-frame work. The shine is one gradient pass masked to the crown's own silhouette,
/// played once when `playsShine` is set, and never under Reduce Motion.
struct ChampionCrownImage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: ChampionTitle
    var playsShine = false
    var shineDelay: TimeInterval = 0

    @State private var shineProgress: CGFloat = -1

    var body: some View {
        Image(title.crownAssetName)
            .resizable()
            .scaledToFit()
            .overlay {
                if playsShine, !reduceMotion {
                    shine
                }
            }
            .accessibilityHidden(true)
    }

    private var shine: some View {
        GeometryReader { proxy in
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.3),
                    .init(color: .white.opacity(0.9), location: 0.5),
                    .init(color: .clear, location: 0.7)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .rotationEffect(.degrees(20))
            .offset(x: proxy.size.width * 1.3 * shineProgress)
        }
        .mask {
            Image(title.crownAssetName)
                .resizable()
                .scaledToFit()
        }
        .allowsHitTesting(false)
        .task {
            shineProgress = -1
            try? await Task.sleep(for: .seconds(shineDelay))
            withAnimation(.easeOut(duration: 0.9)) {
                shineProgress = 1
            }
        }
    }
}
