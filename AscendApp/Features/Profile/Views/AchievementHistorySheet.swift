import SwiftUI

struct AchievementHistorySheet: View {
    @Environment(\.dismiss) private var dismiss

    let band: ProfileAchievementRankBand
    let records: [ProfileAchievementRecord]

    private var sortedRecords: [ProfileAchievementRecord] {
        records.sorted {
            if $0.earnedAt != $1.earnedAt {
                return $0.earnedAt > $1.earnedAt
            }
            return ($0.rank ?? Int.max) < ($1.rank ?? Int.max)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if sortedRecords.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 10) {
                            ForEach(sortedRecords) { record in
                                AchievementHistoryRow(record: record)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(ProfileVisualStyle.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
            }
        }
        .presentationBackground(ProfileVisualStyle.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(band.label.uppercased())
                .font(.montserratBold(size: 28))
                .foregroundStyle(.white)
                .tracking(1.2)

            Text("Final leaderboard finishes. Exact rank and steps are locked when the period closes.")
                .font(.montserratMedium(size: 13))
                .foregroundStyle(ProfileVisualStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        ProfileCardSurfaceView {
            VStack(alignment: .leading, spacing: 8) {
                Text("No finalized rows yet.")
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(.white)

                Text("Finish a leaderboard period inside \(band.label) and the proof lands here.")
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(ProfileVisualStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }
}

private struct AchievementHistoryRow: View {
    let record: ProfileAchievementRecord

    var body: some View {
        ProfileCardSurfaceView {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.montserratBold(size: 14))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(subtitle)
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(ProfileVisualStyle.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(rankText)
                        .font(.montserratBold(size: 24))
                        .foregroundStyle(Color.ascendAccent)
                        .lineLimit(1)

                    Text(valueText)
                        .font(.montserratSemiBold(size: 11))
                        .foregroundStyle(ProfileVisualStyle.secondaryText)
                        .tracking(0.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle), \(rankText), \(valueText)")
    }

    private var title: String {
        if let timeFrame = record.timeFrame {
            return "\(timeFrame.displayName) Steps"
        }
        return record.scope == .climb ? "Climb Finish" : "Leaderboard Finish"
    }

    private var subtitle: String {
        if let periodText {
            return periodText
        }
        if let periodKey = record.periodKey {
            return periodKey
        }
        return "Earned \(ProfileDateFormatters.shortDate(record.earnedAt))"
    }

    private var periodText: String? {
        guard let startAt = record.periodStartAt else { return nil }

        switch record.timeFrame {
        case .weekly:
            let endAt = record.periodEndAt.map { Calendar.current.date(byAdding: .day, value: -1, to: $0) ?? $0 }
            guard let endAt else { return ProfileDateFormatters.shortDate(startAt) }
            return "\(Self.monthDayFormatter.string(from: startAt)) - \(Self.shortDateFormatter.string(from: endAt))"
        case .monthly:
            return Self.monthFormatter.string(from: startAt)
        case .yearly:
            return Self.yearFormatter.string(from: startAt)
        case .daily:
            return ProfileDateFormatters.shortDate(startAt)
        case .allTime:
            return "All time"
        case nil:
            return ProfileDateFormatters.shortDate(startAt)
        }
    }

    private var rankText: String {
        guard let rank = record.rank, rank > 0 else {
            return record.rankBand?.label ?? "Ranked"
        }
        return "#\(rank)"
    }

    private var valueText: String {
        guard let value = record.value, value > 0 else {
            return record.valueUnit?.uppercased() ?? "STEPS"
        }

        let formatted = value.formatted(.number.grouping(.automatic))
        switch record.valueUnit {
        case "seconds":
            return ProfileDateFormatters.compactDuration(TimeInterval(value)).uppercased()
        default:
            return "\(formatted) STEPS"
        }
    }

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter
    }()
}
