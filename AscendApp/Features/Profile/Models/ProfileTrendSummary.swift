import Foundation

struct ProfileTrendSummary: Equatable {
    let currentSteps: Int
    let previousSteps: Int
    let daysWithData: Int

    var hasData: Bool {
        currentSteps > 0 || previousSteps > 0
    }

    var isFullMonthComparison: Bool {
        daysWithData >= 28
    }

    var changePercent: Int? {
        guard previousSteps > 0 else { return nil }
        let percent = Double(currentSteps - previousSteps) / Double(previousSteps) * 100
        return Int(percent.rounded())
    }
}
