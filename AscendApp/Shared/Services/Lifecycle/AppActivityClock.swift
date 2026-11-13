import Foundation

/// When this process launched and when it last came to the foreground.
///
/// Recorded with a failed server read, because the two moments Firestore's stream is most likely
/// to be down are the seconds after a cold launch and the seconds after a resume - and nothing
/// on the phone said which, if either, a failure followed.
@MainActor
final class AppActivityClock {
    static let shared = AppActivityClock()

    private let launchedAt: Date
    private var foregroundedAt: Date
    private(set) var hasEnteredBackground = false

    init(launchedAt: Date = .now) {
        self.launchedAt = launchedAt
        self.foregroundedAt = launchedAt
    }

    func recordWillEnterForeground(at date: Date = .now) {
        foregroundedAt = date
    }

    /// Whether this process has ever left the foreground. Until it has, anything that arrives is
    /// arriving on the launch that started it - a link that opened the app cold.
    func recordDidEnterBackground() {
        hasEnteredBackground = true
    }

    func secondsSinceLaunch(at date: Date = .now) -> Int {
        Self.wholeSeconds(from: launchedAt, to: date)
    }

    /// Equal to `secondsSinceLaunch` until the app has been backgrounded and brought back.
    func secondsSinceForeground(at date: Date = .now) -> Int {
        Self.wholeSeconds(from: foregroundedAt, to: date)
    }

    private static func wholeSeconds(from start: Date, to end: Date) -> Int {
        max(Int(end.timeIntervalSince(start)), 0)
    }
}
