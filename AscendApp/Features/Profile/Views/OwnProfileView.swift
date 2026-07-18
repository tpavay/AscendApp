import SwiftData
import SwiftUI

struct OwnProfileView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @Query(sort: \ClimbAttempt.startedAt, order: .reverse) private var climbAttempts: [ClimbAttempt]
    @Query(sort: \BestEffortCacheEntry.sortKey) private var bestEffortCacheEntries: [BestEffortCacheEntry]

    private let viewModel: ProfileScreenViewModel
    @State private var settingsManager = SettingsManager.shared
    @State private var catalogRevision = 0
    @State private var selectedSegment: OwnProfileSegment = .overview
    @State private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme

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
            completedClimbSet: ClimbCompletionRepository.shared.read(modelContext: modelContext),
            bestEffortCacheEntries: bestEffortCacheEntries,
            achievements: viewModel.achievements,
            achievementRecords: viewModel.achievementRecords,
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

        VStack(spacing: 0) {
            IdentityHeroSection(
                snapshot: snapshot,
                mode: .own
            )

            ProfileSegmentToggle(selection: $selectedSegment)
                .padding(.horizontal, 16)
                .padding(.top, 18)

            Group {
                switch selectedSegment {
                case .overview:
                    overviewContent(snapshot)
                case .activity:
                    activityContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
                modelContext: modelContext,
                taskKey: supportTaskKey
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbCatalogDidChange)) { _ in
            catalogRevision += 1
        }
    }

    private func overviewContent(_ snapshot: ProfileSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ProfileLifetimeStatsRow(
                    climbs: workouts.count,
                    steps: snapshot.stats.lifetimeTotalSteps,
                    durationSeconds: snapshot.stats.lifetimeDurationSeconds,
                    averageStepsPerMinute: snapshot.stats.averageStepsPerMinute
                )

                CollectionSection(
                    collection: snapshot.collection,
                    mode: .own,
                    showsHeader: false
                )

                ProfileWeeklyStepsChart(workouts: snapshot.activityWorkouts)

                if snapshot.hasActiveRank {
                    ActiveStandingsSection(standings: snapshot.standings)
                }

                PrestigeSection(
                    held: snapshot.firstAscentsHeld,
                    open: snapshot.openFirstAscents,
                    achievements: snapshot.achievements,
                    achievementRecords: snapshot.achievementRecords,
                    mode: .own
                )

                RecordBookSection(
                    records: snapshot.records,
                    workouts: workouts
                )

                ActivityCalendarSection(
                    workouts: snapshot.activityWorkouts,
                    currentStreakWeeks: snapshot.stats.currentStreakWeeks,
                    bestStreakWeeks: snapshot.stats.bestStreakWeeks,
                    mode: .own
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 118)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var activityContent: some View {
        if workouts.isEmpty {
            activityEmptyState
        } else {
            WorkoutResultsListView(
                filteredWorkouts: workouts,
                allWorkouts: workouts,
                isInDeleteMode: false,
                effectiveColorScheme: themeManager.effectiveColorScheme(for: colorScheme),
                selectedWorkouts: [],
                toggleSelection: { _ in }
            )
        }
    }

    private var activityEmptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Text("Nothing logged yet.")
                .font(.montserratBold(size: 19))
                .foregroundStyle(.white)

            Text("Climb a landmark — your first session lands here.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(ProfileVisualStyle.secondaryText)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 36)
        .padding(.bottom, 90)
    }
}
