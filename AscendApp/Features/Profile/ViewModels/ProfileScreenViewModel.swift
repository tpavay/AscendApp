import Foundation
import Observation

@MainActor
@Observable
final class ProfileScreenViewModel {
    var standings: [ProfileStanding] = []
    var achievements: ProfileAchievementCounts = .zero
    var firstAscentsHeld: [ProfileFirstAscentSummary] = []
    var openFirstAscents: [ProfileFirstAscentSummary] = []
    var ownIdentity: ProfileUserIdentity?
    var otherUserSnapshot: ProfileSnapshot?
    var comparison: ProfileComparisonSummary?
    var errorMessage: String?
    var isLoading = false

    private let profileRepository: ProfileRepository
    private let standingService: ProfileStandingService
    private let firstAscentService: ProfileFirstAscentService
    private var lastLoadedOwnKey: String?
    private var lastLoadedOtherKey: String?

    init(
        profileRepository: ProfileRepository = .shared,
        standingService: ProfileStandingService = .shared,
        firstAscentService: ProfileFirstAscentService = .shared
    ) {
        self.profileRepository = profileRepository
        self.standingService = standingService
        self.firstAscentService = firstAscentService
    }

    func loadOwnSupport(
        userId: String,
        displayName: String,
        photoURL: URL?,
        joinedAt: Date?,
        climbs: [Climb],
        taskKey: String,
        forceRefresh: Bool = false
    ) async {
        guard forceRefresh || lastLoadedOwnKey != taskKey else { return }
        lastLoadedOwnKey = taskKey
        errorMessage = nil

        ownIdentity = await loadOwnIdentity(
            userId: userId,
            displayName: displayName,
            photoURL: photoURL,
            joinedAt: joinedAt
        )

        async let loadedStandings = standingService.loadStandings(userId: userId)
        async let loadedAchievements = loadAchievementCounts(userId: userId)
        async let firstAscentSummaries = firstAscentService.loadFirstAscentSummaries(
            userId: userId,
            climbs: climbs
        )

        standings = await loadedStandings
        achievements = await loadedAchievements
        let summaries = await firstAscentSummaries
        firstAscentsHeld = summaries.held
        openFirstAscents = summaries.open
    }

    func loadOtherUser(
        userId: String,
        seedIdentity: ProfileUserIdentity,
        viewerSnapshot: ProfileSnapshot,
        climbs: [Climb],
        taskKey: String
    ) async {
        guard lastLoadedOtherKey != taskKey else { return }
        lastLoadedOtherKey = taskKey
        isLoading = true
        errorMessage = nil

        do {
            async let remoteBundle = profileRepository.fetchRemoteBundle(userId: userId)
            async let loadedStandings = standingService.loadStandings(userId: userId)
            async let firstAscentSummaries = firstAscentService.loadFirstAscentSummaries(
                userId: userId,
                climbs: climbs
            )

            let bundle = try await remoteBundle
            let standings = await loadedStandings
            let firstAscents = await firstAscentSummaries
            let achievementCounts = bundle.stats?.achievementCounts ?? ProfileAchievementCounts(records: bundle.achievements)
            let fallbackStats = fallbackStatsSnapshot(
                summaries: bundle.workoutSummaries,
                firstAscentCount: firstAscents.held.count,
                achievementCounts: achievementCounts
            )
            let stats = mergedStats(remote: bundle.stats, fallback: fallbackStats)
            var identity = bundle.identity ?? seedIdentity
            if identity.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                identity.displayName = seedIdentity.displayName
            }

            let snapshot = ProfileSnapshotBuilder.makeRemoteSnapshot(
                identity: identity,
                stats: stats,
                achievements: achievementCounts,
                standings: standings,
                workoutSummaries: bundle.workoutSummaries,
                firstAscentsHeld: firstAscents.held,
                openFirstAscents: firstAscents.open,
                climbs: climbs
            )

            otherUserSnapshot = snapshot
            comparison = ProfileSnapshotBuilder.comparison(
                viewer: viewerSnapshot,
                otherUser: snapshot
            )
        } catch {
            errorMessage = "Couldn't load this profile right now."
            otherUserSnapshot = ProfileSnapshotBuilder.makeRemoteSnapshot(
                identity: seedIdentity,
                stats: .empty,
                achievements: .zero,
                standings: [],
                workoutSummaries: [],
                firstAscentsHeld: [],
                openFirstAscents: [],
                climbs: climbs
            )
            comparison = nil
        }

