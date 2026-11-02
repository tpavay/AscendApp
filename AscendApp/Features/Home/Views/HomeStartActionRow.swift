import SwiftUI

/// One of the Climb sheet's three ways to climb: a gradient tile carrying the row's glyph, the
/// name, and one line under it. The first row is the hero - taller, ringed in the accent - because
/// a live climb is the main way to climb. The two lists carry a `See all ›` link in the corner.
struct HomeStartActionRow: View {
    let action: HomeStartAction
    /// Today's pick, worded for the row. Nil falls back to what the row is for.
    var detail: String?
    let onSelect: (HomeStartAction) -> Void
    var onSeeAll: (HomeStartAction) -> Void = { _ in }

    private var isHero: Bool { action == .justClimb }
    private var cornerRadius: CGFloat { isHero ? 24 : 22 }

    var body: some View {
        Button {
            onSelect(action)
        } label: {
            HStack(spacing: 14) {
                tile

                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title.uppercased())
                        .font(.montserratBold(size: isHero ? 21 : 18))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(detail ?? action.subtitle)
                        .font(.montserratSemiBold(size: 13))
                        .foregroundStyle(Color(white: 0.74))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: isHero ? 128 : 92, alignment: .leading)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isHero ? Color.accent : Color(white: 0.15),
                        lineWidth: isHero ? 2 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .accessibilityValue(detail ?? action.subtitle)
        .overlay(alignment: .topTrailing) {
            if action.offersSeeAll {
                // Outside the row's button: a second tap target that must not trigger the row.
                Button {
                    onSeeAll(action)
                } label: {
                    Text("See all ›")
                        .font(.montserratBold(size: 12))
                        .foregroundStyle(Color(white: 0.74))
                        .padding(.top, 14)
                        .padding(.trailing, 16)
                        .padding(.leading, 12)
                        .padding(.bottom, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See all \(action == .browseClimbs ? "landmarks" : "routines")")
            }
        }
    }

    // MARK: - Pieces

    private var tile: some View {
        let side: CGFloat = isHero ? 52 : 46
        let glyphSide: CGFloat = isHero ? 30 : 26
        let colors = tileColors

        return RoundedRectangle(cornerRadius: isHero ? 14 : 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [colors.0, colors.1],
                    startPoint: UnitPoint(x: 0.33, y: 0),
                    endPoint: UnitPoint(x: 0.67, y: 1)
                )
            )
            .frame(width: side, height: side)
            .overlay {
                HomeStartGlyphShape(glyph: action.glyph)
                    .fill(.black)
                    .frame(width: glyphSide, height: glyphSide)
            }
            .accessibilityHidden(true)
    }

    private var tileColors: (Color, Color) {
        switch action {
        case .justClimb:
            return (Color(red: 0.84, green: 0.97, blue: 0.60), Color(red: 0.49, green: 0.72, blue: 0.16))
        case .browseClimbs:
            return (Color(red: 1.0, green: 0.94, blue: 0.72), Color(red: 0.78, green: 0.60, blue: 0.13))
        case .routines:
            return (Color(red: 1.0, green: 0.89, blue: 0.69), Color(red: 0.91, green: 0.53, blue: 0.10))
        }
    }

    private var cardBackground: some View {
        let base = Color(white: 0.047)
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(base)
            .overlay {
                switch action {
                case .justClimb:
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 0.13, green: 0.20, blue: 0.05), .clear],
                                center: .topTrailing,
                                startRadius: 0,
                                endRadius: 260
                            )
                        )
                case .browseClimbs:
                    EmptyView()
                case .routines:
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 0.16, green: 0.09, blue: 0.02), .clear],
                                center: .bottomTrailing,
                                startRadius: 0,
                                endRadius: 220
                            )
                        )
                }
            }
    }
}

#Preview {
    VStack(spacing: 12) {
        ForEach(HomeStartAction.allCases, id: \.self) { action in
            HomeStartActionRow(action: action, onSelect: { _ in })
        }
    }
    .padding()
    .background(Color.black)
}
