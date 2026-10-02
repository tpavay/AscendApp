import Foundation
import Observation
import SwiftData

/// The unlock catalogue in force, and which items the signed-in climber has earned.
///
/// Event items are derived, never granted: an item is earned when the climbs the climber
/// saved in Ascend during its event reach its threshold - every climb saved with progress counts,
/// a live climb stopped short of the top as much as one that reached it, counted from the local store - which
/// a reinstall restores from the climber's cloud backup, so a new phone earns the same climbing
/// items back. The visit item is the exception: opening Ascend is remembered only on the device
/// for the signed-in account, so after a sign-out or reinstall only a climb in the event earns it
/// again. What has been earned is also remembered on the device for the signed-in account, so an
/// unlock outlives a catalogue that later moves an event's dates. Nothing earned is taken away.
///
/// The general unlock plan moves deciding who earned what to the server; until it does, an event
/// item is a cosmetic the climber's own phone counts (`docs/seasonal-unlocks.md`).
@MainActor
@Observable
final class UnlockStore {
    static let shared = UnlockStore()

    private(set) var catalog: UnlockCatalog
    /// Everything the climber has earned.
    private(set) var earned: Set<AthleteGear> = []
    /// Earned items the climber has looked at since earning them; the rest read NEW.
    private(set) var seen: Set<AthleteGear> = []
    private(set) var userId: String?
    /// The events the climber has opened Ascend during, and the ones whose intro they have seen.
    @ObservationIgnored private var visited: Set<String> = []
    @ObservationIgnored private var introsSeen: Set<String> = []

    @ObservationIgnored private let repository: UnlockCatalogRepository
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isFlagEnabled: @MainActor () -> Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var refreshedCatalog = false

    static let earnedKey = "unlocks.earned"

    private struct Cached: Codable {
        let userId: String
        let earned: [String]
        var visited: [String]?
        var introsSeen: [String]?
        var seen: [String]?
    }

    init(
        repository: UnlockCatalogRepository = HostedUnlockCatalogRepository(),
        defaults: UserDefaults = .standard,
        isFlagEnabled: @escaping @MainActor () -> Bool = { RemoteFeatureFlagStore.shared.isEnabled(.unlocks) },
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.repository = repository
        self.defaults = defaults
        self.isFlagEnabled = isFlagEnabled
        self.now = now
        catalog = repository.loadInitialCatalog()
    }

    /// Whether unlockable items are shown, offered and drawn at all.
    var isEnabled: Bool { isFlagEnabled() }

    /// The items a look is drawn wearing: none while unlocks are switched off.
    func drawnGear(for look: AthleteLook) -> [AthleteGear] {
        isEnabled ? look.gear : []
    }

    /// How the running event dresses the mountain, if it does: none while unlocks are off.
    func runningTheme(now: Date = .now, calendar: Calendar = .current) -> UnlockEvent.Theme? {
        guard isEnabled else { return nil }
        return catalog.events.first { $0.contains(now, calendar: calendar) }?.theme
    }

    /// The event running now that has items to earn, while unlocks are switched on.
    func runningEvent(calendar: Calendar = .current) -> UnlockEvent? {
        guard isEnabled else { return nil }
        return catalog.events.first { $0.contains(now(), calendar: calendar) && !catalog.items(earnedIn: $0).isEmpty }
    }

    /// Days left in `event`: the one count every surface that says so reads.
    func daysLeft(in event: UnlockEvent, calendar: Calendar = .current) -> Int {
        event.daysLeft(now: now(), calendar: calendar)
    }

    /// The items of `event` the climber has earned, the open-app item included: the one earned
    /// count every surface that shows one reads.
    func earnedItems(in event: UnlockEvent) -> [UnlockItem] {
        catalog.items(earnedIn: event).filter { earned.contains($0.shape) }
    }

    /// Fetches the hosted catalogue once per launch, so an event can move without a build.
    func refreshCatalogIfNeeded() async {
        guard !refreshedCatalog else { return }
        refreshedCatalog = true
        if let fresh = try? await repository.refreshCatalog() {
            catalog = fresh
        }
    }

    /// Reads what `userId` has earned on this device.
    func load(userId: String) {
        guard self.userId != userId else { return }
        self.userId = userId
        let cached = self.cached(for: userId)
        earned = Set((cached?.earned ?? []).compactMap(AthleteGear.init(rawValue:)))
        visited = Set(cached?.visited ?? [])
        introsSeen = Set(cached?.introsSeen ?? [])
        seen = Set((cached?.seen ?? []).compactMap(AthleteGear.init(rawValue:)))
    }

    /// Records that the climber opened Ascend now, which earns every running event's visit item.
    func recordVisit(userId: String, now: Date = .now, calendar: Calendar = .current) {
        guard isEnabled else { return }
        load(userId: userId)
        let running = catalog.events.filter { $0.contains(now, calendar: calendar) && catalog.visitItem(of: $0) != nil }
        guard !running.isEmpty, !Set(running.map(\.id)).isSubset(of: visited) else { return }
        visited.formUnion(running.map(\.id))
        remember(running.compactMap { catalog.visitItem(of: $0)?.shape }, for: userId, force: true)
    }

    /// The running event whose intro the climber has not seen yet, if any.
    func pendingIntro(userId: String, now: Date = .now, calendar: Calendar = .current) -> UnlockEvent? {
        guard isEnabled else { return nil }
        load(userId: userId)
        return catalog.events.first { event in
            event.contains(now, calendar: calendar) && !introsSeen.contains(event.id) && !catalog.items(earnedIn: event).isEmpty
        }
    }

