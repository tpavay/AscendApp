import Foundation

enum ProfileAchievementType: String, CaseIterable {
    case firstAscent = "first_ascent"
    case weeklyTop1 = "weekly_top_1"
    case weeklyTop3 = "weekly_top_3"
    case weeklyTop10 = "weekly_top_10"
    case weeklyTop100 = "weekly_top_100"
    case monthlyTop1 = "monthly_top_1"
    case monthlyTop3 = "monthly_top_3"
    case monthlyTop10 = "monthly_top_10"
    case monthlyTop100 = "monthly_top_100"
    case yearlyTop1 = "yearly_top_1"
    case yearlyTop3 = "yearly_top_3"
    case yearlyTop10 = "yearly_top_10"
    case yearlyTop100 = "yearly_top_100"

    var rankBand: ProfileAchievementRankBand? {
        switch self {
        case .firstAscent:
            nil
        case .weeklyTop1, .monthlyTop1, .yearlyTop1:
            .top1
        case .weeklyTop3, .monthlyTop3, .yearlyTop3:
            .top3
        case .weeklyTop10, .monthlyTop10, .yearlyTop10:
            .top10
        case .weeklyTop100, .monthlyTop100, .yearlyTop100:
            .top100
        }
    }

    var timeFrame: LeaderboardTimeFrame? {
        switch self {
        case .firstAscent:
            nil
        case .weeklyTop1, .weeklyTop3, .weeklyTop10, .weeklyTop100:
            .weekly
        case .monthlyTop1, .monthlyTop3, .monthlyTop10, .monthlyTop100:
            .monthly
        case .yearlyTop1, .yearlyTop3, .yearlyTop10, .yearlyTop100:
            .yearly
        }
    }
}

enum ProfileAchievementRankBand: String, Identifiable, Sendable {
    case top1
    case top3
    case top10
    case top100

    var id: String { rawValue }

    var threshold: Int {
        switch self {
        case .top1:
            1
        case .top3:
            3
        case .top10:
            10
        case .top100:
            100
        }
    }

    var label: String {
        switch self {
        case .top1:
            ProfileTerminology.topOneAchievementLabel
        case .top3:
            ProfileTerminology.topThreeAchievementLabel
        case .top10:
            ProfileTerminology.topTenAchievementLabel
        case .top100:
            ProfileTerminology.topHundredAchievementLabel
        }
    }
}

enum ProfileAchievementScope: String {
    case global
    case climb
}

enum ProfileAchievementMetric: String {
    case steps
    case completionTime = "completion_time"
}

struct ProfileAchievementRecord: Identifiable, Equatable {
    let id: String
    let type: ProfileAchievementType
    let scope: ProfileAchievementScope
    let metric: ProfileAchievementMetric?
    let climbId: String?
    let periodKey: String?
    let periodStartAt: Date?
    let periodEndAt: Date?
    let earnedAt: Date
    let rank: Int?
    let value: Int?
    let valueUnit: String?

    var rankBand: ProfileAchievementRankBand? {
        type.rankBand
    }

    var timeFrame: LeaderboardTimeFrame? {
        type.timeFrame
    }

    func countsToward(_ band: ProfileAchievementRankBand) -> Bool {
        guard let rankBand else { return false }
        return rankBand.threshold <= band.threshold
    }
}

struct ProfileAchievementCounts: Equatable {
    var top1: Int
    var top3: Int
    var top10: Int
    var top100: Int

    static let zero = ProfileAchievementCounts(top1: 0, top3: 0, top10: 0, top100: 0)

    init(top1: Int, top3: Int, top10: Int, top100: Int) {
        self.top1 = max(top1, 0)
        self.top3 = max(top3, self.top1, 0)
        self.top10 = max(top10, self.top3, 0)
        self.top100 = max(top100, self.top10, 0)
    }

    /// Reads the band counts out of a published `profile_stats` document.
    init(statsDocument data: [String: Any]) {
        self.init(
            top1: Self.finishCount(band: "1", in: data),
            top3: Self.finishCount(band: "3", in: data),
            top10: Self.finishCount(band: "10", in: data),
            top100: Self.finishCount(band: "100", in: data)
        )
    }

    /// Reads a band's finish count, falling back to the misnamed `_weeks` key so profiles
    /// published before the rename keep their badges until their next publication rewrites
    /// them. Remove the fallback after 2026-10-01.
    private static func finishCount(band: String, in data: [String: Any]) -> Int {
        intValue(for: "top_\(band)_finishes", in: data)
            ?? intValue(for: "top_\(band)_weeks", in: data)
            ?? 0
    }

    private static func intValue(for key: String, in data: [String: Any]) -> Int? {
        if let value = data[key] as? Int { return value }
        if let value = data[key] as? Int64 { return Int(value) }
        if let value = data[key] as? Double { return Int(value) }
        if let value = data[key] as? NSNumber { return value.intValue }
        return nil
    }

    init(records: [ProfileAchievementRecord]) {
        var top1 = 0
        var top3 = 0
        var top10 = 0
        var top100 = 0

        for record in records {
            switch record.type.rankBand {
            case .top1:
                top1 += 1
                top3 += 1
                top10 += 1
                top100 += 1
            case .top3:
                top3 += 1
                top10 += 1
                top100 += 1
            case .top10:
                top10 += 1
                top100 += 1
            case .top100:
                top100 += 1
            case nil:
                break
            }
        }

        self.init(top1: top1, top3: top3, top10: top10, top100: top100)
    }
}
