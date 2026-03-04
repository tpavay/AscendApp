//
//  LeaderboardHeroView.swift
//  AscendApp
//

import SwiftUI

struct LeaderboardHeroView: View {
    @Environment(\.colorScheme) private var colorScheme

    let podiumEntries: [LeaderboardEntry]
    let metric: LeaderboardMetric

    private var showsPodium: Bool { !podiumEntries.isEmpty }

    private var heroSurface: Color {
        colorScheme == .dark ? .night : .white
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsPodium {
                LeaderboardPodiumView(
                    entries: podiumEntries,
                    metric: metric,
                    usesContainerBackground: false
                )
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
        }
        .background(heroSurface)
        .clipShape(.rect(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
    }
}

#Preview {
    LeaderboardHeroView(
        podiumEntries: [
            LeaderboardEntry(userId: "1", displayName: "Luna Ramirez", rank: 1, value: 16086, formattedValue: "16,086"),
            LeaderboardEntry(userId: "2", displayName: "Ethan Moore", rank: 2, value: 14064, formattedValue: "14,064"),
            LeaderboardEntry(userId: "3", displayName: "Lucas Harris", rank: 3, value: 12342, formattedValue: "12,342")
        ],
        metric: .climb
    )
    .themedBackground()
}
