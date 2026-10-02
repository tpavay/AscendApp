import Foundation
import Observation
import SwiftData

/// The unlock catalogue in force, and which items the signed-in climber has earned.
///
/// Event items are derived, never granted: an item is earned when the climbs the climber
/// finished in Ascend during its event reach its threshold, counted from the local store - which
/// a reinstall restores from the climber's cloud backup, so a new phone earns the same items
/// back. What has been earned is also remembered on the device for the signed-in account, so an
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
    private(set) var userId: String?
    /// The events the climber has opened Ascend during, and the ones whose intro they have seen.
    @ObservationIgnored private var visited: Set<String> = []
    @ObservationIgnored private var introsSeen: Set<String> = []

    @ObservationIgnored private let repository: UnlockCatalogRepository
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isFlagEnabled: @MainActor () -> Bool
    @ObservationIgnored private var refreshedCatalog = false

    static let earnedKey = "unlocks.earned"

    private struct Cached: Codable {
        let userId: String
        let earned: [String]
        var visited: [String]?
        var introsSeen: [String]?
    }

    init(
        repository: UnlockCatalogRepository = HostedUnlockCatalogRepository(),
        defaults: UserDefaults = .standard,
        isFlagEnabled: @escaping @MainActor () -> Bool = { RemoteFeatureFlagStore.shared.isEnabled(.unlocks) }
    ) {
        self.repository = repository
        self.defaults = defaults
        self.isFlagEnabled = isFlagEnabled
        catalog = repository.loadInitialCatalog()
    }

    /// Whether unlockable items are shown, offered and drawn at all.
    var isEnabled: Bool { isFlagEnabled() }

    /// The item a look is drawn carrying: none while unlocks are switched off.
    func drawnCarry(for look: AthleteLook) -> AthleteGear? {
        isEnabled ? look.carry : nil
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
        let progress = catalog.openedEvents(by: now, calendar: calendar).reversed().compactMap { event in
            (try? UnlockClimbQuery.climbs(in: event, calendar: calendar, modelContext: modelContext)).map {
                UnlockEventProgress(event: event, items: catalog.items(earnedIn: event), climbs: $0, visited: visited.contains(event.id), calendar: calendar)
            }
        }
        remember(progress.flatMap(\.earned), for: userId)
        return progress
    }

    /// What one finished climb did for the event it fell in: where the climber stands now, and
    /// anything that climb itself earned. Nil when the climb fell outside every event.
    func outcome(of workout: Workout, userId: String, modelContext: ModelContext, calendar: Calendar = .current) -> UnlockClimbOutcome? {
        guard isEnabled,
              let event = catalog.events.first(where: { $0.contains(workout.date, calendar: calendar) }),
              let climbs = try? UnlockClimbQuery.climbs(in: event, calendar: calendar, modelContext: modelContext) else { return nil }
        let items = catalog.items(earnedIn: event)
        guard !items.isEmpty else { return nil }
        load(userId: userId)
        let wasVisited = visited.contains(event.id)
        let after = UnlockEventProgress(event: event, items: items, climbs: climbs, visited: wasVisited, calendar: calendar)
        let before = UnlockEventProgress(event: event, items: items, climbs: climbs.filter { $0.id != workout.id }, visited: wasVisited, calendar: calendar)
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
        defaults.removeObject(forKey: Self.earnedKey)
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
            introsSeen: introsSeen.sorted()
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

/// What one finished climb did for its event.
struct UnlockClimbOutcome: Equatable, Sendable {
    let progress: UnlockEventProgress
    let newlyEarned: [AthleteGear]
}

/// The climbs an event counts: the ones Ascend recorded inside its days. Bounded by the event,
/// never by the climber's whole history.
enum UnlockClimbQuery {
    static func climbs(in event: UnlockEvent, calendar: Calendar, modelContext: ModelContext) throws -> [UnlockEventProgress.Climb] {
        guard let interval = event.interval(in: calendar) else { return [] }
        let source = WorkoutSource.headphoneMotion.rawValue
        let start = interval.start, end = interval.end
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.sourceRawValue == source && workout.date >= start && workout.date < end
            }
        )
        descriptor.propertiesToFetch = [\.id, \.date, \.steps]
        return try modelContext.fetch(descriptor).map { UnlockEventProgress.Climb(id: $0.id, date: $0.date, steps: $0.steps) }
    }
}
