import Foundation

/// Everything a climber can unlock for their athlete, and how each is earned: hosted beside the
/// climb catalogue (`web/public/unlocks/catalog.json`) and bundled as a fallback, so an event's
/// dates move, a threshold changes, or an item a build already draws goes live, without a new
/// build ("ship dark, drop live"). A new shape still needs a build; an item whose shape, slot or
/// way of earning this build does not know is skipped rather than failing the catalogue.
///
/// The seasonal carried items are its first instance: earned by climbing during an event.
struct UnlockCatalog: Decodable, Equatable, Sendable {
    let version: Int
    let events: [UnlockEvent]
    let items: [UnlockItem]

    static let empty = UnlockCatalog(version: 0, events: [], items: [])

    init(version: Int, events: [UnlockEvent], items: [UnlockItem]) {
        self.version = version
        self.events = events
        self.items = items
    }

    private enum CodingKeys: String, CodingKey { case version, events, items }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        events = try container.decode([UnlockEvent].self, forKey: .events)
        items = try container.decode([Lenient<UnlockItem>].self, forKey: .items).compactMap(\.value)
    }

    func event(id: String) -> UnlockEvent? {
        events.first { $0.id == id }
    }

    /// Every event that has opened by `date`: what the editor offers, earned or not.
    func openedEvents(by date: Date, calendar: Calendar = .current) -> [UnlockEvent] {
        events.filter { event in
            event.interval(in: calendar).map { $0.start <= date } ?? false
        }
    }

    /// The items an event awards that are switched on, in the catalogue's order.
    func items(earnedIn event: UnlockEvent) -> [UnlockItem] {
        items.filter { $0.status == .live && $0.earn.event == event.id }
    }

    /// The item an event gives to everybody who opens Ascend during it, if it has one.
    func visitItem(of event: UnlockEvent) -> UnlockItem? {
        items(earnedIn: event).first { $0.earn.metric == .visits }
    }

    /// The item drawn as `shape`, for naming what a climber carries.
    func item(shape: AthleteGear) -> UnlockItem? {
        items.first { $0.shape == shape }
    }
}

/// A stretch of days during which climbing earns its items: Halloween is October.
struct UnlockEvent: Decodable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    /// The event's name as copy uses it: "Halloween".
    let title: String
    /// The span its climbs are counted over in copy: "October".
    let monthName: String
    /// The first day of the event, and the first day after it, in the climber's own calendar.
    let startsOn: Day
    let endsBefore: Day

    /// A calendar day, `YYYY-MM-DD`, read in the climber's time zone: a climb at 11pm on
    /// October 31 counts for Halloween wherever it is climbed.
    struct Day: Decodable, Equatable, Hashable, Sendable {
        let year: Int
        let month: Int
        let day: Int

        init(year: Int, month: Int, day: Int) {
            self.year = year
            self.month = month
            self.day = day
        }

        init(from decoder: Decoder) throws {
            let text = try decoder.singleValueContainer().decode(String.self)
            let parts = text.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a YYYY-MM-DD day: \(text)"))
            }
            self.init(year: parts[0], month: parts[1], day: parts[2])
        }

        func start(in calendar: Calendar) -> Date? {
            calendar.date(from: DateComponents(year: year, month: month, day: day))
        }
    }

    func interval(in calendar: Calendar) -> DateInterval? {
        guard let start = startsOn.start(in: calendar), let end = endsBefore.start(in: calendar), start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard let interval = interval(in: calendar) else { return false }
        return date >= interval.start && date < interval.end
    }
}

/// One thing a climber can unlock: the shape it is drawn as, the slot it goes in, and what
/// earns it.
struct UnlockItem: Decodable, Equatable, Hashable, Sendable {
    enum Slot: String, Decodable, Sendable {
        /// Held in the arms up the mountain.
        case carry
    }

    enum Status: String, Decodable, Sendable {
        /// Shipped in the build but not offered yet.
        case hidden
        /// Offered and earnable.
        case live
        /// No longer earnable; kept by everyone who earned it.
        case retired
    }

    /// How an item is earned.
    struct Earn: Decodable, Equatable, Hashable, Sendable {
        enum Path: String, Decodable, Sendable {
            /// By climbing during an event's days.
            case event
        }

        enum Metric: String, Decodable, Sendable {
            /// Opening Ascend during the event: the item everybody who shows up gets.
            case visits
            /// Climbs finished in Ascend.
            case climbs
            /// Steps those climbs added up to.
            case steps
        }

        let path: Path
        let event: String
        let metric: Metric
        let threshold: Int
    }

    let id: String
    let shape: AthleteGear
    let slot: Slot
    let rarity: String?
    let status: Status
    let earn: Earn

    init(id: String, shape: AthleteGear, slot: Slot = .carry, rarity: String? = nil, status: Status = .live, earn: Earn) {
        self.id = id
        self.shape = shape
        self.slot = slot
        self.rarity = rarity
        self.status = status
        self.earn = earn
    }

    private enum CodingKeys: String, CodingKey { case id, shape, slot, rarity, status, earn }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        shape = try container.decode(AthleteGear.self, forKey: .shape)
        slot = try container.decode(Slot.self, forKey: .slot)
        rarity = try container.decodeIfPresent(String.self, forKey: .rarity)
        status = try container.decode(Status.self, forKey: .status)
        earn = try container.decode(Earn.self, forKey: .earn)
        guard earn.threshold > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .earn, in: container, debugDescription: "A threshold must be positive")
        }
    }
}

/// A catalogue entry decoded if this build understands it, and skipped if not.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
