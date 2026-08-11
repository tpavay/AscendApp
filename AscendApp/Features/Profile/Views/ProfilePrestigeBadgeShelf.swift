import SwiftUI

struct ProfilePrestigeBadgeShelf: View {
    let tokens: [ProfilePrestigeToken]
    let imageSize: CGFloat
    /// `nil` renders the shelf as plain art. A record set - empty or not - makes every badge
    /// that carries a history filter open its history.
    let history: [ProfileAchievementRecord]?

    @State private var selectedHistoryFilter: ProfileAchievementHistoryFilter?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(tokens) { token in
                    if history != nil, let filter = token.historyFilter {
                        Button {
                            HapticsManager.shared.trigger(.lightImpact)
                            selectedHistoryFilter = filter
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
        .sheet(item: $selectedHistoryFilter) { filter in
            AchievementHistorySheet(
                filter: filter,
                records: (history ?? []).filter(filter.matches)
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