        isLoading = false
    }

    private func loadAchievementCounts(userId: String) async -> ProfileAchievementCounts {
        do {
            let stats = try await profileRepository.fetchStats(userId: userId)
            if let stats {
                return stats.achievementCounts
            }

            let records = try await profileRepository.fetchAchievements(userId: userId)
            return ProfileAchievementCounts(records: records)
        } catch {
            return .zero
        }
    }

    private func loadOwnIdentity(
        userId: String,
        displayName: String,
        photoURL: URL?,
        joinedAt: Date?
    ) async -> ProfileUserIdentity {
        let storedProfile = try? await UserDataRepository.shared.getUserFromFirestore(userId: userId)
        let storedDisplayName = storedProfile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDisplayName: String
        if let storedDisplayName, !storedDisplayName.isEmpty {
            resolvedDisplayName = storedDisplayName
        } else {
            resolvedDisplayName = displayName
        }

        return ProfileUserIdentity(
            userId: userId,
            displayName: resolvedDisplayName,
            photoURL: storedProfile?.profilePictureURL.flatMap(URL.init(string:)) ?? photoURL,
            age: storedProfile?.age,
            gender: storedProfile?.gender.flatMap(ProfileGender.init(rawValue:)),
            weightKg: storedProfile?.weightKg,
            heightCm: storedProfile?.heightCm,
            locationCity: storedProfile?.locationCity,
            locationCountryCode: storedProfile?.locationCountry,
            locationRegionCode: storedProfile?.locationRegion,
            joinedAt: storedProfile?.joinedAt ?? joinedAt
        )
    }

    private func fallbackStatsSnapshot(
        summaries: [ProfileWorkoutSummary],
        firstAscentCount: Int,
        achievementCounts: ProfileAchievementCounts
    ) -> ProfileStatsSnapshot {
        let lifetimeTotalSteps = summaries.reduce(0) { $0 + $1.steps }
        let lifetimeDurationSeconds = Int(summaries.reduce(0.0) { $0 + $1.durationSeconds }.rounded())
        let completedClimbIds = Set(summaries.filter(\.isCompletedClimb).compactMap(\.climbId))

        return ProfileStatsSnapshot(
            totalClimbsCompleted: completedClimbIds.count,
            totalFirstAscents: firstAscentCount,
            achievementCounts: achievementCounts,
            mostCompletedClimbId: nil,
            currentStreakWeeks: 0,
            bestStreakWeeks: 0,
            prMostSteps: summaries.map(\.steps).max() ?? 0,
            prLongestClimbSeconds: Int((summaries.map(\.durationSeconds).max() ?? 0).rounded()),
            prHighestSPM: bestSPM(from: summaries),
            lifetimeTotalSteps: lifetimeTotalSteps,
            lifetimeDurationSeconds: lifetimeDurationSeconds,
            totalClimbs: summaries.count,
            averageStepsPerMinute: lifetimeDurationSeconds > 0
                ? Double(lifetimeTotalSteps) / (Double(lifetimeDurationSeconds) / 60.0)
                : 0
        )
    }

    private func mergedStats(
        remote: ProfileStatsSnapshot?,
        fallback: ProfileStatsSnapshot
    ) -> ProfileStatsSnapshot {
        guard var remote else { return fallback }

        if remote.lifetimeTotalSteps == 0 && fallback.lifetimeTotalSteps > 0 {
            remote.lifetimeTotalSteps = fallback.lifetimeTotalSteps
        }
        if remote.lifetimeDurationSeconds == 0 && fallback.lifetimeDurationSeconds > 0 {
            remote.lifetimeDurationSeconds = fallback.lifetimeDurationSeconds
        }
        if remote.totalClimbs == 0 && fallback.totalClimbs > 0 {
            remote.totalClimbs = fallback.totalClimbs
        }
        if remote.averageStepsPerMinute == 0 && fallback.averageStepsPerMinute > 0 {
            remote.averageStepsPerMinute = fallback.averageStepsPerMinute
        }
        if remote.totalClimbsCompleted == 0 && fallback.totalClimbsCompleted > 0 {
            remote.totalClimbsCompleted = fallback.totalClimbsCompleted
        }
        if remote.prMostSteps == 0 && fallback.prMostSteps > 0 {
            remote.prMostSteps = fallback.prMostSteps
        }
        if remote.prLongestClimbSeconds == 0 && fallback.prLongestClimbSeconds > 0 {
            remote.prLongestClimbSeconds = fallback.prLongestClimbSeconds
        }
        if remote.prHighestSPM == 0 && fallback.prHighestSPM > 0 {
            remote.prHighestSPM = fallback.prHighestSPM
        }

        return remote
    }

    private func bestSPM(from summaries: [ProfileWorkoutSummary]) -> Double {
        summaries
            .filter { $0.durationSeconds > 0 }
            .map { Double($0.steps) / ($0.durationSeconds / 60.0) }
            .max() ?? 0
    }
}
