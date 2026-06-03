import SwiftData
import SwiftUI

struct OwnProfileView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @Query(sort: \ClimbAttempt.startedAt, order: .reverse) private var climbAttempts: [ClimbAttempt]
    @Query(sort: \BestEffortCacheEntry.sortKey) private var bestEffortCacheEntries: [BestEffortCacheEntry]

    private let viewModel: ProfileScreenViewModel
    @State private var settingsManager = SettingsManager.shared
    @State private var catalogRevision = 0

    init(viewModel: ProfileScreenViewModel = ProfileScreenViewModel()) {
        self.viewModel = viewModel
    }

    private var userId: String {
        authVM.user?.uid ?? "signed-out"
    }

    private var identity: ProfileUserIdentity {
        if var ownIdentity = viewModel.ownIdentity {
            if ownIdentity.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ownIdentity.displayName = displayName
            }
            if ownIdentity.photoURL == nil {
                ownIdentity.photoURL = authVM.displayPhotoURL
            }
            if ownIdentity.joinedAt == nil {
                ownIdentity.joinedAt = authVM.user?.metadata.creationDate
            }
            return ownIdentity
        }

        return ProfileUserIdentity(
            userId: userId,
            displayName: displayName,
            photoURL: authVM.displayPhotoURL,
            joinedAt: authVM.user?.metadata.creationDate
        )
    }

    private var displayName: String {
        let trimmed = authVM.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Climber" : trimmed
    }

    private var climbs: [Climb] {
        _ = catalogRevision
        return (try? ClimbService.shared.loadVisibleClimbs()) ?? []
    }

    private var snapshot: ProfileSnapshot {
        var snapshot = ProfileSnapshotBuilder.makeOwnSnapshot(
            identity: identity,
            workouts: workouts,
            climbAttempts: climbAttempts,
            bestEffortCacheEntries: bestEffortCacheEntries,
            achievements: viewModel.achievements,
            standings: viewModel.standings,
            climbs: climbs,
            fitnessLevel: settingsManager.fitnessLevel
        )
        if !viewModel.firstAscentsHeld.isEmpty {
            snapshot.firstAscentsHeld = viewModel.firstAscentsHeld
            snapshot.stats.totalFirstAscents = viewModel.firstAscentsHeld.count
        }
        snapshot.openFirstAscents = viewModel.openFirstAscents
        return snapshot
    }

    private var supportTaskKey: String {
        let latestWorkout = workouts.first?.lastModifiedAt.timeIntervalSince1970 ?? 0
        let latestAttempt = climbAttempts.first?.startedAt.timeIntervalSince1970 ?? 0
        return "\(userId)-\(workouts.count)-\(climbAttempts.count)-\(latestWorkout)-\(latestAttempt)-\(catalogRevision)"
    }

    var body: some View {
        let snapshot = snapshot

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                IdentityHeroSection(
                    snapshot: snapshot,
                    mode: .own,
                    measurementSystem: settingsManager.measurementSystem
                )

                VStack(alignment: .leading, spacing: 16) {
                    if snapshot.hasActiveRank {
                        ActiveStandingsSection(standings: snapshot.standings)
                    }

                    ActivityCalendarSection(
                        workouts: snapshot.activityWorkouts,
                        currentStreakWeeks: snapshot.stats.currentStreakWeeks,
                        bestStreakWeeks: snapshot.stats.bestStreakWeeks,
                        mode: .own
                    )

                    CollectionSection(collection: snapshot.collection, mode: .own)
                    AchievementsSection(counts: snapshot.achievements, mode: .own)
                    FirstAscentsSection(
                        held: snapshot.firstAscentsHeld,
                        open: snapshot.openFirstAscents,
                        mode: .own,
                        climbs: climbs
                    )
                    RecordsSection(
                        records: snapshot.records,
                        totalClimbsCompleted: snapshot.totalClimbsCompleted,
                        workouts: workouts
                    )
                    TrendsSection(trend: snapshot.trends)
                    RecentWorkoutsSection(
                        workouts: snapshot.recentWorkouts,
                        mode: .own,
                        localWorkouts: workouts
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 118)
            }
        }
        .scrollIndicators(.hidden)
        .background(ProfileVisualStyle.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: supportTaskKey) {
            guard authVM.user != nil else { return }
            await viewModel.loadOwnSupport(
                userId: userId,
                displayName: displayName,
                photoURL: authVM.displayPhotoURL,
                joinedAt: authVM.user?.metadata.creationDate,
                climbs: climbs,
                taskKey: supportTaskKey
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbCatalogDidChange)) { _ in
            catalogRevision += 1
        }
    }
}
