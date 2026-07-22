//
//  LeaderboardUserRowView.swift
//  AscendApp
//

import SwiftUI

struct LeaderboardUserRowView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: LeaderboardEntry
    let metric: LeaderboardMetric
    var crownGapText: String? = nil

    private var identity: PublicClimberIdentity.Presentation {
        PublicClimberIdentity.resolve(
            userId: entry.userId,
            storedDisplayName: entry.displayName,
            storedPhotoURL: entry.photoURL,
            isCurrentUser: true,
            currentUserPhotoURL: entry.photoURL
        )
    }

    private var rowFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.045)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(CompetitionRanking.rankLabel(entry.rank, isTied: entry.isTied))
                .font(.montserratBold(size: 30))
                .foregroundStyle(.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 52, alignment: .leading)
                .monospacedDigit()

            profileImage
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(identity.displayName.uppercased())
                    .font(.montserratBold(size: 15))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                if let crownGapText {
                    HStack(spacing: 5) {
                        Image("LeaderboardCrown")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .accessibilityHidden(true)

                        Text(crownGapText)
                            .font(.montserratBold(size: 9))
                            .foregroundStyle(Color.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
            }

            Spacer(minLength: 8)

            Text(entry.formattedValue)
                .font(.montserratMedium(size: 16))
                .foregroundStyle(primaryTextColor.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .frame(height: crownGapText == nil ? 64 : 72)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowFill)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.accent)
                .frame(width: 4)
                .padding(.vertical, 2)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(colorScheme == .dark ? .white.opacity(0.06) : .black.opacity(0.05), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let rankText = entry.isTied
            ? "You are tied for rank \(entry.rank)"
            : "Your rank \(entry.rank)"
        let base = "\(rankText), \(identity.displayName), \(entry.formattedValue) \(metric.displayName)"
        guard let crownGapText else {
            return base
        }
        return "\(base), \(crownGapText)"
    }

    @ViewBuilder
    private var profileImage: some View {
        if let photoURL = identity.photoURL {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
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
            .overlay(
                Circle()
                    .stroke(Color.accent.opacity(0.78), lineWidth: 1.5)
            )
            .id(photoURL)
        } else {
            defaultAvatar
        }
    }

    private var defaultAvatar: some View {
        Circle()
            .fill(Color.accent.opacity(colorScheme == .dark ? 0.22 : 0.16))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.accent)
            )
            .overlay(
                Circle()
                    .stroke(Color.accent.opacity(0.78), lineWidth: 1.5)
            )
    }
}

#Preview {
    LeaderboardUserRowView(
        entry: LeaderboardEntry(
            userId: "1",
            displayName: "Ryan T.",
            rank: 43,
            value: 15_872_211,
            formattedValue: "15,872,211",
            isCurrentUser: true
        ),
        metric: .climb,
        crownGapText: "1,204 STEPS TO CROWN"
    )
    .background(Color.black)
}
