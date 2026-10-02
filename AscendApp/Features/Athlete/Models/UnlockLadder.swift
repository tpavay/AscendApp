import Foundation

/// One row of an event's page: the items one kind of climbing earns, in the order it earns them,
/// with how far the climber has come along it. Halloween has three - climbs, steps and days - and
/// every item the event awards sits on exactly one of them.
struct UnlockLadder: Equatable, Identifiable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        /// Opening Ascend and climbing: the first rung is the item for showing up.
        case climbs
        case steps
        /// Different days climbed, and climbing on one named day.
        case days

        static func of(_ metric: UnlockItem.Earn.Metric) -> Kind {
            switch metric {
            case .visits, .climbs: .climbs
            case .steps: .steps
            case .days, .onDay: .days
            }
        }
    }

    /// Where one item stands for this climber.
    enum State: Equatable, Sendable {
        case earned
        /// The first item on its ladder not yet earned.
        case next
        case locked
    }

    let kind: Kind
    let items: [UnlockItem]
    /// The climber's count along this ladder: climbs, steps, or different days climbed.
    let count: Int
    /// The count the ladder's last rung asks for, which a full bar reaches.
    let goal: Int
    private let earned: Set<AthleteGear>

    var id: Kind { kind }

    /// How full the ladder's bar is, 0 to 1.
    var fraction: Double {
        goal > 0 ? min(Double(count) / Double(goal), 1) : 0
    }

    func state(of item: UnlockItem) -> State {
        if earned.contains(item.shape) { return .earned }
        return items.first { !earned.contains($0.shape) } == item ? .next : .locked
    }

    /// The ladders of `progress`'s event that hold an item, climbs first. `owned` adds what the
    /// climber earned on this device that their climbs alone no longer show, such as the open-app
    /// item after a reinstall, so a tile never reads locked for something they have.
    static func ladders(for progress: UnlockEventProgress, owned: Set<AthleteGear> = []) -> [UnlockLadder] {
        let earned = Set(progress.earned).union(owned)
        return Kind.allCases.compactMap { kind in
            let items = progress.items
                .filter { Kind.of($0.earn.metric) == kind }
                .sorted { (rank($0.earn.metric), $0.earn.threshold) < (rank($1.earn.metric), $1.earn.threshold) }
            guard !items.isEmpty else { return nil }
            let count = switch kind {
            case .climbs: progress.climbs
            case .steps: progress.steps
            case .days: progress.days
            }
            let goal = items.filter { $0.earn.metric != .visits && $0.earn.metric != .onDay }.map(\.earn.threshold).max() ?? 0
            return UnlockLadder(kind: kind, items: items, count: count, goal: goal, earned: earned)
        }
    }

    /// Within a ladder, showing up comes before climbing, and a count before a named day.
    private static func rank(_ metric: UnlockItem.Earn.Metric) -> Int {
        switch metric {
        case .visits: 0
        case .climbs, .steps, .days: 1
        case .onDay: 2
        }
    }
}

/// How far one locked item is: "4 of 5 climbs", "1 to go".
struct UnlockItemProgress: Equatable, Sendable {
    let have: Int
    let need: Int
    let unit: String

    var remaining: Int { max(need - have, 0) }
    var fraction: Double { need > 0 ? min(Double(have) / Double(need), 1) : 0 }

    /// Nil for an item that is not counted toward, such as climbing on one named day.
    init?(item: UnlockItem, progress: UnlockEventProgress) {
        let need = item.earn.threshold
        switch item.earn.metric {
        case .climbs:
            self.init(have: progress.climbs, need: need, unit: need == 1 ? "climb" : "climbs")
        case .steps:
            self.init(have: progress.steps, need: need, unit: "steps")
        case .days:
            self.init(have: progress.days, need: need, unit: need == 1 ? "day" : "days")
        case .visits, .onDay:
            return nil
        }
    }

    init(have: Int, need: Int, unit: String) {
        self.have = have
        self.need = need
        self.unit = unit
    }
}

extension UnlockEvent {
    /// Days left in the event counting today, so the last day reads 1 and the day after 0.
    func daysLeft(now: Date = .now, calendar: Calendar = .current) -> Int {
        guard let end = interval(in: calendar)?.end else { return 0 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: end).day ?? 0
        return max(days, 0)
    }
}
