import SwiftUI

/// The champion's crown perched on a picture, plus a dot for each other title held.
///
/// Drawn as an overlay sized exactly to the picture; the crown deliberately extends past
/// the picture's top-right edge. It never changes the picture's layout size, so a row or
/// a strip lays out the same whether or not the climber is crowned.
struct ChampionCrownMark: View {
    let titles: ChampionTitles
    let avatarSize: CGFloat
    /// The surface behind the picture, cut around each title dot so it reads on photos.
    var cutColor: Color = .black
    var playsShine = false

    private var perch: ChampionCrownPerch {
        ChampionCrownPerch(avatarSize: avatarSize)
    }

    var body: some View {
        if let leading = titles.leading {
            ZStack(alignment: .topLeading) {
                ChampionCrownImage(title: leading, playsShine: playsShine)
                    .frame(width: perch.crownWidth, height: perch.crownHeight)
                    .shadow(color: .black.opacity(0.85), radius: 1, x: 0, y: 1)
                    .shadow(color: leading.glow.opacity(0.5), radius: 3)
                    .rotationEffect(.degrees(perch.rotationDegrees))
                    .position(perch.crownCenter)

                if perch.showsTitleDots {
                    ForEach(Array(titles.others.enumerated()), id: \.element) { index, title in
                        titleDot(title)
                            .position(
                                x: perch.firstTitleDotCenter.x,
                                y: perch.firstTitleDotCenter.y +
                                    CGFloat(index) * (ChampionCrownPerch.titleDotDiameter + ChampionCrownPerch.titleDotSpacing)
                            )
                    }
                }
            }
            .frame(width: avatarSize, height: avatarSize)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func titleDot(_ title: ChampionTitle) -> some View {
        Circle()
            .fill(dotFill(title))
            .frame(
                width: ChampionCrownPerch.titleDotDiameter,
                height: ChampionCrownPerch.titleDotDiameter
            )
            .background {
                Circle()
                    .fill(cutColor)
                    .padding(-1.5)
            }
    }

    private func dotFill(_ title: ChampionTitle) -> AnyShapeStyle {
        switch title {
        case .yearly:
            AnyShapeStyle(AngularGradient(colors: Color.championMythicSpectrum, center: .center))
        case .weekly, .monthly, .allTime:
            AnyShapeStyle(title.tint)
        }
    }
}
