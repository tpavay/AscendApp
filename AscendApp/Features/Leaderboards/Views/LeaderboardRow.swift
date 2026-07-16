//
//  LeaderboardRow.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI

struct LeaderboardRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: LeaderboardEntry
    let metric: LeaderboardMetric

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.montserratMedium(size: 14))
                .foregroundStyle(primaryTextColor.opacity(0.82))
                .frame(width: 34, alignment: .leading)

            Text(entry.displayName.uppercased())
                .font(.montserratMedium(size: 13))
                .foregroundStyle(entry.isCurrentUser ? .accent : primaryTextColor.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            Spacer(minLength: 8)

            Text(entry.formattedValue)
                .font(.montserratMedium(size: 13))
                .foregroundStyle(entry.isCurrentUser ? .accent : primaryTextColor.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .frame(height: 36)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(entry.rank), \(entry.displayName), \(entry.formattedValue) \(metric.displayName)")
    }
}

#Preview {
    VStack(spacing: 0) {
        LeaderboardRow(
            entry: LeaderboardEntry(
                userId: "1",
                displayName: "Alex P.",
                rank: 5,
                value: 13_178_802,
                formattedValue: "13,178,802"
            ),
            metric: .climb
        )

        Divider()

        LeaderboardRow(
            entry: LeaderboardEntry(
                userId: "2",
                displayName: "Mia K.",
                rank: 6,
                value: 11_246_663,
                formattedValue: "11,246,663"
            ),
            metric: .climb
        )
    }
    .padding()
    .background(Color.black)
}
