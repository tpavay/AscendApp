//
//  Top5CarouselView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 12/6/25.
//

import SwiftUI

struct Top5CarouselView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var settingsManager = SettingsManager.shared

    let entries: [LeaderboardEntry]
    let metric: LeaderboardMetric
    let currentUserId: String?

    private var preferredMetric: WorkoutMetric {
        settingsManager.preferredWorkoutMetric
    }

    private var top5Entries: [LeaderboardEntry] {
        Array(entries.prefix(5))
    }

    private let cardSpacing: CGFloat = 20

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            // Section header
            Text("CURRENT STANDINGS")
                .font(.montserratSemiBold(size: 12))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)

            // Horizontal carousel with centered paging
            GeometryReader { geometry in
                let screenWidth = geometry.size.width
                let cardWidth = screenWidth - 120 // Leave 60pt on each side for peeking adjacent cards
                let horizontalPadding = (screenWidth - cardWidth) / 2

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: cardSpacing) {
                        ForEach(top5Entries) { entry in
                            Top5Card(
                                entry: entry,
                                metric: metric,
                                preferredMetric: preferredMetric
                            )
                            .frame(width: cardWidth)
                            .scrollTransition { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0.5)
                                    .scaleEffect(phase.isIdentity ? 1 : 0.92)
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, horizontalPadding)
                }
                .scrollTargetBehavior(.viewAligned)
            }
            .frame(height: 160)
        }
    }
}

// MARK: - Top 5 Card

private struct Top5Card: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: LeaderboardEntry
    let metric: LeaderboardMetric
    let preferredMetric: WorkoutMetric

    private var ordinalRank: String {
        switch entry.rank {
        case 1: return "1ST"
        case 2: return "2ND"
        case 3: return "3RD"
        case 4: return "4TH"
        case 5: return "5TH"
        default: return "\(entry.rank)TH"
        }
    }

    private var rankColor: Color {
        switch entry.rank {
        case 1:
            return Color(red: 1.0, green: 0.84, blue: 0.0) // Gold
        case 2:
            return Color(red: 0.75, green: 0.75, blue: 0.82) // Silver
        case 3:
            return Color(red: 0.80, green: 0.50, blue: 0.20) // Bronze
        default:
            return colorScheme == .dark ? .white : .black
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left side: Rank, Name, Stats
            VStack(alignment: .leading, spacing: 8) {
                // Rank with trophy/medal
                HStack(spacing: 6) {
                    if entry.rank <= 3 {
                        Image(systemName: entry.rank == 1 ? "trophy.fill" : "medal.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(rankColor)
                    }

                    Text(ordinalRank)
                        .font(.montserratBold(size: 28))
                        .foregroundStyle(rankColor)
                }

                // Display name
                Text(entry.displayName)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(entry.isCurrentUser ? .accent : (colorScheme == .dark ? .white : .black))
                    .lineLimit(1)

                Spacer()

                // Value and unit
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.formattedValue)
                        .font(.montserratBold(size: 22))
                        .foregroundStyle(.accent)

                    let unitLabel = metric.unit(for: preferredMetric)
                    if !unitLabel.isEmpty {
                        Text(unitLabel)
                            .font(.montserratRegular(size: 12))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right side: Large profile picture
            profileImage
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var profileImage: some View {
        if let photoURL = entry.photoURL {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                case .failure:
                    defaultAvatar
                case .empty:
                    defaultAvatar
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.6)
                        )
                @unknown default:
                    defaultAvatar
                }
            }
        } else {
            defaultAvatar
        }
    }

    private var defaultAvatar: some View {
        ZStack {
            Circle()
                .fill(entry.isCurrentUser ? Color.accent.opacity(0.2) : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.15)))
                .frame(width: 100, height: 100)

            Image(systemName: "person.fill")
                .font(.system(size: 40))
                .foregroundStyle(entry.isCurrentUser ? .accent : (colorScheme == .dark ? .white.opacity(0.5) : .gray))
        }
    }
}

#Preview {
    VStack {
        Top5CarouselView(
            entries: [
                LeaderboardEntry(userId: "1", displayName: "Alice", rank: 1, value: 15000, formattedValue: "15,000", isCurrentUser: false),
                LeaderboardEntry(userId: "2", displayName: "Bob", rank: 2, value: 14500, formattedValue: "14,500", isCurrentUser: false),
                LeaderboardEntry(userId: "3", displayName: "Charlie", rank: 3, value: 14000, formattedValue: "14,000", isCurrentUser: true),
                LeaderboardEntry(userId: "4", displayName: "Diana", rank: 4, value: 13500, formattedValue: "13,500", isCurrentUser: false),
                LeaderboardEntry(userId: "5", displayName: "Eve", rank: 5, value: 13000, formattedValue: "13,000", isCurrentUser: false)
            ],
            metric: .climb,
            currentUserId: "3"
        )
    }
    .themedBackground()
}
