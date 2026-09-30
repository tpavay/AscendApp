import SwiftUI

/// The slim line that leads a Steps board all period: last period's champion, in the
/// title's colour, with a chevron to past champions.
///
/// It is the only place a board names its champion - list rows never carry a crown.
struct ChampionStripView: View {
    @Environment(ModerationStore.self) private var moderationStore

    let reign: ChampionReign
    var currentUserId: String?

    private var champions: [ModeratedLeaderboardEntry] {
        moderationStore.moderate(reign.champions.entries(currentUserId: currentUserId))
    }

    private var tint: Color {
        reign.title.tint
    }

    var body: some View {
        HStack(spacing: 12) {
            avatars

            VStack(alignment: .leading, spacing: 3) {
                Text(Self.label(for: reign.title, championCount: reign.result.championUserIds.count))
                    .font(.montserratBold(size: 10))
                    .tracking(1.6)
                    .foregroundStyle(tint)
                    .lineLimit(1)

                Text(nameLine)
                    .font(.montserratBold(size: 14))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.accent)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: tint.opacity(0.16), location: 0),
                            .init(color: tint.opacity(0.03), location: 0.6),
                            .init(color: .white.opacity(0.02), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.38), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens past champions")
    }

    private var avatars: some View {
        HStack(spacing: -12) {
            ForEach(champions.prefix(2)) { champion in
                ClimberAvatar(
                    userId: champion.userId,
                    photoURL: champion.identity.photoURL,
                    placeholder: .initials(
                        for: champion.identity,
                        fill: champion.isCurrentUser ? Color.accent : Color(hex: "3A3A3C"),
                        foreground: champion.isCurrentUser ? .black : .white,
                        fontSize: 12
                    ),
                    size: 40,
                    crownCutColor: .black,
                    championTitlesOverride: ChampionTitles([reign.title])
                )
            }
        }
    }

    /// `Zoe R. · 836 steps`; an exact tie names both, and more than two names the first.
    private var nameLine: String {
        let steps = (reign.champions.first?.totalSteps ?? 0).formatted(.number.grouping(.automatic))
        return "\(ChampionNames.joined(champions.map(\.identity.displayName))) · \(steps) steps"
    }

    private var accessibilityLabel: String {
        "\(Self.label(for: reign.title, championCount: reign.result.championUserIds.count).capitalized), \(nameLine)"
    }

    /// The strip names the reign relative to now - `LAST WEEK'S CHAMPION` - because it only
    /// ever shows the period that just closed; past boards keep the dates history needs.
    static func label(for title: ChampionTitle, championCount: Int) -> String {
        "\(ChampionTitleLine.relativeName(for: title)) \(championCount > 1 ? "CHAMPIONS" : "CHAMPION")"
    }
}

/// Names on a result: one name, two joined with `&`, more as the first and a count.
enum ChampionNames {
    static func joined(_ names: [String]) -> String {
        switch names.count {
        case 0: return PublicClimberIdentity.anonymousDisplayName
        case 1: return names[0]
        case 2: return "\(names[0]) & \(names[1])"
        default: return "\(names[0]) + \(names.count - 1)"
        }
    }
}
