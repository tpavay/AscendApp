import Foundation
import Observation

/// Where this climb starts on Ascend Mountain: every step the climber has climbed in Ascend,
/// across every climb before this one (captain, round 16: "your climbs add up"; round 11:
/// "Victor has climbed 15,000 in total, so his climb today happens around 15,000").
///
/// The total is read two ways and the larger wins, because each lags in its own way:
/// - the phone's all-time aggregate (`LeaderboardService`), which holds a climb the moment it is
///   saved and needs no network, but knows only the climbs on this phone;
/// - the server's all-time standing (`leaderboard_stats`), derived from every climb backed up
///   from every phone, remembered per climber from the last time it was read.
///
/// The climb never waits for either. A climber with no reading yet starts at the foot of the
/// mountain, and the scene takes a later reading only while they are still on the start line.
@MainActor
@Observable
final class MountainJourney {
    private(set) var startSteps = 0

    @ObservationIgnored private let source: MountainJourneyTotalSource
    @ObservationIgnored private let defaults: UserDefaults

    init(source: MountainJourneyTotalSource = LeaderboardMountainJourneyTotalSource(), defaults: UserDefaults = .standard) {
        self.source = source
        self.defaults = defaults
    }

    /// Starts from what the phone already knows, then asks the server and remembers its answer
    /// for the next climb, online or not.
    func load(userId: String?) async {
        let local = source.localTotalSteps(userId: userId)
        guard let userId else {
            startSteps = Self.start(local: local, remembered: nil)
            return
        }
        startSteps = Self.start(local: local, remembered: remembered(userId: userId))
        guard let server = try? await source.serverTotalSteps(userId: userId) else { return }
        defaults.set(server, forKey: Self.rememberedKey(userId: userId))
        startSteps = Self.start(local: local, remembered: server)
    }

    static func start(local: Int?, remembered: Int?) -> Int {
        max(local ?? 0, remembered ?? 0, 0)
    }

    func remembered(userId: String) -> Int? {
        defaults.object(forKey: Self.rememberedKey(userId: userId)) as? Int
    }

    /// Kept per climber, so a phone shared between accounts never starts one on another's total.
    static func rememberedKey(userId: String) -> String {
        "AscendMountainJourneyTotal.\(userId)"
    }
}

/// The two readings of a climber's all-time total the journey starts from.
@MainActor
protocol MountainJourneyTotalSource {
    func localTotalSteps(userId: String?) -> Int?
    func serverTotalSteps(userId: String) async throws -> Int
}

/// Reads both totals where the global all-time leaderboard keeps them, so the mountain counts
/// exactly the climbs the climber's all-time standing counts.
@MainActor
struct LeaderboardMountainJourneyTotalSource: MountainJourneyTotalSource {
    var service: LeaderboardService = .shared
    var repository: LeaderboardRepository = .shared

    func localTotalSteps(userId: String?) -> Int? {
        guard let userId else { return nil }
        return try? service.getLocalStats(for: userId, timeFrame: .allTime)?.totalSteps
    }

    func serverTotalSteps(userId: String) async throws -> Int {
        try await repository.fetchOwnTotalSteps(userId: userId, timeFrame: .allTime)
    }
}
