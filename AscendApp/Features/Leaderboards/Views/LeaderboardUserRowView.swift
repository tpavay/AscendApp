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
        case unranked(userId: String?, displayName: String, formattedValue: String, photoURL: URL?)
    }

    @Environment(\.colorScheme) private var colorScheme

    let standing: Standing
    let metric: LeaderboardMetric
    var crownGapText: String? = nil
    /// The board's frame. On the last day of its open period the chase line names the time
    /// left, in gold.
    var countdownTimeFrame: LeaderboardTimeFrame? = nil
    /// Fixes the clock for evidence tests and previews.
    var now: Date? = nil

    init(
        entry: ModeratedLeaderboardEntry,
        metric: LeaderboardMetric,
        crownGapText: String? = nil,
        countdownTimeFrame: LeaderboardTimeFrame? = nil,
        now: Date? = nil
    ) {
        self.standing = .ranked(entry)
        self.metric = metric
        self.crownGapText = crownGapText
        self.countdownTimeFrame = countdownTimeFrame
        self.now = now
    }

    init(
        unrankedFormattedValue: String,
        userId: String?,
        displayName: String,
        photoURL: URL?,
        metric: LeaderboardMetric,
        crownGapText: String? = nil,
        countdownTimeFrame: LeaderboardTimeFrame? = nil,
        now: Date? = nil
    ) {
        self.standing = .unranked(
            userId: userId,
            displayName: displayName,
            formattedValue: unrankedFormattedValue,
            photoURL: photoURL
        )
        self.metric = metric
        self.crownGapText = crownGapText
        self.countdownTimeFrame = countdownTimeFrame
        self.now = now
    }

    private var displayName: String {
        switch standing {
        case .ranked(let entry):
            return entry.identity.displayName
        case .unranked(_, let displayName, _, _):
            return displayName
        }
    }

    private var userId: String? {
        switch standing {
        case .ranked(let entry):
            return entry.userId
        case .unranked(let userId, _, _, _):
            return userId
        }
    }

    private var photoURL: URL? {
        switch standing {
        case .ranked(let entry):
            return entry.identity.photoURL
        case .unranked(_, _, _, let photoURL):
            return photoURL
        }
    }

    private var formattedValue: String {
        switch standing {
        case .ranked(let entry):
            return entry.formattedValue
        case .unranked(_, _, let formattedValue, _):
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
                    if countdownTimeFrame != nil, now == nil {
                        TimelineView(.everyMinute) { context in
                            crownGapLine(crownGapText, countdown: countdown(at: context.date))
                        }
                    } else {
                        crownGapLine(crownGapText, countdown: countdown(at: now ?? .now))
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

    /// On the board's last day the chase line names the time left and turns gold: the
    /// crown is on the line.
    private func countdown(at date: Date) -> LeaderboardCountdown? {
        countdownTimeFrame.flatMap {
            LeaderboardCountdown.make(period: $0.currentPeriod(referenceDate: date), now: date)
        }
    }

    private func crownGapLine(_ text: String, countdown: LeaderboardCountdown?) -> some View {
        let isLastDay = countdown?.isLastDay ?? false
        let line = isLastDay ? "\(text) · \(countdown?.remainingText ?? "")" : text
        return HStack(spacing: 5) {
            Image("LeaderboardCrown")
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)

            Text(line)
                .font(.montserratBold(size: 9))
                .foregroundStyle(isLastDay ? Color.championGold : Color.accent)
                .lineLimit(isLastDay ? 2 : 1)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: false, vertical: isLastDay)
        }
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
        guard let countdown = countdown(at: now ?? .now), countdown.isLastDay else {
            return "\(base), \(crownGapText)"
        }
        return "\(base), \(crownGapText) · \(countdown.remainingText)"
    }

    private var profileImage: some View {
        ClimberAvatar(
            userId: userId,
            photoURL: photoURL,
            placeholder: .glyph(
                systemName: "person.fill",
                fill: Color.accent.opacity(colorScheme == .dark ? 0.22 : 0.16),
                foreground: .accent,
                glyphSize: 16
            ),
            size: 42,
            border: .init(color: Color.accent.opacity(0.78), width: 1.5),
            crownCutColor: colorScheme == .dark ? Color(white: 0.055) : Color(white: 0.955),
            showsLoadingIndicator: true
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
        userId: nil,
        displayName: "Maya Chen",
        photoURL: nil,
        metric: .climb,
        crownGapText: "48,000 STEPS TO CROWN"
    )
    .background(Color.black)
}
