//
//  LeaderboardUserRowView.swift
//  AscendApp
//

import SwiftUI

struct LeaderboardUserRowView: View {
    /// Rank glyph for a climber who holds no rank this period. Reads as "no rung on the
    /// ladder" rather than as a number, so it can never be mistaken for a placing.
    static let unrankedRankLabel = "-"

    /// The signed-in climber's own row. An unranked climber renders without a rank
    /// number at all - see `LeaderboardUserStanding`. The two cases are one property
    /// rather than a nullable entry beside loose copies of its fields, so no caller can
    /// assemble a row that carries a rank and an unranked treatment at the same time.
    enum Standing {
        case ranked(ModeratedLeaderboardEntry)
        case unranked(displayName: String, formattedValue: String, photoURL: URL?)
    }

    @Environment(\.colorScheme) private var colorScheme

    let standing: Standing
    let metric: LeaderboardMetric
    var crownGapText: String? = nil

    init(
        entry: ModeratedLeaderboardEntry,
        metric: LeaderboardMetric,
        crownGapText: String? = nil
    ) {
        self.standing = .ranked(entry)
        self.metric = metric
        self.crownGapText = crownGapText
    }

    init(
        unrankedFormattedValue: String,
        displayName: String,
        photoURL: URL?,
        metric: LeaderboardMetric,
        crownGapText: String? = nil
    ) {
        self.standing = .unranked(
            displayName: displayName,
            formattedValue: unrankedFormattedValue,
            photoURL: photoURL
        )
        self.metric = metric
        self.crownGapText = crownGapText
    }

    private var displayName: String {
        switch standing {
        case .ranked(let entry):
            return entry.identity.displayName
        case .unranked(let displayName, _, _):
            return displayName
        }
    }

    private var photoURL: URL? {
        switch standing {
        case .ranked(let entry):
            return entry.identity.photoURL
        case .unranked(_, _, let photoURL):
            return photoURL
        }
    }

    private var formattedValue: String {
        switch standing {
        case .ranked(let entry):
            return entry.formattedValue
        case .unranked(_, let formattedValue, _):
            return formattedValue
        }
    }

    private var rowFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.045)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var rankLabel: String {
        switch standing {
        case .ranked(let entry):
            return CompetitionRanking.rankLabel(entry.rank, isTied: entry.isTied)
        case .unranked:
            return Self.unrankedRankLabel
        }
    }

    private var rankTint: Color {
        switch standing {
        case .ranked:
            return .accent
        case .unranked:
            return Color.accent.opacity(0.45)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(rankLabel)
                .font(.montserratBold(size: 30))
                .foregroundStyle(rankTint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 52, alignment: .leading)
                .monospacedDigit()

            profileImage
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName.uppercased())
                    .font(.montserratBold(size: 15))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                if let crownGapText {
                    HStack(spacing: 5) {
                        Image("LeaderboardCrown")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
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

            Text(formattedValue)
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
        let rankText: String
        switch standing {
        case .ranked(let entry):
            rankText = entry.isTied
                ? "You are tied for rank \(entry.rank)"
                : "Your rank \(entry.rank)"
        case .unranked:
            rankText = "You are unranked this period"
        }
        let base = "\(rankText), \(displayName), \(formattedValue) \(metric.displayName)"
        guard let crownGapText else {
            return base
        }
        return "\(base), \(crownGapText)"
    }

    @ViewBuilder
    private var profileImage: some View {
        if let photoURL {
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

#Preview("Ranked") {
    LeaderboardUserRowView(
        entry: .preview(
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

#Preview("Unranked") {
    LeaderboardUserRowView(
        unrankedFormattedValue: "0",
        displayName: "Maya Chen",
        photoURL: nil,
        metric: .climb,
        crownGapText: "48,000 STEPS TO CROWN"
    )
    .background(Color.black)
}
