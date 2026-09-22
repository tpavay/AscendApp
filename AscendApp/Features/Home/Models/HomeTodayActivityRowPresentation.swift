import Foundation

/// The words a today row shows, derived from what the row is and what the device can
/// name. Pure so the copy for every session kind is unit-testable.
///
/// Titles come from content the app already ships - the climb catalog and the routine
/// templates - never from text another climber typed: a personal routine's name is the
/// climber's own and stays private, so that row reads as a routine and opens nothing.
/// A Live Climb the device's catalog cannot name has no Climb Detail to open either,
/// so its row is not a door: a chevron that leads nowhere is worse than none.
struct HomeTodayActivityRowPresentation: Equatable {
    /// Where a tap on the row leads.
    enum Destination: Equatable {
        case climbDetail(climbId: String)
        case justClimb(JustClimbGoal)
        case routineTemplate(templateId: String)
        case none
    }

    let title: String
    let detail: String
    let destination: Destination

    var isTappable: Bool {
        destination != .none
    }

    init(
        row: ModeratedHomeTodayActivityRow,
        climbName: String?,
        routineTemplateName: String?,
        now: Date = Date()
    ) {
        let elapsed = Self.elapsedText(since: row.publishedAt, now: now)
        let steps = "\(row.steps.formatted()) steps"
        let time = DurationFormatter.format(duration: row.durationSeconds)

        switch row.kind {
        case .liveClimb:
            title = climbName ?? "Live Climb"
            detail = [time, steps, elapsed].joined(separator: " · ")
            if climbName != nil, let climbId = row.climbId {
                destination = .climbDetail(climbId: climbId)
            } else {
                destination = .none
            }
        case .justClimb:
            title = "Just Climb"
            let goal = row.justClimbGoal ?? JustClimbGoal(kind: .open)
            let goalText: String
            switch goal.kind {
            case .open:
                goalText = time
            case .duration:
                goalText = "\(time) of \(goal.durationMinutes) min"
            case .steps:
                goalText = "\(row.steps.formatted()) of \(goal.stepCount.formatted()) steps"
            }
            detail = goal.kind == .steps
                ? [goalText, time, elapsed].joined(separator: " · ")
                : [goalText, steps, elapsed].joined(separator: " · ")
            destination = .justClimb(goal)
        case .routineTemplate:
            title = routineTemplateName ?? "Routine"
            detail = [time, steps, elapsed].joined(separator: " · ")
            destination = row.routineTemplateId.map { .routineTemplate(templateId: $0) } ?? .none
        case .routine:
            title = "Routine"
            detail = [time, steps, elapsed].joined(separator: " · ")
            destination = .none
        }
    }

    /// "just now", "4 min ago", "2 h ago", "3 d ago": coarse on purpose, because a
    /// feed line is glanced at and the server's publish time is the only clock.
    static func elapsedText(since date: Date, now: Date) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        if seconds < 60 {
            return "just now"
        }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes) min ago"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) h ago"
        }
        let days = hours / 24
        return "\(days) d ago"
    }
}
