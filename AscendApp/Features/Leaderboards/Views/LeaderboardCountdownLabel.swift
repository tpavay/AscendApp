import SwiftUI

/// `ENDS IN 2D 14H` in lime, gold on the last day.
///
/// It ticks once a minute, never per second: a board is read, not watched, and a
/// per-second timer would re-render the whole header for a digit nobody is waiting on.
struct LeaderboardCountdownLabel: View {
    private enum Window {
        case fixed(LeaderboardPeriod)
        /// Whichever period of this frame is open at each tick, so a label left on screen
        /// across a reset starts counting down the new period.
        case current(LeaderboardTimeFrame)
    }

    private let window: Window
    private let fontSize: CGFloat
    /// Fixes the clock for evidence tests and previews.
    private let now: Date?

    init(period: LeaderboardPeriod, fontSize: CGFloat = 10, now: Date? = nil) {
        window = .fixed(period)
        self.fontSize = fontSize
        self.now = now
    }

    init(currentPeriodOf timeFrame: LeaderboardTimeFrame, fontSize: CGFloat = 10, now: Date? = nil) {
        window = .current(timeFrame)
        self.fontSize = fontSize
        self.now = now
    }

    var body: some View {
        if let now {
            label(at: now)
        } else {
            TimelineView(.everyMinute) { context in
                label(at: context.date)
            }
        }
    }

    private func period(at date: Date) -> LeaderboardPeriod {
        switch window {
        case .fixed(let period): period
        case .current(let timeFrame): timeFrame.currentPeriod(referenceDate: date)
        }
    }

    @ViewBuilder
    private func label(at date: Date) -> some View {
        if let countdown = LeaderboardCountdown.make(period: period(at: date), now: date) {
            Text(countdown.text)
                .font(.montserratBold(size: fontSize))
                .foregroundStyle(countdown.isLastDay ? Color.championGold : Color.accent)
                .lineLimit(1)
                .accessibilityLabel(countdown.accessibilityLabel(now: date))
        }
    }
}
