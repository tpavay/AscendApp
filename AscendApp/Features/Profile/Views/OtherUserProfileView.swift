import SwiftData
import SwiftUI

struct OtherUserProfileView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Query(sort: \Workout.date, order: .reverse) private var viewerWorkouts: [Workout]
    @Query(sort: \ClimbAttempt.startedAt, order: .reverse) private var viewerClimbAttempts: [ClimbAttempt]
    @Query(sort: \BestEffortCacheEntry.sortKey) private var viewerBestEffortCacheEntries: [BestEffortCacheEntry]

    @State private var viewModel = ProfileScreenViewModel()
    @State private var settingsManager = SettingsManager.shared
    @State private var catalogRevision = 0

    let userId: String
    let seedDisplayName: String
    let seedPhotoURL: URL?

    init(userId: String, seedDisplayName: String, seedPhotoURL: URL? = nil) {
        self.userId = userId
        self.seedDisplayName = seedDisplayName
        self.seedPhotoURL = seedPhotoURL
    }

    private var climbs: [Climb] {
        _ = catalogRevision
        return (try? ClimbService.shared.loadVisibleClimbs()) ?? []
    }

    private var seedIdentity: ProfileUserIdentity {
        ProfileUserIdentity(
            userId: userId,
            displayName: seedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Climber" : seedDisplayName,
            photoURL: seedPhotoURL
        )
    }

    private var viewerSnapshot: ProfileSnapshot {
        ProfileSnapshotBuilder.makeOwnSnapshot(
            identity: ProfileUserIdentity(
                userId: authVM.user?.uid ?? "viewer",
                displayName: authVM.displayName,
                photoURL: authVM.displayPhotoURL,
                joinedAt: authVM.user?.metadata.creationDate
            ),
            workouts: viewerWorkouts,
            climbAttempts: viewerClimbAttempts,
            bestEffortCacheEntries: viewerBestEffortCacheEntries,
            achievements: .zero,
            standings: [],
            climbs: climbs,
            fitnessLevel: settingsManager.fitnessLevel
        )
    }

    private var loadingSnapshot: ProfileSnapshot {
        ProfileSnapshotBuilder.makeRemoteSnapshot(
            identity: seedIdentity,
            stats: .empty,
            achievements: .zero,
            standings: [],
            workoutSummaries: [],
            firstAscentsHeld: [],
            openFirstAscents: [],
            climbs: climbs
        )
    }

    private var taskKey: String {
        "\(userId)-\(viewerWorkouts.count)-\(viewerClimbAttempts.count)-\(catalogRevision)"
    }

    var body: some View {
        let snapshot = viewModel.otherUserSnapshot ?? loadingSnapshot

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                IdentityHeroSection(
                    snapshot: snapshot,
                    mode: .otherUser,
                    measurementSystem: settingsManager.measurementSystem
                )

                VStack(alignment: .leading, spacing: 16) {
                    if let comparison = viewModel.comparison, comparison.state != .hidden {
                        ComparisonBlock(comparison: comparison)
                    }

                    if snapshot.hasActiveRank {
                        ActiveStandingsSection(standings: snapshot.standings)
                    }

                    if snapshot.totalClimbsCompleted > 0 {
                        ActivityCalendarSection(
                            workouts: snapshot.activityWorkouts,
                            currentStreakWeeks: snapshot.stats.currentStreakWeeks,
                            bestStreakWeeks: snapshot.stats.bestStreakWeeks,
                            mode: .otherUser
                        )
                    }

                    if snapshot.totalClimbsCollected > 0 {
                        CollectionSection(collection: snapshot.collection, mode: .otherUser)
                    }

                    if snapshot.totalMedalWeeks > 0 {
                        AchievementsSection(counts: snapshot.achievements, mode: .otherUser)
                    }

                    if snapshot.totalFirstAscents > 0 {
                        FirstAscentsSection(
                            held: snapshot.firstAscentsHeld,
                            open: [],
                            mode: .otherUser,
                            climbs: climbs
                        )
                    }

                    if snapshot.totalClimbsCompleted > 0 {
                        RecordsSection(
                            records: snapshot.records,
                            totalClimbsCompleted: snapshot.totalClimbsCompleted,
                            workouts: []
                        )
                        TrendsSection(trend: snapshot.trends)
                        RecentWorkoutsSection(
                            workouts: snapshot.recentWorkouts,
                            mode: .otherUser,
                            localWorkouts: []
                        )
                    }

                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 118)
            }
        }
        .scrollIndicators(.hidden)
        .background(ProfileVisualStyle.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: taskKey) {
            await viewModel.loadOtherUser(
                userId: userId,
                seedIdentity: seedIdentity,
                viewerSnapshot: viewerSnapshot,
                climbs: climbs,
                taskKey: taskKey
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbCatalogDidChange)) { _ in
            catalogRevision += 1
        }
    }
}
