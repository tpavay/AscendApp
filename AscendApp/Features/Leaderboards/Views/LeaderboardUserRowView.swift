//
//  LeaderboardUserRowView.swift
//  AscendApp
//

import SwiftUI

struct LeaderboardUserRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var settingsManager = SettingsManager.shared

    let entry: LeaderboardEntry
    let metric: LeaderboardMetric

    private var preferredMetric: WorkoutMetric {
        settingsManager.preferredWorkoutMetric
    }

    private var rowFill: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color.night,
                    Color.jetLighter,
                    Color.accent.opacity(0.3)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        return LinearGradient(
            colors: [
                Color.white,
                Color.night.opacity(0.08),
                Color.accent.opacity(0.24)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        HStack(spacing: 14) {
            Text("\(entry.rank)")
                .font(.montserratBold(size: 24))
                .foregroundStyle(.accent)
                .frame(width: 34, alignment: .leading)

            profileImage

            Text(entry.displayName)
                .font(.montserratSemiBold(size: 15))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .lineLimit(1)

            Spacer()

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
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(rowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accent.opacity(colorScheme == .dark ? 0.45 : 0.55), lineWidth: 1.5)
        )
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
                        .frame(width: 36, height: 36)
                        .clipShape(.circle)
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
                .frame(width: 36, height: 36)

            Image(systemName: "person.fill")
                .font(.system(size: 15))
                .foregroundStyle(.accent)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        LeaderboardUserRowView(
            entry: LeaderboardEntry(
                userId: "1",
                displayName: "Tyler Pavay",
                rank: 37,
                value: 3425,
                formattedValue: "3,425",
                isCurrentUser: true
            ),
            metric: .climb
        )
    }
    .themedBackground()
}
