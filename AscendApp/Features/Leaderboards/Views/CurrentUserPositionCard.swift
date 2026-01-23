//
//  CurrentUserPositionCard.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI

/// A banner showing the user's current position on the leaderboard.
/// Displayed at the top when the user is not in the top 5.
/// Tapping scrolls to the user's position in the list.
struct UserPositionBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var settingsManager = SettingsManager.shared

    let entry: LeaderboardEntry
    let metric: LeaderboardMetric
    let onTap: () -> Void

    private var preferredMetric: WorkoutMetric {
        settingsManager.preferredWorkoutMetric
    }

    private var ordinalRank: String {
        let rank = entry.rank
        let suffix: String
        switch rank {
        case 11, 12, 13:
            suffix = "TH"
        default:
            switch rank % 10 {
            case 1: suffix = "ST"
            case 2: suffix = "ND"
            case 3: suffix = "RD"
            default: suffix = "TH"
            }
        }
        return "\(rank)\(suffix)"
    }

    var body: some View {
        VStack(spacing: 12) {
            // "You're in #XX" header - plain text, no background
            HStack(spacing: 6) {
                Text("You're in")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .gray)

                Text(ordinalRank)
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(.accent)
            }

            // User info card - tappable
            Button(action: {
                HapticsManager.shared.trigger(.lightImpact)
                onTap()
            }) {
                HStack(spacing: 14) {
                    // Rank badge
                    Text(ordinalRank)
                        .font(.montserratBold(size: 14))
                        .foregroundStyle(.accent)
                        .frame(width: 50)

                    // Profile image
                    profileImage

                    // Name
                    Text(entry.displayName)
                        .font(.montserratSemiBold(size: 15))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)

                    Spacer()

                    // Value
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(entry.formattedValue)
                            .font(.montserratBold(size: 16))
                            .foregroundStyle(.accent)

                        let unitLabel = metric.unit(for: preferredMetric)
                        if !unitLabel.isEmpty {
                            Text(unitLabel)
                                .font(.montserratRegular(size: 10))
                                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color("Jet") : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accent.opacity(0.3), lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
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
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                case .failure:
                    defaultAvatar
                case .empty:
                    defaultAvatar
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.5)
                        )
                @unknown default:
                    defaultAvatar
                }
            }
            .id(photoURL)
        } else {
            defaultAvatar
        }
    }

    private var defaultAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.accent.opacity(0.2))
                .frame(width: 40, height: 40)

            Image(systemName: "person.fill")
                .font(.system(size: 18))
                .foregroundStyle(.accent)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        UserPositionBanner(
            entry: LeaderboardEntry(
                userId: "1",
                displayName: "Tyler Pavay",
                rank: 44,
                value: 8500,
                formattedValue: "8,500",
                isCurrentUser: true
            ),
            metric: .climb,
            onTap: {}
        )

        UserPositionBanner(
            entry: LeaderboardEntry(
                userId: "2",
                displayName: "Jane Doe",
                rank: 821,
                value: 1200,
                formattedValue: "1,200",
                isCurrentUser: true
            ),
            metric: .climb,
            onTap: {}
        )
    }
    .themedBackground()
}
