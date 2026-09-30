import SwiftUI

/// The one picture of a climber, on every surface that shows one.
///
/// It draws the photo (or the surface's placeholder), an optional stroke, and - when the
/// climber holds a champion title - the perched crown. The crown is read from
/// `ChampionRegistry` by uid, so no surface has to remember to pass it, and a blocked
/// climber keeps their crown on the placeholder picture. Set `showsChampionMark` to false
/// only where the picture already wears a gold, silver or bronze ring.
struct ClimberAvatar: View {
    struct Border: Equatable {
        let color: Color
        let width: CGFloat
        /// Some boards outline a photograph but draw initials edge to edge.
        var onlyOverPhoto = false
        /// Draws the stroke this far inside the picture's edge.
        var inset: CGFloat = 0
    }

    @Environment(ChampionRegistry.self) private var championRegistry: ChampionRegistry?

    let userId: String?
    /// The signed-in climber's own row. Their live attempt carries no uid, so this is how
    /// its picture finds their crown.
    var isCurrentUser = false
    let photoURL: URL?
    let placeholder: ClimberAvatarPlaceholder
    let size: CGFloat
    var border: Border?
    var showsChampionMark = true
    /// The surface colour behind the picture, cut around the title dots.
    var crownCutColor: Color = .black
    var playsCrownShine = false
    var showsLoadingIndicator = false
    /// Titles to draw instead of the registry's - for the recap's coronation, which crowns
    /// the winner of the period being recapped rather than whoever reigns now.
    var championTitlesOverride: ChampionTitles?

    private var championTitles: ChampionTitles {
        guard showsChampionMark else { return .none }
        if let championTitlesOverride {
            return (championRegistry?.isEnabled ?? true) ? championTitlesOverride : .none
        }
        return championRegistry?.titles(for: userId, isCurrentUser: isCurrentUser) ?? .none
    }

    var body: some View {
        picture
            .frame(width: size, height: size)
            .clipShape(.circle)
            .overlay {
                if let border, !border.onlyOverPhoto || photoURL != nil {
                    Circle()
                        .stroke(border.color, lineWidth: border.width)
                        .padding(border.inset)
                }
            }
            .overlay {
                ChampionCrownMark(
                    titles: championTitles,
                    avatarSize: size,
                    cutColor: crownCutColor,
                    playsShine: playsCrownShine
                )
            }
    }

    @ViewBuilder
    private var picture: some View {
        if let photoURL {
            AsyncImage(
                url: photoURL,
                transaction: Transaction(animation: .easeInOut(duration: 0.2))
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty:
                    placeholderView
                        .overlay {
                            if showsLoadingIndicator {
                                ProgressView()
                                    .scaleEffect(0.5)
                            }
                        }
                case .failure:
                    placeholderView
                @unknown default:
                    placeholderView
                }
            }
            .id(photoURL)
        } else {
            placeholderView
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        switch placeholder {
        case .initials(let token, let fill, let foreground, let fontSize):
            if token.isEmpty {
                glyph(
                    systemName: PublicClimberIdentity.genericAvatarSystemName,
                    fill: fill,
                    foreground: foreground,
                    glyphSize: nil
                )
            } else {
                Circle()
                    .fill(fill)
                    .overlay {
                        Text(token)
                            .font(.montserratBold(size: fontSize ?? Self.initialsFontSize(for: size)))
                            .foregroundStyle(foreground)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .padding(.horizontal, size * 0.08)
                    }
            }
        case .glyph(let systemName, let fill, let foreground, let glyphSize):
            glyph(systemName: systemName, fill: fill, foreground: foreground, glyphSize: glyphSize)
        case .profileDefault:
            Circle()
                .fill(Color.white.opacity(0.08))
                .overlay {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: size * 0.62, weight: .semibold))
                        .foregroundStyle(Color.ascendAccent)
                }
        }
    }

    private func glyph(
        systemName: String,
        fill: Color,
        foreground: Color,
        glyphSize: CGFloat?
    ) -> some View {
        Circle()
            .fill(fill)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: glyphSize ?? size * 0.38, weight: .semibold))
                    .foregroundStyle(foreground)
                    .accessibilityHidden(true)
            }
    }

    static func initialsFontSize(for size: CGFloat) -> CGFloat {
        max(11, (size * 0.3).rounded())
    }
}
