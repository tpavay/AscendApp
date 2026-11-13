import Foundation

/// The numbers and judgments Apple Health import runs on, with no store and no HealthKit in them.
enum AppleHealthImportPolicy {
    /// How far back the red badge looks.
    static let badgeWindow: TimeInterval = 7 * 24 * 60 * 60

    /// How long an automatic import keeps asking for the Home strip before it gives up and lets
    /// the climb simply be a climb.
    static let noticeLifetime: TimeInterval = 24 * 60 * 60

    /// How long the Undo toast stays up after an import.
    static let undoWindow: Duration = .seconds(5)

    /// A live climb and a Health workout are the same session when their windows share this much.
    static let overlapThreshold: TimeInterval = 60

    /// Whether two time windows intersect by the overlap threshold or more.
    static func windowsOverlap(_ firstStart: Date, _ firstEnd: Date, _ secondStart: Date, _ secondEnd: Date) -> Bool {
        let overlapStart = max(firstStart, secondStart)
        let overlapEnd = min(firstEnd, secondEnd)
        return overlapEnd.timeIntervalSince(overlapStart) >= overlapThreshold
    }

    /// A workout shorter than a second or longer than a day cannot be a climb, whatever Health
    /// says it is: a day is the longest one climb can run (`ClimbPacePolicy.maximumDuration`).
    static func isImportableDuration(_ duration: TimeInterval) -> Bool {
        duration >= 1 && duration <= ClimbPacePolicy.maximumDuration
    }

    /// The steps an imported climb is allowed to carry.
    ///
    /// Health's number is kept exactly - until it is one no stair stepper produces. A save the
    /// climber types is refused at 300 steps a minute or 120,000 steps because the cloud would
    /// refuse the same climb on every sync forever; an import cannot be refused, since the climber
    /// asked for nothing, so the one implausible number is dropped instead and the climb arrives
    /// with the Add steps prompt rather than as a climb that can never back up.
    static func importableSteps(_ steps: Int?, duration: TimeInterval) -> Int? {
        guard let steps, steps > 0, steps <= ClimbPacePolicy.maximumSteps else { return nil }
        guard ClimbPacePolicy.verdict(steps: steps, duration: duration).isSaveable else { return nil }
        return steps
    }

    /// The local notification's title and body. Steps are the climb's number and never "~"; a
    /// climb with none says so rather than naming a number.
    static func notificationContent(steps: Int?) -> (title: String, body: String) {
        let title = "Climb imported"
        guard let steps else {
            return (title, "Your stair stepper workout from Apple Health is in. Tap to add your steps.")
        }
        return (
            title,
            "Your \(steps.formatted())-step stair stepper workout from Apple Health is in. Tap to add a note or photo."
        )
    }
}
