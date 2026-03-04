//
//  LeaderboardRowListView.swift
//  AscendApp
//

import SwiftUI

struct LeaderboardRowListView: View {
    let entries: [LeaderboardEntry]
    let metric: LeaderboardMetric
    let onEntryAppear: (LeaderboardEntry) -> Void

    var body: some View {
        LazyVStack(spacing: 10) {
            ForEach(entries) { entry in
                LeaderboardRow(
                    entry: entry,
                    metric: metric
                )
                .onAppear {
                    onEntryAppear(entry)
                }
            }
        }
    }
}

#Preview {
    LeaderboardRowListView(
        entries: [
            LeaderboardEntry(userId: "1", displayName: "Elijah Bell", rank: 4, value: 11195, formattedValue: "11,195"),
            LeaderboardEntry(userId: "2", displayName: "Penelope Ortiz", rank: 5, value: 10194, formattedValue: "10,194")
        ],
        metric: .climb,
        onEntryAppear: { _ in }
    )
    .themedBackground()
}
