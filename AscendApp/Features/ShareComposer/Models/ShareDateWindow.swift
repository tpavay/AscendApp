import Foundation

/// A year, or a month inside a year, that the camera roll can be scoped to.
///
/// Deliberately not a free date range: "I know it was the 14th" is not a real memory, "August" is.
/// Pure so the window arithmetic is testable without a photo library.
struct ShareDateWindow: Equatable, Hashable, Sendable {
    let year: Int
    /// 1...12, or `nil` for the whole year.
    let month: Int?

    init(year: Int, month: Int? = nil) {
        self.year = year
        self.month = month.flatMap { (1...12).contains($0) ? $0 : nil }
    }

    /// The half-open interval this window covers, or `nil` if the calendar cannot build it.
    ///
    /// Half-open on purpose: `creationDate >= start AND creationDate < end` cannot double-count an
    /// asset created at midnight on the boundary.
    func dateInterval(calendar: Calendar = .current) -> DateInterval? {
        var components = DateComponents()
        components.year = year
        components.month = month ?? 1
        components.day = 1

        guard let start = calendar.date(from: components) else { return nil }
        let step: DateComponents = month == nil
            ? DateComponents(year: 1)
            : DateComponents(month: 1)
        guard let end = calendar.date(byAdding: step, to: start) else { return nil }

        return DateInterval(start: start, end: end)
    }

    /// What the sheet's button and any accessibility label call this window.
    func displayName(calendar: Calendar = .current) -> String {
        guard month != nil, let interval = dateInterval(calendar: calendar) else {
            return String(year)
        }
        return interval.start.formatted(.dateTime.month(.abbreviated).year())
    }
}
