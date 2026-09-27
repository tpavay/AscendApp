import SwiftUI

/// Back after weeks away: every champion missed, one line each, rather than a stack of
/// stale recaps. A crown appears only on a title still held.
struct PeriodRecapCatchUpPage: View {
    @Environment(ModerationStore.self) private var moderationStore

    let catchUp: PeriodRecapCatchUp
    let viewerId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(PeriodRecapCopy.catchUpHeadline(
                weeks: catchUp.missedWeeks,
                champions: catchUp.lines.filter { $0.crown.title == .weekly }.count
            ))
            .font(.montserratBold(size: 26))
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 20)
            .recapEntrance(0)

            if let lastClimb = PeriodRecapCopy.lastClimbLine(catchUp.lastClimbAt) {
                Text(lastClimb)
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(RecapStyle.secondaryText)
                    .padding(.top, 8)
                    .recapEntrance(1)
            }

            VStack(spacing: 0) {
                ForEach(Array(catchUp.lines.enumerated()), id: \.offset) { index, line in
                    row(line)
                        .recapEntrance(index + 2)
                }
            }
            .padding(.top, 22)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ line: PeriodRecapCatchUp.Line) -> some View {
        let champions = moderationStore.moderate(line.crown.champions.entries(currentUserId: viewerId))
        return HStack(spacing: 12) {
            HStack(spacing: -12) {
                ForEach(champions.prefix(2)) { champion in
                    ClimberAvatar(
                        userId: champion.userId,
                        photoURL: champion.identity.photoURL,
                        placeholder: RecapAvatarStyle.placeholder(for: champion, fontSize: 12),
                        size: 36,
                        showsChampionMark: line.isReigning
                    )
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(ChampionNames.joined(champions.map(\.identity.displayName)))
                    .font(.montserratBold(size: 15))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(subtitle(for: line.crown))
                    .font(.montserratSemiBold(size: 11))
                    .foregroundStyle(RecapStyle.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            Text(line.crown.winningSteps.formatted())
                .font(.montserratBold(size: 14))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// `Week 38 · Sep 14-20`, `Week 36 · tied at exactly 1,776 steps`, or `August`.
    private func subtitle(for crown: PeriodRecapCrown) -> String {
        let name = ChampionTitleLine.periodName(for: crown.period).capitalized
        if crown.isTie {
            return "\(name) · tied at exactly \(crown.winningSteps.formatted()) steps"
        }
        switch crown.period.timeFrame {
        case .weekly:
            return "\(name) · \(PeriodRecapCopy.sentenceWindow(for: crown.period))"
        default:
            return name
        }
    }
}

/// A period without climbs, on one short page: when the climber last climbed, where to
/// start, what everyone else did, and who took the crown.
struct PeriodRecapNoClimbsPage: View {
    @Environment(ModerationStore.self) private var moderationStore

    let summary: PeriodRecapNoClimbs
    let viewerId: String?
    var now: Date = .now

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(PeriodRecapCopy.noClimbsHeadline(for: summary.period))
                    .font(.montserratBold(size: 26))
                    .foregroundStyle(.white)
                    .padding(.top, 20)
                    .recapEntrance(0)

                Text(PeriodRecapCopy.noClimbsDetail(
                    lastClimbAt: summary.inactive.lastClimbAt,
                    period: summary.period,
                    now: now
                ))
                .font(.montserratMedium(size: 13))
                .foregroundStyle(RecapStyle.secondaryText)
                .padding(.top, 8)
                .recapEntrance(1)

                if let climb = suggestedClimb {
                    suggestion(climb)
                        .padding(.top, 20)
                        .recapEntrance(2)
                }

                if summary.community.climbers > 0 {
                    RecapSectionLabel("EVERYONE CLIMBED")
                        .padding(.top, 24)
                        .padding(.bottom, 10)
                        .recapEntrance(3)

                    HStack(spacing: 8) {
                        tile(label: "CLIMBS", value: summary.community.climbs)
                        tile(label: "STEPS", value: summary.community.steps)
                    }
                    .recapEntrance(4)
                }

                if let crown = summary.crown {
                    championCard(crown)
                        .padding(.top, 10)
                        .recapEntrance(5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var suggestedClimb: Climb? {
        guard let id = summary.inactive.suggestedClimbId else { return nil }
        return try? ClimbService.shared.climb(for: id)
    }

    private func suggestion(_ climb: Climb) -> some View {
        HStack(spacing: 14) {
            ClimbArtworkView(climb: climb, variant: .thumb)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("START HERE")
                    .font(.montserratBold(size: 10))
                    .tracking(1.6)
                    .foregroundStyle(Color.accent)
                Text(climb.name)
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(climb.referenceStepCount.formatted()) steps")
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(RecapStyle.tileFill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(RecapStyle.tileStroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func tile(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.montserratBold(size: 10))
                .tracking(1.6)
                .foregroundStyle(RecapStyle.tertiaryText)
            Text(value.formatted(.number.notation(.compactName)))
                .font(.montserratBold(size: 24))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(RecapStyle.tileFill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(RecapStyle.tileStroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func championCard(_ crown: PeriodRecapCrown) -> some View {
        let champions = moderationStore.moderate(crown.champions.entries(currentUserId: viewerId))
        return HStack(spacing: 12) {
            if let champion = champions.first {
                ClimberAvatar(
                    userId: champion.userId,
                    photoURL: champion.identity.photoURL,
                    placeholder: RecapAvatarStyle.placeholder(for: champion, fontSize: 12),
                    size: 38,
                    championTitlesOverride: ChampionTitles([crown.title])
                )
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(ChampionTitleLine.periodName(for: crown.period)) CHAMPION")
                    .font(.montserratBold(size: 10))
                    .tracking(1.6)
                    .foregroundStyle(crown.title.tint)
                Text("\(ChampionNames.joined(champions.map(\.identity.displayName))) · \(crown.winningSteps.formatted()) steps")
                    .font(.montserratBold(size: 14))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(
                    colors: [crown.title.tint.opacity(0.14), RecapStyle.tileFill],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(crown.title.tint.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
