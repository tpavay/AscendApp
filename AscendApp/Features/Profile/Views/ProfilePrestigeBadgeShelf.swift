import SwiftUI

struct ProfilePrestigeBadgeShelf: View {
    let tokens: [ProfilePrestigeToken]
    let achievementRecords: [ProfileAchievementRecord]
    let imageSize: CGFloat

    @State private var selectedAchievementBand: ProfileAchievementRankBand?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(tokens) { token in
                    if let band = token.achievementBand {
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
                records: achievementRecords.filter { $0.countsToward(band) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
