import Foundation

extension AthleteGear {
    /// The item's picture in the asset catalogue, photographed from the real model.
    var thumbnailName: String { "Gear/\(rawValue)" }
}

/// The words unlock surfaces use, in one place so the editor and the unlock moment agree.
enum UnlockCopy {
    /// What a climber's climbs this event earned before they first saw it: "Your October climbs
    /// already earned 3 more. They're marked below. Put them on in Your Athlete."
    static func alreadyEarned(_ count: Int, in event: UnlockEvent) -> String {
        let amount = count == 1 ? "1 more" : "\(count) more"
        return "Your \(event.monthName) climbs already earned \(amount). They're marked below. Put them on in Your Athlete."
    }

    /// What an item takes, as a bare count: "Open Ascend", "5 climbs", "10K steps", "7 days",
    /// "Every day", "Oct 31".
    static func threshold(_ item: UnlockItem, in event: UnlockEvent) -> String {
        let count = item.earn.threshold
        switch item.earn.metric {
        case .visits: return "Open Ascend"
        case .climbs: return count == 1 ? "1 climb" : "\(count) climbs"
        case .steps: return "\(compact(count)) steps"
        case .days:
            if count == event.dayCount() { return "Every day" }
            return count == 1 ? "1 day" : "\(count) days"
        case .onDay:
            return event.date(ofDay: count)?.formatted(.dateTime.month(.abbreviated).day()) ?? "1 day"
        }
    }

    /// What an item takes, in a sentence: "5 climbs in October", "Every day in October",
    /// "Climb on October 31".
    static func rule(_ item: UnlockItem, in event: UnlockEvent) -> String {
        switch item.earn.metric {
        case .onDay:
            let day = event.date(ofDay: item.earn.threshold)?.formatted(.dateTime.month(.wide).day()) ?? "the day"
            return "Climb on \(day)"
        default:
            return "\(threshold(item, in: event)) in \(event.monthName)"
        }
    }

    /// Where an item goes on the athlete: "CARRIED ON YOUR SHOULDER", "HELD OVER YOUR HEAD".
    static func slotLine(_ gear: AthleteGear) -> String {
        switch gear.slot {
        case .carry:
            switch gear.carry {
            case .shoulder: "CARRIED ON YOUR SHOULDER"
            case .overhead: "HELD OVER YOUR HEAD"
            case .tray: "CARRIED IN YOUR HAND"
            }
        case .head: "WORN ON YOUR HEAD"
        case .costume, .shorts: "WORN AS YOUR KIT"
        case .trainers: "ON YOUR FEET"
        }
    }

    /// A ladder's heading: "CLIMBS IN OCTOBER".
    static func ladderTitle(_ kind: UnlockLadder.Kind, in event: UnlockEvent) -> String {
        "\(kind.rawValue.uppercased()) IN \(event.monthName.uppercased())"
    }

    /// The unit after a ladder's count: "climbs" in "5 climbs".
    static func ladderUnit(_ ladder: UnlockLadder) -> String {
        switch ladder.kind {
        case .climbs: ladder.count == 1 ? "climb" : "climbs"
        case .steps: ladder.count == 1 ? "step" : "steps"
        case .days: ladder.count == 1 ? "day" : "days"
        }
    }

    /// "29 DAYS LEFT", then "LAST DAY".
    static func daysLeft(_ days: Int) -> String {
        days <= 1 ? "LAST DAY" : "\(days) DAYS LEFT"
    }

    /// The Home card's line: "4 of 15 earned. Climb for the rest."
    static func earnedLine(earned: Int, of total: Int) -> String {
        earned >= total ? "All \(total) earned." : "\(earned) of \(total) earned. Climb for the rest."
    }

    /// "4 CLIMBS · 12,400 STEPS".
    static func tally(_ progress: UnlockEventProgress) -> String {
        let climbs = progress.climbs == 1 ? "1 CLIMB" : "\(progress.climbs) CLIMBS"
        return "\(climbs) · \(progress.steps.formatted()) STEPS"
    }

    /// What is left on each ladder: "2 more climbs to the Ghost Pumpkin".
    static func nextLines(_ progress: UnlockEventProgress) -> [String] {
        progress.nextItems.map { next in
            let amount = switch next.item.earn.metric {
            case .visits: "Open Ascend"
            case .climbs: next.remaining == 1 ? "1 more climb" : "\(next.remaining) more climbs"
            case .days: next.remaining == 1 ? "1 more day climbing" : "\(next.remaining) more days climbing"
            case .steps: "\(next.remaining.formatted()) more steps"
            case .onDay: "Climb that day"
            }
            let title = next.item.shape.title
            return "\(amount) to \(title.hasPrefix("The ") ? title : "the \(title)")"
        }
    }

    static func compact(_ value: Int) -> String {
        value >= 1_000 && value % 1_000 == 0 ? "\(value / 1_000)K" : value.formatted()
    }
}
