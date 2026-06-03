import SwiftUI

/// A pre-designed "recap" card: the climb's hero artwork with the name and key
/// stats laid out for the user. One source of truth, used two ways:
///   • shown live in the Recaps tab as the tappable preview, and
///   • rendered to a UIImage (via `ImageRenderer`) to become a baked background.
///
/// Scale-aware (everything derives from `width / 390`), so the small preview and
/// the full-resolution export are visually identical. New recap styles are new
/// card views — adding one is data/layout, not a new export path.
struct ShareRecapCard: View {
    let climb: Climb
    /// Curated stats for the stat row (typically duration · steps · calories).
    let stats: [ResolvedShareStat]
    /// Optional headline best effort shown beneath the stat row.
    let bestEffort: ResolvedShareStat?

    private let lime = Color(red: 0.706, green: 0.8, blue: 0)

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 390

            ZStack {
                ClimbArtworkView(climb: climb, variant: .hero)

                LinearGradient(
                    colors: [.black.opacity(0.2), .clear, .black.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: 0) {
                    Spacer()

                    Text(climb.name)
                        .font(.montserratBold(size: 30 * s))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 24 * s)

                    Text("CLIMB")
                        .font(.montserratSemiBold(size: 11 * s))
                        .tracking(3 * s)
                        .foregroundStyle(lime)
                        .padding(.top, 6 * s)

                    HStack(alignment: .top, spacing: 26 * s) {
                        ForEach(stats.prefix(3), id: \.label) { stat in
                            statCell(stat, scale: s)
                        }
                    }
                    .padding(.top, 26 * s)

                    if let bestEffort {
                        VStack(spacing: 2 * s) {
                            Text(bestEffort.value)
                                .font(.montserratBold(size: 34 * s))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(bestEffort.label)
                                .font(.montserratSemiBold(size: 11 * s))
                                .tracking(2 * s)
                                .foregroundStyle(lime)
                        }
                        .padding(.top, 30 * s)
                    }

                    Spacer()
                }
                .padding(.bottom, 70 * s)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    private func statCell(_ stat: ResolvedShareStat, scale s: CGFloat) -> some View {
        VStack(spacing: 2 * s) {
            Text(stat.value)
                .font(.montserratBold(size: 22 * s))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(stat.label)
                .font(.montserratSemiBold(size: 9 * s))
                .tracking(1 * s)
                .foregroundStyle(lime)
        }
    }
}
