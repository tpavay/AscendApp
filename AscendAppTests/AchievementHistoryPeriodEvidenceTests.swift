import Foundation
import SwiftUI
import Testing
@testable import AscendApp

/// Evidence that the shipping history sheet names each finish by the UTC window it was
/// ranked over. `ProfileAchievementPeriodLabelTests` owns the labels; this proves the
/// sheet renders them rather than re-deriving a date of its own.
///
/// Run with `TEST_RUNNER_TZ=America/Chicago` to read the sheet the way a US climber does,
/// where the August title used to read "July 2026" and the 2026 title "2025".
@MainActor
@Suite(.hostsAWindow)
struct AchievementHistoryPeriodEvidenceTests {
    @Test
    func theHistorySheetNamesEachFinishByItsUtcWindow() async throws {
        let records = [
            record(type: .monthlyTop1, timeFrame: .monthly, containing: utcDate(2026, 8, 15)),
            record(type: .yearlyTop1, timeFrame: .yearly, containing: utcDate(2026, 6, 1)),
            record(type: .weeklyTop1, timeFrame: .weekly, containing: utcDate(2026, 8, 1))
        ]
        let size = CGSize(width: 390, height: 700)

        try await RenderedScreen.host(
            AchievementHistorySheet(filter: .band(.top1), records: records)
                .frame(width: size.width, height: size.height, alignment: .top),
            size: size
        ) { screen in
            let copy = try await screen.copy { $0.contains("jul 27") }

            #expect(copy.contains("monthly steps, august 2026"), "\(copy)")
            #expect(copy.contains("yearly steps, 2026"), "\(copy)")
            #expect(copy.contains("weekly steps, jul 27 - aug 2, 2026"), "\(copy)")
            #expect(copy.contains("july 2026") == false, "\(copy)")
            #expect(copy.contains("2025") == false, "\(copy)")
            try screen.photograph(named: "achievement-history-utc-periods")
        }
    }

    private func record(
        type: ProfileAchievementType,
        timeFrame: LeaderboardTimeFrame,
        containing instant: Date
    ) -> ProfileAchievementRecord {
        let period = timeFrame.currentPeriod(referenceDate: instant)
        return ProfileAchievementRecord(
            id: "global_steps_\(timeFrame.rawValue)_\(period.key)",
            type: type,
            scope: .global,
            metric: .steps,
            climbId: nil,
            periodKey: period.key,
            periodStartAt: period.startAt,
            periodEndAt: period.endAt,
            earnedAt: period.endAt ?? instant,
            rank: 1,
            value: 42_000,
            valueUnit: "steps"
        )
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.calendar = WeekConfiguration.calendar(timeZone: LeaderboardTimeFrame.canonicalTimeZone)
        components.timeZone = LeaderboardTimeFrame.canonicalTimeZone
        components.year = year
        components.month = month
        components.day = day
        return components.date!
    }
}
