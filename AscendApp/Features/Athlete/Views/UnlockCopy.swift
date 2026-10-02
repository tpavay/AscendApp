import Foundation

extension AthleteGear {
    /// The item's picture in the asset catalogue, photographed from the real model.
    var thumbnailName: String { "Gear/\(rawValue)" }
}

/// The words unlock surfaces use, in one place so the editor and the unlock moment agree.
enum UnlockCopy {
    /// "10 CLIMBS", "25K STEPS", "EVERY DAY".
    static func requirement(_ item: UnlockItem, in event: UnlockEvent? = nil) -> String {
        let threshold = item.earn.threshold
        switch item.earn.metric {
        case .visits: return "OPEN ASCEND"
        case .climbs: return threshold == 1 ? "1 CLIMB" : "\(threshold) CLIMBS"
        case .days:
            if let event, threshold == event.dayCount() { return "EVERY DAY" }
            return threshold == 1 ? "1 DAY" : "\(threshold) DAYS"
        case .steps: return "\(compact(threshold)) STEPS"
        case .onDay:
            guard let event, let day = event.date(ofDay: threshold) else { return "1 DAY" }
            return "CLIMB \(day.formatted(.dateTime.month(.abbreviated).day()).uppercased())"
        }
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
            return "\(amount) to the \(next.item.shape.title)"
        }
    }

    static func compact(_ value: Int) -> String {
        value >= 1_000 && value % 1_000 == 0 ? "\(value / 1_000)K" : value.formatted()
    }
}
