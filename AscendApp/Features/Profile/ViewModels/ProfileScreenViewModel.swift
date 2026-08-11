import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ProfileScreenViewModel {
    var standings: [ProfileStanding] = []
    var achievements: ProfileAchievementLadder = .empty
    var firstAscentsHeld: [ProfileFirstAscentSummary] = []
    var openFirstAscents: [ProfileFirstAscentSummary] = []
    var otherUserSnapshot: ProfileSnapshot?
    var comparison: ProfileComparisonSummary?
    var errorMessage: String?
    var isLoading = false

    var hasLoadedOwnIdentity: Bool {
        ownIdentity != nil
    }

    private let profileRepository: ProfileRepository
    private let standingService: ProfileStandingService
    private let firstAscentService: ProfileFirstAscentService
    private var ownIdentity: ProfileUserIdentity?
    private var otherUserIdentity: ProfileUserIdentity?
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
        modelContext: ModelContext,
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

        async let loadedAchievements = loadAchievements(userId: userId)
        async let firstAscentSummaries = firstAscentService.loadFirstAscentSummaries(
            userId: userId,
            climbs: climbs
        )

        standings = await standingService.loadOwnStandings(
            userId: userId,
            modelContext: modelContext
        )
        achievements = await loadedAchievements
        let summaries = await firstAscentSummaries
        firstAscentsHeld = summaries.held
        openFirstAscents = summaries.open
    }

    func loadOtherUser(
        userId: String,
        initialIdentity: ResolvedUserIdentity,
        viewerSnapshot: ProfileSnapshot,
        climbs: [Climb],
        taskKey: String
    ) async {
        guard lastLoadedOtherKey != taskKey else { return }
        lastLoadedOtherKey = taskKey
        isLoading = true
        errorMessage = nil
        let seedIdentity = Self.initialOtherUserIdentity(
            userId: userId,
            initialIdentity: initialIdentity
        )
        // A hidden climber contributes no presentation values either, so an empty
        // remote field falls through to the stable UID-derived handle instead of
        // adopting the placeholder label as if it were an account name.
        let fallbackDisplayName = initialIdentity.isHidden ? "" : initialIdentity.displayName
        let fallbackPhotoURL = initialIdentity.isHidden ? nil : initialIdentity.photoURL
        otherUserIdentity = seedIdentity

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
            // Records first: only they name the exact finishing rank. The banded counters are
            // the fallback, and a ladder built from them proves no #2 or #3.
            let achievements = bundle.achievements.isEmpty
                ? ProfileAchievementLadder(bandedCounters: bundle.stats?.achievementCounts ?? .zero)
                : ProfileAchievementLadder(records: bundle.achievements)
            let fallbackStats = fallbackStatsSnapshot(
                summaries: bundle.workoutSummaries,
                firstAscentCount: firstAscents.held.count,
                achievementCounts: achievements.counts
            )
            let stats = mergedStats(remote: bundle.stats, fallback: fallbackStats)
            otherUserIdentity = (bundle.identity ?? seedIdentity)?
                .applyingPresentationFallback(
                    displayName: fallbackDisplayName,
                    photoURL: fallbackPhotoURL
                )

            let snapshot = ProfileSnapshotBuilder.makeRemoteSnapshot(
                demographics: otherUserDemographics(userId: userId),
                stats: stats,
                achievements: achievements,
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
            otherUserIdentity = seedIdentity
            otherUserSnapshot = ProfileSnapshotBuilder.makeRemoteSnapshot(
                demographics: otherUserDemographics(userId: userId),
                stats: .empty,
                achievements: .empty,
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

    /// Pre-populates the screen from the identity it was navigated with.
    ///
    /// That identity is already resolved, so no raw name or photo has to travel
    /// with the navigation. A hidden climber seeds nothing at all: the screen
    /// keeps rendering the placeholder it arrived with until the remote profile
    /// loads and can be moderated on its own terms.
    nonisolated static func initialOtherUserIdentity(
        userId: String,
        initialIdentity: ResolvedUserIdentity
    ) -> ProfileUserIdentity? {
        guard !initialIdentity.isHidden else { return nil }

        return ProfileUserIdentity(
            userId: userId,
            displayName: initialIdentity.displayName,
            photoURL: initialIdentity.photoURL
        )
    }

    func ownDemographics(
        userId: String,
        displayName: String,
        photoURL: URL?,
        joinedAt: Date?
    ) -> ProfileDemographicsSnapshot {
        ownProfileIdentity(
            userId: userId,
            displayName: displayName,
            photoURL: photoURL,
            joinedAt: joinedAt
        ).demographicsSnapshot
    }

    func resolvedOwnIdentity(
        using moderationStore: ModerationStore,
        userId: String,
        displayName: String,
        photoURL: URL?,
        joinedAt: Date?
    ) -> ResolvedUserIdentity {
        moderationStore.moderate(
            ownProfileIdentity(
                userId: userId,
                displayName: displayName,
                photoURL: photoURL,
                joinedAt: joinedAt
            ),
            isCurrentUser: true
        )
    }

    func otherUserDemographics(userId: String) -> ProfileDemographicsSnapshot {
        otherUserIdentity?.demographicsSnapshot ??
            ProfileDemographicsSnapshot(userId: userId)
    }

    func resolvedOtherIdentity(
        using moderationStore: ModerationStore,
        fallback: ResolvedUserIdentity
    ) -> ResolvedUserIdentity {
        guard let otherUserIdentity else {
            return fallback
        }

        return moderationStore.moderate(
            otherUserIdentity,
            isCurrentUser: false
        )
    }

    /// Prefers the finalized records - they carry the exact finishing rank of every period -
    /// and falls back to the banded `profile_stats` counters only when none arrived. The
    /// fallback ladder can prove no exact placement, so it withholds those badges.
    private func loadAchievements(userId: String) async -> ProfileAchievementLadder {
        do {
            let records = try await profileRepository.fetchAchievements(userId: userId)
            if !records.isEmpty {
                return ProfileAchievementLadder(records: records)
            }

            let stats = try await profileRepository.fetchStats(userId: userId)
            return ProfileAchievementLadder(bandedCounters: stats?.achievementCounts ?? .zero)
        } catch {
            return .empty
        }
    }

    private func loadOwnIdentity(
        userId: String,
        displayName: String,
        photoURL: URL?,
        joinedAt: Date?
    ) async -> ProfileUserIdentity {
        let storedProfile = try? await UserDataRepository.shared.getUserFromFirestore(userId: userId)
        let storedDisplayName = storedProfile?.resolvedDisplayName
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

    private func ownProfileIdentity(
        userId: String,
        displayName: String,
        photoURL: URL?,
        joinedAt: Date?
    ) -> ProfileUserIdentity {
        if let ownIdentity {
            return ownIdentity.applyingPresentationFallback(
                displayName: displayName,
                photoURL: photoURL,
                joinedAt: joinedAt
            )
        }

        return ProfileUserIdentity(
            userId: userId,
            displayName: displayName,
            photoURL: photoURL,
            joinedAt: joinedAt
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
