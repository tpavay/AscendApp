import SwiftUI

/// The champion's picture on the recap's crown page, with the crown dropping onto it.
///
/// The crown falls from well above at almost twice its size, overshoots, and settles at
/// its perch over 1.1 seconds while a gold ring pulses out behind the picture, then shines
/// once. This is the one moment a crown moves; everywhere else crowns are still. Under
/// Reduce Motion the crown is simply there.
struct CoronationAvatar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let userId: String?
    let photoURL: URL?
    let placeholder: ClimberAvatarPlaceholder
    let title: ChampionTitle
    var size: CGFloat = 120
    /// Holds the crown at rest - for evidence renders, which capture a still frame.
    var isStatic = false

    @State private var dropTrigger = 0
    @State private var hasSettled = false

    private var perch: ChampionCrownPerch {
        ChampionCrownPerch(avatarSize: size)
    }

    private var animates: Bool {
        !reduceMotion && !isStatic
    }

    var body: some View {
        ZStack {
            if animates {
                CoronationBurst(color: title.glow, trigger: dropTrigger)
                    .frame(width: size, height: size)
            }

            ClimberAvatar(
                userId: userId,
                photoURL: photoURL,
                placeholder: placeholder,
                size: size,
                showsChampionMark: false
            )
        }
        .overlay {
            ZStack(alignment: .topLeading) {
                crown
                    .position(perch.crownCenter)
            }
            .frame(width: size, height: size)
        }
        .onAppear {
            if animates {
                dropTrigger += 1
            } else {
                hasSettled = true
            }
        }
    }

    @ViewBuilder
    private var crown: some View {
        let art = ChampionCrownImage(title: title, playsShine: hasSettled && animates)
            .frame(width: perch.crownWidth, height: perch.crownHeight)
            .shadow(color: .black.opacity(0.85), radius: 1, x: 0, y: 1)
            .shadow(color: title.glow.opacity(0.5), radius: 4)

        if animates {
            art
                .keyframeAnimator(initialValue: CrownDrop.start, trigger: dropTrigger) { content, value in
                    content
                        .rotationEffect(.degrees(value.rotation))
                        .scaleEffect(value.scale)
                        .offset(y: value.offsetY)
                        .opacity(value.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.offsetY) {
                        LinearKeyframe(-90, duration: 0.45)
                        SpringKeyframe(6, duration: 0.6)
                        SpringKeyframe(-4, duration: 0.22)
                        SpringKeyframe(0, duration: 0.28)
                    }
                    KeyframeTrack(\.scale) {
                        LinearKeyframe(1.9, duration: 0.45)
                        CubicKeyframe(0.95, duration: 0.6)
                        CubicKeyframe(1.04, duration: 0.22)
                        CubicKeyframe(1, duration: 0.28)
                    }
                    KeyframeTrack(\.rotation) {
                        LinearKeyframe(-10, duration: 0.45)
                        CubicKeyframe(26, duration: 0.6)
                        CubicKeyframe(20, duration: 0.22)
                        CubicKeyframe(perch.rotationDegrees, duration: 0.28)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(0, duration: 0.45)
                        LinearKeyframe(1, duration: 0.4)
                    }
                }
                .task(id: dropTrigger) {
                    guard dropTrigger > 0 else { return }
                    try? await Task.sleep(for: .seconds(1.55))
                    hasSettled = true
                }
        } else {
            art.rotationEffect(.degrees(perch.rotationDegrees))
        }
    }
}

private struct CrownDrop {
    var offsetY: CGFloat
    var scale: CGFloat
    var rotation: Double
    var opacity: Double

    static let start = CrownDrop(offsetY: -90, scale: 1.9, rotation: -10, opacity: 0)
}

/// A ring of the title's colour pulsing out from behind the picture as the crown lands.
private struct CoronationBurst: View {
    let color: Color
    let trigger: Int

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 3)
            .keyframeAnimator(initialValue: BurstState(scale: 1, opacity: 0), trigger: trigger) { content, value in
                content
                    .scaleEffect(value.scale)
                    .opacity(value.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1, duration: 1.05)
                    CubicKeyframe(2.6, duration: 1.2)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: 1.0)
                    LinearKeyframe(0.7, duration: 0.05)
                    CubicKeyframe(0, duration: 1.2)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private struct BurstState {
        var scale: CGFloat
        var opacity: Double
    }
}