    func markIntroSeen(_ event: UnlockEvent, userId: String) {
        load(userId: userId)
        guard !introsSeen.contains(event.id) else { return }
        introsSeen.insert(event.id)
        persist(for: userId)
    }

    /// Recounts every event that has opened from the climbs in the store, and remembers anything
    /// newly earned. Returns each opened event's progress, the newest event first.
    @discardableResult
    func refresh(userId: String, modelContext: ModelContext, now: Date = .now, calendar: Calendar = .current) -> [UnlockEventProgress] {
        load(userId: userId)
        var retired: [AthleteGear] = []
        let progress = catalog.openedEvents(by: now, calendar: calendar).reversed().compactMap { event -> UnlockEventProgress? in
            guard let climbs = try? UnlockClimbQuery.climbs(in: event, calendar: calendar, modelContext: modelContext) else { return nil }
            retired += catalog.retiredItems(earnedIn: event, by: climbs, calendar: calendar)
            return UnlockEventProgress(event: event, items: catalog.items(earnedIn: event), climbs: climbs, visited: visited.contains(event.id), calendar: calendar)
        }
        remember(progress.flatMap(\.earned) + retired, for: userId)
        return progress
    }

    /// What one saved climb did for the event it fell in: where the climber stood once it was
    /// done, and anything that climb itself earned, so a reopened summary reads as it did at the
    /// finish. Nil when the climb fell outside every event.
    func outcome(of workout: Workout, userId: String, modelContext: ModelContext, calendar: Calendar = .current) -> UnlockClimbOutcome? {
        guard isEnabled,
              let event = catalog.events.first(where: { $0.contains(workout.date, calendar: calendar) }),
              let climbs = try? UnlockClimbQuery.climbs(in: event, calendar: calendar, modelContext: modelContext) else { return nil }
        let items = catalog.items(earnedIn: event)
        guard !items.isEmpty else { return nil }
        load(userId: userId)
        let wasVisited = visited.contains(event.id)
        let upToThisClimb = climbs.filter { $0.date <= workout.date }
        let after = UnlockEventProgress(event: event, items: items, climbs: upToThisClimb, visited: wasVisited, calendar: calendar)
        let before = UnlockEventProgress(event: event, items: items, climbs: upToThisClimb.filter { $0.id != workout.id }, visited: wasVisited, calendar: calendar)
        remember(after.earned, for: userId)
        return UnlockClimbOutcome(progress: after, newlyEarned: after.newlyEarned(since: before))
    }

    /// Forgets the account's unlocks on this device, on sign-out and account deletion. The next
    /// account counts its own climbs.
    func clearAccountScopedState() {
        userId = nil
        earned = []
        visited = []
        introsSeen = []
        seen = []
        defaults.removeObject(forKey: Self.earnedKey)
    }

    /// Earned items the climber has not looked at yet: only ones Your Athlete draws, and never
    /// one the athlete is `wearing`, so every NEW counted is a NEW tag the climber can see.
    func newItems(wearing: [AthleteGear]) -> Set<AthleteGear> {
        let drawn = catalog.events.flatMap { catalog.gearItems(of: $0, owned: earned) }.map(\.shape)
        return Set(drawn).intersection(earned).subtracting(seen).subtracting(wearing)
    }

    /// Records that the climber has looked at `items`, which stops them reading NEW.
    func markSeen(_ items: some Sequence<AthleteGear>, userId: String) {
        load(userId: userId)
        let fresh = Set(items).intersection(earned).subtracting(seen)
        guard !fresh.isEmpty else { return }
        seen.formUnion(fresh)
        persist(for: userId)
    }

    private func remember(_ items: [AthleteGear], for userId: String, force: Bool = false) {
        guard force || !Set(items).isSubset(of: earned) else { return }
        earned.formUnion(items)
        persist(for: userId)
    }

    private func persist(for userId: String) {
        let cached = Cached(
            userId: userId,
            earned: earned.map(\.rawValue).sorted(),
            visited: visited.sorted(),
            introsSeen: introsSeen.sorted(),
            seen: seen.map(\.rawValue).sorted()
        )
        guard let data = try? JSONEncoder().encode(cached) else { return }
        defaults.set(data, forKey: Self.earnedKey)
    }

    private func cached(for userId: String) -> Cached? {
        guard let data = defaults.data(forKey: Self.earnedKey),
              let cached = try? JSONDecoder().decode(Cached.self, from: data),
              cached.userId == userId else { return nil }
        return cached
    }
}

/// What one saved climb did for its event.
struct UnlockClimbOutcome: Equatable, Sendable {
    let progress: UnlockEventProgress
    let newlyEarned: [AthleteGear]
}

/// The climbs an event counts: every one Ascend recorded and saved with progress inside its days,
/// finished or stopped short - a live climb ended early, a routine stopped partway, a session
/// recovered after the app was closed. A climb with no steps is not progress and never counts.
/// Bounded by the event, never by the climber's whole history.
enum UnlockClimbQuery {
    static func climbs(in event: UnlockEvent, calendar: Calendar, modelContext: ModelContext) throws -> [UnlockEventProgress.Climb] {
        guard let interval = event.interval(in: calendar) else { return [] }
        let source = WorkoutSource.headphoneMotion.rawValue
        let start = interval.start, end = interval.end
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.sourceRawValue == source && workout.steps > 0 && workout.date >= start && workout.date < end
            }
        )
        descriptor.propertiesToFetch = [\.id, \.date, \.steps]
        return try modelContext.fetch(descriptor).map { UnlockEventProgress.Climb(id: $0.id, date: $0.date, steps: $0.steps) }
    }
}
