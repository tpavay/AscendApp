//
//  LeaderboardRowListView.swift
//  AscendApp
//

import SwiftUI

struct LeaderboardRowListView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entries: [ModeratedLeaderboardEntry]
    let metric: LeaderboardMetric
    let onEntryAppear: (ModeratedLeaderboardEntry) -> Void

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var metricHeader: String {
        metric.displayName.uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    Group {
                        if entry.isCurrentUser {
                            LeaderboardRow(
                                entry: entry,
                                metric: metric
                            )
                        } else {
                            NavigationLink {
                                OtherUserProfileView(
                                    identity: entry.identity,
                                    moderationSource: .globalLeaderboard
                                )
                            } label: {
                                LeaderboardRow(
                                    entry: entry,
                                    metric: metric
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onAppear { onEntryAppear(entry) }

                    if entry.id != entries.last?.id {
                        Divider()
                            .overlay(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("RANK")
                .frame(width: 34, alignment: .leading)

            Text("CLIMBER")

            Spacer()

            Text(metricHeader)
                .frame(alignment: .trailing)
        }
        .font(.montserratBold(size: 10))
        .foregroundStyle(primaryTextColor.opacity(0.42))
        .padding(.bottom, 6)
    }
}

#Preview {
    LeaderboardRowListView(
        entries: [
            .preview(
                userId: "1",
                displayName: "Alex P.",
                rank: 5,
                value: 13_178_802,
                formattedValue: "13,178,802"
            ),
            .preview(
                userId: "2",
                displayName: "Mia K.",
                rank: 6,
                value: 11_246_663,
                formattedValue: "11,246,663"
            )
        ],
        metric: .climb,
        onEntryAppear: { _ in }
    )
    .background(Color.black)
}
