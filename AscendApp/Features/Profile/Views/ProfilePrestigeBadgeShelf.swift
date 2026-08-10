import SwiftUI

struct ProfilePrestigeBadgeShelf: View {
    let tokens: [ProfilePrestigeToken]
    let imageSize: CGFloat
    /// `nil` renders the shelf as plain art. A record set - empty or not - makes each
    /// banded badge open its history.
    let history: [ProfileAchievementRecord]?

    @State private var selectedAchievementBand: ProfileAchievementRankBand?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(tokens) { token in
                    if history != nil, let band = token.achievementBand {
                        Button {
                            HapticsManager.shared.trigger(.lightImpact)
                            selectedAchievementBand = band
                        } label: {
                            ProfilePrestigeBadgeView(token: token, imageSize: imageSize)
                        }
                        .buttonStyle(.plain)
                    } else {
                        ProfilePrestigeBadgeView(token: token, imageSize: imageSize)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .sheet(item: $selectedAchievementBand) { band in
            AchievementHistorySheet(
                band: band,
                records: (history ?? []).filter { $0.countsToward(band) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
