import SwiftUI

/// The crown: who took the period, with the crown landing on their picture. When the
/// viewer won, this page is their coronation.
struct PeriodRecapCrownPage: View {
    @Environment(ModerationStore.self) private var moderationStore
    @Environment(\.recapIsStatic) private var isStatic

    let crown: PeriodRecapCrown
    let viewerId: String?
    /// The viewer has never climbed, so the page ends on their first climb, not the podium.
    var isFirstClimbInvitation = false

    private var champions: [ModeratedLeaderboardEntry] {
        moderationStore.moderate(crown.champions.entries(currentUserId: viewerId))
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
                .frame(maxHeight: 40)

            HStack(spacing: champions.count > 1 ? 28 : 0) {
                ForEach(champions.prefix(2)) { champion in
                    CoronationAvatar(
                        userId: champion.userId,
                        photoURL: champion.identity.photoURL,
                        placeholder: RecapAvatarStyle.placeholder(for: champion, fontSize: 38),
                        title: crown.title,
                        size: champions.count > 1 ? 96 : 120,
                        isStatic: isStatic
                    )
                }
            }
            .padding(.top, 44)
            .recapEntrance(0)

            Text(PeriodRecapCopy.crownHeadline(
                names: champions.map(\.identity.displayName),
                viewerIsChampion: crown.viewerIsChampion
            ))
            .font(.montserratBold(size: 26))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .padding(.top, 22)
            .recapEntrance(1)

            Text(PeriodRecapCopy.crownDetail(
                steps: crown.winningSteps,
                climberCount: crown.climberCount,
                isTie: crown.isTie
            ))
            .font(.montserratSemiBold(size: 13))
            .foregroundStyle(RecapStyle.secondaryText)
            .padding(.top, 8)
            .recapEntrance(2)

            if crown.viewerIsChampion {
                if let reignLine = PeriodRecapCopy.reignLine(endsAt: crown.reignEndsAt) {
                    Text(reignLine)
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.top, 22)
                        .padding(.horizontal, 12)
                        .recapEntrance(3)
                }
            } else if isFirstClimbInvitation {
                Text(PeriodRecapCopy.firstClimbLine(after: crown.period))
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.top, 22)
                    .padding(.horizontal, 12)
                    .recapEntrance(3)
            } else {
                podiumRows
                    .padding(.top, 26)
                    .recapEntrance(3)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var podiumRows: some View {
        VStack(spacing: 8) {
            ForEach(moderationStore.moderate(crown.runnersUp.entries(currentUserId: viewerId))) { entry in
                RecapPlacingRow(
                    leading: "#\(entry.rank)",
                    leadingColor: entry.rank == 2 ? Color(hex: "BFC4CC") : Color(hex: "C8793D"),
                    entry: entry,
                    name: entry.identity.displayName,
                    value: entry.formattedValue
                )
            }

            let mostClimbs = moderationStore.moderate(crown.mostClimbs.entries(currentUserId: viewerId))
            if let first = mostClimbs.first, let count = crown.mostClimbsCount {
                RecapPlacingRow(
                    leading: "MOST",
                    leadingColor: Color.accent,
                    entry: first,
                    name: "\(ChampionNames.joined(mostClimbs.map(\.identity.displayName))) · most climbs",
                    value: count.formatted()
                )
            }
        }
    }
}

/// One line of a recap podium: `#2 · Maya C. · 8,120`.
struct RecapPlacingRow: View {
    let leading: String
    let leadingColor: Color
    let entry: ModeratedLeaderboardEntry
    let name: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(leading)
                .font(.montserratBold(size: leading.count > 3 ? 10 : 14))
                .tracking(leading.count > 3 ? 1 : 0)
                .foregroundStyle(leadingColor)
                .frame(width: 38, alignment: .leading)

            ClimberAvatar(
                userId: entry.userId,
                photoURL: entry.identity.photoURL,
                placeholder: RecapAvatarStyle.placeholder(for: entry, fontSize: 11),
                size: 32,
                crownCutColor: RecapStyle.tileFill
            )

            Text(name)
                .font(.montserratBold(size: 14))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            Text(value)
                .font(.montserratBold(size: 14))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(RecapStyle.tileFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(RecapStyle.tileStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// How the recap draws a climber with no photo: initials on graphite, the viewer in lime.
enum RecapAvatarStyle {
    static func placeholder(for entry: ModeratedLeaderboardEntry, fontSize: CGFloat) -> ClimberAvatarPlaceholder {
        .initials(
            for: entry.identity,
            fill: entry.isCurrentUser ? Color.accent : Color(hex: "3A3A3C"),
            foreground: entry.isCurrentUser ? .black : .white,
            fontSize: fontSize
        )
    }
}

/// The closing page when a month and a week closed together: both champions, both crowns.
struct PeriodRecapCrownsPage: View {
    @Environment(ModerationStore.self) private var moderationStore
    @Environment(\.recapIsStatic) private var isStatic

    let crowns: [PeriodRecapCrown]
    let viewerId: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(crowns.enumerated()), id: \.offset) { index, crown in
                if index > 0 {
                    Rectangle()
                        .fill(.white.opacity(0.12))
                        .frame(height: 1)
                        .padding(.vertical, 26)
                }
                block(crown)
                    .recapEntrance(index)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
    }

    private func block(_ crown: PeriodRecapCrown) -> some View {
        let champions = moderationStore.moderate(crown.champions.entries(currentUserId: viewerId))
        return HStack(spacing: 16) {
            if let champion = champions.first {
                CoronationAvatar(
                    userId: champion.userId,
                    photoURL: champion.identity.photoURL,
                    placeholder: RecapAvatarStyle.placeholder(for: champion, fontSize: 26),
                    title: crown.title,
                    size: 76,
                    isStatic: isStatic
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(label(for: crown.period))
                    .font(.montserratBold(size: 10))
                    .tracking(1.8)
                    .foregroundStyle(crown.title.tint)

                Text(PeriodRecapCopy.crownsHeadline(
                    names: champions.map(\.identity.displayName),
                    viewerIsChampion: crown.viewerIsChampion,
                    period: crown.period
                ))
                .font(.montserratBold(size: 19))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

                Text(PeriodRecapCopy.crownDetail(
                    steps: crown.winningSteps,
                    climberCount: crown.climberCount,
                    isTie: crown.isTie
                ))
                .font(.montserratSemiBold(size: 12))
                .foregroundStyle(RecapStyle.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func label(for period: LeaderboardPeriod) -> String {
        switch period.timeFrame {
        case .weekly:
            "WEEK \(ChampionTitleLine.weekNumber(of: period)) · \(PeriodRecapCopy.compactWindow(for: period))"
        default:
            ChampionTitleLine.periodName(for: period)
        }
    }
}
