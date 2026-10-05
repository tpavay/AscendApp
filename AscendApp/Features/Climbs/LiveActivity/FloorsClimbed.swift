import Foundation

/// How Ascend turns a step count into floors climbed.
///
/// One definition for every surface: the `floors` a saved workout stores - which the weekly
/// recap and the leaderboard totals sum - and the figure drawn while that climb is still
/// running. A live screen that counted floors its own way would disagree with the workout it
/// becomes the moment the climb is saved.
///
/// It lives in this folder because the widget extension compiles these files and not
/// `Workout`, so the Lock Screen reads the same rule the app does.
enum FloorsClimbed {
    static let stepsPerFloor = 16

    /// Whole floors, rounded to the nearest: half a floor of steps is where the count turns over.
    static func count(forSteps steps: Int, stepsPerFloor: Int = stepsPerFloor) -> Int {
        guard stepsPerFloor > 0 else { return 0 }
        return Int((Double(steps) / Double(stepsPerFloor)).rounded())
    }

    /// The count with its noun, for a line that states floors in running text: `77 floors`.
    static func phrase(_ floors: Int) -> String {
        "\(floors.formatted()) floor\(floors == 1 ? "" : "s")"
    }

    static func phrase(forSteps steps: Int) -> String {
        phrase(count(forSteps: steps))
    }
}
