import Foundation

@MainActor
enum ProfileSnapshotBuilder {
    static func makeOwnSnapshot(
        identity: ProfileUserIdentity,
        workouts: [Workout],
        climbAttempts: [ClimbAttempt],
        bestEffortCacheEntries: [BestEffortCacheEntry],
        achievements: ProfileAchievementCounts,
        standings: [ProfileStanding],
        climbs: [Climb],
        fitnessLevel: FitnessLevel,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ProfileSnapshot {
        let ownedWorkouts = workouts.sorted { $0.date > $1.date }
        let completedAttempts = climbAttempts
            .filter { $0.status == .completed }
            .sorted { ClimbService.attemptSortDate(for: $0) > ClimbService.attemptSortDate(for: $1) }
        let stats = statsSnapshot(
            workouts: ownedWorkouts,
            completedAttempts: completedAttempts,
            achievements: achievements
        )
        let summaries = workoutSummaries(
            from: ownedWorkouts,
            climbAttempts: climbAttempts,
            climbs: climbs
        )
        let records = recordSummary(
            workouts: ownedWorkouts,
            bestEffortCacheEntries: bestEffortCacheEntries
        )

        return ProfileSnapshot(
            identity: identity,
            stats: stats,
            standings: standings,
            activityWorkouts: summaries,
            collection: collectionSummary(
                completedAttempts: completedAttempts,
                climbs: climbs,
                fitnessLevel: fitnessLevel
            ),
            achievements: achievements,
            firstAscentsHeld: firstAscentsHeld(
                completedAttempts: completedAttempts,
                climbs: climbs
            ),
            openFirstAscents: [],
            records: records,
            trends: trendSummary(workouts: ownedWorkouts, now: now, calendar: calendar),
            recentWorkouts: Array(summaries.prefix(5))
        )
    }

    static func makeRemoteSnapshot(
        identity: ProfileUserIdentity,
        stats: ProfileStatsSnapshot,
        achievements: ProfileAchievementCounts,
        standings: [ProfileStanding],
        workoutSummaries: [ProfileWorkoutSummary],
        firstAscentsHeld: [ProfileFirstAscentSummary],
        openFirstAscents: [ProfileFirstAscentSummary],
        climbs: [Climb],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ProfileSnapshot {
        let sortedWorkouts = workoutSummaries.sorted { $0.startedAt > $1.startedAt }
        return ProfileSnapshot(
            identity: identity,
            stats: stats,
            standings: standings,
            activityWorkouts: sortedWorkouts,
            collection: remoteCollectionSummary(
                workoutSummaries: sortedWorkouts,
                climbs: climbs
            ),
            achievements: achievements,
            firstAscentsHeld: firstAscentsHeld,
            openFirstAscents: openFirstAscents,
            records: remoteRecordSummary(stats: stats),
            trends: trendSummary(workoutSummaries: sortedWorkouts, now: now, calendar: calendar),
            recentWorkouts: Array(sortedWorkouts.prefix(5))
        )
    }

    static func comparison(
        viewer: ProfileSnapshot,
        otherUser: ProfileSnapshot
    ) -> ProfileComparisonSummary {
        let viewerClimbs = Set(viewer.activityWorkouts.filter(\.isCompletedClimb).compactMap(\.climbId))
        let otherClimbs = Set(otherUser.activityWorkouts.filter(\.isCompletedClimb).compactMap(\.climbId))

        if otherUser.totalClimbs == 0 && otherUser.activityWorkouts.isEmpty {
            return ProfileComparisonSummary(
                state: .otherEmpty,
                sharedClimbCount: 0,
                viewerWins: 0,
                otherUserWins: 0,
                ties: 0,
                viewerExclusiveCount: viewerClimbs.count,
                otherExclusiveCount: 0
            )
        }

        if viewerClimbs.isEmpty && otherClimbs.isEmpty {
            return ProfileComparisonSummary(
                state: .hidden,
                sharedClimbCount: 0,
                viewerWins: 0,
                otherUserWins: 0,
                ties: 0,
                viewerExclusiveCount: 0,
                otherExclusiveCount: 0
            )
        }

        if viewerClimbs.isEmpty && !otherClimbs.isEmpty {
            return ProfileComparisonSummary(
                state: .viewerEmpty,
                sharedClimbCount: 0,
                viewerWins: 0,
                otherUserWins: 0,
                ties: 0,
                viewerExclusiveCount: 0,
                otherExclusiveCount: otherClimbs.count
            )
        }

        if !viewerClimbs.isEmpty && otherClimbs.isEmpty {
            return ProfileComparisonSummary(
                state: .hidden,
                sharedClimbCount: 0,
                viewerWins: 0,
                otherUserWins: 0,
                ties: 0,
                viewerExclusiveCount: viewerClimbs.count,
                otherExclusiveCount: 0
            )
        }

        let shared = viewerClimbs.intersection(otherClimbs)
        let state: ProfileComparisonSummary.State = shared.isEmpty ? .noSharedClimbs : .shared
        let viewerBestDurations = bestCompletedDurationByClimb(viewer.activityWorkouts)
        let otherBestDurations = bestCompletedDurationByClimb(otherUser.activityWorkouts)
        var viewerWins = 0
        var otherUserWins = 0
        var ties = 0

        for climbId in shared {
            guard let viewerDuration = viewerBestDurations[climbId],
                  let otherDuration = otherBestDurations[climbId],
                  viewerDuration > 0,
                  otherDuration > 0 else {
                continue
            }

            if viewerDuration < otherDuration {
                viewerWins += 1
            } else if otherDuration < viewerDuration {
                otherUserWins += 1
            } else {
                ties += 1
            }
        }

        return ProfileComparisonSummary(
            state: state,
            sharedClimbCount: shared.count,
            viewerWins: viewerWins,
            otherUserWins: otherUserWins,
            ties: ties,
            viewerExclusiveCount: viewerClimbs.subtracting(otherClimbs).count,
            otherExclusiveCount: otherClimbs.subtracting(viewerClimbs).count
        )
    }

    static func headToHeadResults(
        viewer: ProfileSnapshot,
        otherUser: ProfileSnapshot,
        climbs: [Climb]
    ) -> [ProfileHeadToHeadClimbResult] {
        let climbsByID = Dictionary(uniqueKeysWithValues: climbs.map { ($0.id, $0) })
        let viewerBest = bestCompletedWorkoutByClimb(viewer.activityWorkouts)
        let otherBest = bestCompletedWorkoutByClimb(otherUser.activityWorkouts)
        let sharedClimbIDs = Set(viewerBest.keys).intersection(otherBest.keys)

        return sharedClimbIDs.compactMap { climbId in
            guard let viewerWorkout = viewerBest[climbId],
                  let otherWorkout = otherBest[climbId],
                  let viewerDuration = viewerWorkout.comparisonDurationSeconds,
                  let otherDuration = otherWorkout.comparisonDurationSeconds,
                  viewerDuration > 0,
                  otherDuration > 0 else {
                return nil
            }

            let climb = climbsByID[climbId]
            let winner: ProfileHeadToHeadClimbResult.Winner
            if viewerDuration < otherDuration {
                winner = .viewer
            } else if otherDuration < viewerDuration {
                winner = .otherUser
            } else {
                winner = .tie
            }

            return ProfileHeadToHeadClimbResult(
                id: climbId,
                climbName: climb?.name ?? viewerWorkout.name,
                stepCount: climb?.referenceStepCount ?? max(viewerWorkout.steps, otherWorkout.steps),
                viewerDurationSeconds: viewerDuration,
                otherUserDurationSeconds: otherDuration,
                mostRecentAt: max(viewerWorkout.startedAt, otherWorkout.startedAt),
                winner: winner
            )
        }
        .sorted { lhs, rhs in
            if lhs.mostRecentAt != rhs.mostRecentAt {
                return lhs.mostRecentAt > rhs.mostRecentAt
            }
            return lhs.climbName < rhs.climbName
        }
    }

    static func statsSnapshot(
        workouts: [Workout],
        completedAttempts: [ClimbAttempt],
        achievements: ProfileAchievementCounts
    ) -> ProfileStatsSnapshot {
        let firstAscentCount = completedAttempts.filter { ($0.globalCompletionOrder ?? 0) == 1 }.count
        let mostCompletedClimbId = Dictionary(grouping: completedAttempts, by: \.climbId)
            .max { lhs, rhs in lhs.value.count < rhs.value.count }?
            .key
        let lifetimeTotalSteps = workouts.reduce(0) { $0 + $1.steps }
        let lifetimeDurationSeconds = Int(workouts.reduce(0.0) { $0 + $1.duration }.rounded())
        let totalClimbs = workouts.count
        let averageStepsPerMinute = lifetimeDurationSeconds > 0
            ? Double(lifetimeTotalSteps) / (Double(lifetimeDurationSeconds) / 60.0)
            : 0

        return ProfileStatsSnapshot(
            totalClimbsCompleted: completedAttempts.count,
            totalFirstAscents: max(firstAscentCount, achievementsFromFirstAscents(achievements)),
            achievementCounts: achievements,
            mostCompletedClimbId: mostCompletedClimbId,
            currentStreakWeeks: Workout.calculateWeeklyStreak(from: workouts),
            bestStreakWeeks: Workout.calculateLongestWeeklyStreak(from: workouts),
            prMostSteps: workouts.map(\.steps).max() ?? 0,
            prLongestClimbSeconds: Int((workouts.map(\.duration).max() ?? 0).rounded()),
            prHighestSPM: workouts.compactMap(\.stepsPerMinute).max() ?? 0,
            lifetimeTotalSteps: lifetimeTotalSteps,
            lifetimeDurationSeconds: lifetimeDurationSeconds,
            totalClimbs: totalClimbs,
            averageStepsPerMinute: averageStepsPerMinute
        )
    }

    static func workoutSummaries(
        from workouts: [Workout],
        climbAttempts: [ClimbAttempt],
        climbs: [Climb]
    ) -> [ProfileWorkoutSummary] {
        let climbsByID = Dictionary(uniqueKeysWithValues: climbs.map { ($0.id, $0) })
        let attemptsByID = Dictionary(uniqueKeysWithValues: climbAttempts.map { ($0.id.uuidString, $0) })

        return workouts.map { workout in
            let climbParticipation = workout.participations.first { $0.contextType == .climbAttempt }
            let attempt = climbParticipation.flatMap { attemptsByID[$0.contextId] }
            let climbId = attempt?.climbId
            let climb = climbId.flatMap { climbsByID[$0] }
            return ProfileWorkoutSummary(
                id: workout.id.uuidString,
                name: workout.name,
                startedAt: workout.date,
                durationSeconds: workout.duration,
                steps: workout.steps,
                source: workout.source,
                climbId: climbId,
                climbTier: climb?.tier,
                climbCompletionStatus: attempt?.status,
                climbCompletionDurationSeconds: attempt?.bestCompletionDurationSeconds ?? attempt?.accumulatedDurationSeconds
            )
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    private static func collectionSummary(
        completedAttempts: [ClimbAttempt],
        climbs: [Climb],
        fitnessLevel: FitnessLevel
    ) -> ProfileCollectionSummary {
        let availableClimbs = climbs.filter(\.isAvailable)
        let comingSoonClimbs = climbs.filter(\.isComingSoon)
        let completedClimbs = claimedClimbs(
            from: completedAttempts,
            availableClimbs: availableClimbs
        )
        let launchedCards = collectionCards(
            for: collectionOrderedLaunchedClimbs(availableClimbs),
            claimedClimbs: completedClimbs
        )
        let previewCards = collectionPreviewCards(
            claimedClimbs: completedClimbs,
            availableClimbs: availableClimbs
        )

        _ = fitnessLevel
        return ProfileCollectionSummary(
            collectedCount: completedClimbs.count,
            catalogCount: availableClimbs.count,
            previewCards: previewCards,
            launchedCards: launchedCards,
            comingSoonClimbs: Array(comingSoonClimbs.prefix(6))
        )
    }

    private static func remoteCollectionSummary(
        workoutSummaries: [ProfileWorkoutSummary],
        climbs: [Climb]
    ) -> ProfileCollectionSummary {
        let availableClimbs = climbs.filter(\.isAvailable)
        let comingSoonClimbs = climbs.filter(\.isComingSoon)
        let completedClimbs = claimedClimbs(
            from: workoutSummaries,
            availableClimbs: availableClimbs
        )
        let launchedCards = collectionCards(
            for: collectionOrderedLaunchedClimbs(availableClimbs),
            claimedClimbs: completedClimbs
        )
        let previewCards = collectionPreviewCards(
            claimedClimbs: completedClimbs,
            availableClimbs: availableClimbs
        )

        return ProfileCollectionSummary(
            collectedCount: completedClimbs.count,
            catalogCount: availableClimbs.count,
            previewCards: previewCards,
            launchedCards: launchedCards,
            comingSoonClimbs: Array(comingSoonClimbs.prefix(6))
        )
    }

    private static func claimedClimbs(
        from completedAttempts: [ClimbAttempt],
        availableClimbs: [Climb]
    ) -> [ProfileCollectionClaimedClimb] {
        let climbsByID = Dictionary(uniqueKeysWithValues: availableClimbs.map { ($0.id, $0) })
        var claimedAtByClimbID: [String: Date] = [:]

        for attempt in completedAttempts {
            guard climbsByID[attempt.climbId] != nil else { continue }
            let claimedAt = attempt.completedAt ?? attempt.endedAt ?? attempt.startedAt
            if let existing = claimedAtByClimbID[attempt.climbId] {
                claimedAtByClimbID[attempt.climbId] = min(existing, claimedAt)
            } else {
                claimedAtByClimbID[attempt.climbId] = claimedAt
            }
        }

        return claimedAtByClimbID.compactMap { climbId, claimedAt in
            guard let climb = climbsByID[climbId] else { return nil }
            return ProfileCollectionClaimedClimb(climb: climb, claimedAt: claimedAt)
        }
        .sorted { lhs, rhs in
            if lhs.claimedAt != rhs.claimedAt {
                return lhs.claimedAt > rhs.claimedAt
            }
            return lhs.climb.name < rhs.climb.name
        }
    }

    private static func claimedClimbs(
        from workoutSummaries: [ProfileWorkoutSummary],
        availableClimbs: [Climb]
    ) -> [ProfileCollectionClaimedClimb] {
        let climbsByID = Dictionary(uniqueKeysWithValues: availableClimbs.map { ($0.id, $0) })
        var claimedAtByClimbID: [String: Date] = [:]

        for workout in workoutSummaries where workout.isCompletedClimb {
            guard let climbId = workout.climbId, climbsByID[climbId] != nil else { continue }
            if let existing = claimedAtByClimbID[climbId] {
                claimedAtByClimbID[climbId] = min(existing, workout.startedAt)
            } else {
                claimedAtByClimbID[climbId] = workout.startedAt
            }
        }

        return claimedAtByClimbID.compactMap { climbId, claimedAt in
            guard let climb = climbsByID[climbId] else { return nil }
            return ProfileCollectionClaimedClimb(climb: climb, claimedAt: claimedAt)
        }
        .sorted { lhs, rhs in
            if lhs.claimedAt != rhs.claimedAt {
                return lhs.claimedAt > rhs.claimedAt
            }
            return lhs.climb.name < rhs.climb.name
        }
    }

    private static func collectionPreviewCards(
        claimedClimbs: [ProfileCollectionClaimedClimb],
        availableClimbs: [Climb]
    ) -> [ProfileCollectionCardItem] {
        let claimedCards = claimedClimbs.prefix(3).map(ProfileCollectionCardItem.claimed)
        let claimedIDs = Set(claimedClimbs.map(\.climb.id))
        let recommendationLimit = max(3 - claimedCards.count, 0)
        let recommendedCards = recommendedUnclaimedClimbs(
            from: availableClimbs,
            excluding: claimedIDs
        )
        .prefix(recommendationLimit)
        .map(ProfileCollectionCardItem.unclaimed)

        return Array(claimedCards + recommendedCards)
    }

    private static func collectionCards(
        for climbs: [Climb],
        claimedClimbs: [ProfileCollectionClaimedClimb]
    ) -> [ProfileCollectionCardItem] {
        let claimedByID = Dictionary(uniqueKeysWithValues: claimedClimbs.map { ($0.climb.id, $0) })

        return climbs.map { climb in
            if let claimedClimb = claimedByID[climb.id] {
                return .claimed(claimedClimb)
            }

            return .unclaimed(climb)
        }
    }

    private static func collectionOrderedLaunchedClimbs(_ climbs: [Climb]) -> [Climb] {
        climbs.sorted(by: collectionLaunchSort)
    }

    private static func collectionLaunchSort(lhs: Climb, rhs: Climb) -> Bool {
        let lhsRank = collectionLaunchOrder[lhs.id] ?? Int.max
        let rhsRank = collectionLaunchOrder[rhs.id] ?? Int.max

        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }

        if lhs.tier != rhs.tier {
            return lhs.tier < rhs.tier
        }

        if lhs.totalSteps != rhs.totalSteps {
            return lhs.totalSteps < rhs.totalSteps
        }

        return lhs.name < rhs.name
    }

    private static let collectionLaunchOrder: [String: Int] = [
        "taipei-101": 0,
        "statue-of-liberty": 1,
        "space-needle": 2,
        "empire-state-building": 3,
        "eiffel-tower": 4,
        "burj-khalifa": 5,
        "table-mountain": 6,
        "machu-picchu": 7,
        "mount-everest": 8,
        "sydney-tower": 9
    ]

    private static func recommendedUnclaimedClimbs(
        from climbs: [Climb],
        excluding claimedIDs: Set<String>
    ) -> [Climb] {
        climbs
            .filter { !claimedIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.tier != rhs.tier {
                    return lhs.tier < rhs.tier
                }

                if lhs.totalSteps != rhs.totalSteps {
                    return lhs.totalSteps < rhs.totalSteps
                }

                return lhs.name < rhs.name
            }
    }

    private static func firstAscentsHeld(
        completedAttempts: [ClimbAttempt],
        climbs: [Climb]
    ) -> [ProfileFirstAscentSummary] {
        let climbsByID = Dictionary(uniqueKeysWithValues: climbs.map { ($0.id, $0) })

        return completedAttempts.compactMap { attempt in
            guard (attempt.globalCompletionOrder ?? 0) == 1,
                  let climb = climbsByID[attempt.climbId] else {
                return nil
            }

            return ProfileFirstAscentSummary(
                climbId: climb.id,
                climbName: climb.name,
                locationText: climb.displayLocation,
                tier: climb.tier,
                targetSteps: climb.referenceStepCount,
                kind: .held(claimedAt: attempt.completedAt ?? attempt.endedAt ?? attempt.startedAt)
            )
        }
    }

    private static func recordSummary(
        workouts: [Workout],
        bestEffortCacheEntries: [BestEffortCacheEntry]
    ) -> ProfileRecordSummary {
        let mostSteps = workouts.max { $0.steps < $1.steps }
        let longest = workouts.max { $0.duration < $1.duration }
        let fastest = workouts.max { ($0.stepsPerMinute ?? 0) < ($1.stepsPerMinute ?? 0) }
        let snapshot = BestEffortCacheSnapshot(entries: bestEffortCacheEntries, workouts: workouts)

        return ProfileRecordSummary(
            personalRecords: [
                .init(
                    kind: .mostSteps,
                    label: "MOST STEPS",
                    valueText: mostSteps.map { $0.steps.formatted(.number.grouping(.automatic)) },
                    date: mostSteps?.date
                ),
                .init(
                    kind: .longestClimb,
                    label: "LONGEST CLIMB",
                    valueText: longest.map { ProfileDateFormatters.durationClock($0.duration) },
                    date: longest?.date
                ),
                .init(
                    kind: .fastestPace,
                    label: "FASTEST PACE",
                    valueText: fastest.flatMap(\.stepsPerMinute).map { "\(Int($0.rounded())) SPM" },
                    date: fastest?.date
                )
            ],
            featuredBestEffort: snapshot.board(scope: .allTime, context: .all).primaryEffort
        )
    }

    private static func remoteRecordSummary(stats: ProfileStatsSnapshot) -> ProfileRecordSummary {
        ProfileRecordSummary(
            personalRecords: [
                .init(
                    kind: .mostSteps,
                    label: "MOST STEPS",
                    valueText: stats.prMostSteps > 0 ? stats.prMostSteps.formatted(.number.grouping(.automatic)) : nil,
                    date: nil
                ),
                .init(
                    kind: .longestClimb,
                    label: "LONGEST CLIMB",
                    valueText: stats.prLongestClimbSeconds > 0 ? ProfileDateFormatters.durationClock(TimeInterval(stats.prLongestClimbSeconds)) : nil,
                    date: nil
                ),
                .init(
                    kind: .fastestPace,
                    label: "FASTEST PACE",
                    valueText: stats.prHighestSPM > 0 ? "\(Int(stats.prHighestSPM.rounded())) SPM" : nil,
                    date: nil
                )
            ],
            featuredBestEffort: nil
        )
    }

    private static func trendSummary(
        workouts: [Workout],
        now: Date,
        calendar: Calendar
    ) -> ProfileTrendSummary {
        trendSummary(
            workoutDatesAndSteps: workouts.map { ($0.date, $0.steps) },
            now: now,
            calendar: calendar
        )
    }

    private static func trendSummary(
        workoutSummaries: [ProfileWorkoutSummary],
        now: Date,
        calendar: Calendar
    ) -> ProfileTrendSummary {
        trendSummary(
            workoutDatesAndSteps: workoutSummaries.map { ($0.startedAt, $0.steps) },
            now: now,
            calendar: calendar
        )
    }

    private static func trendSummary(
        workoutDatesAndSteps: [(Date, Int)],
        now: Date,
        calendar: Calendar
    ) -> ProfileTrendSummary {
        let currentInterval = calendar.dateInterval(of: .month, for: now)
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: now)
        let previousInterval = previousMonth.flatMap { calendar.dateInterval(of: .month, for: $0) }

        let currentSteps = currentInterval.map { interval in
            workoutDatesAndSteps
                .filter { interval.contains($0.0) && $0.0 <= now }
                .reduce(0) { $0 + $1.1 }
        } ?? 0

        let previousSteps = previousInterval.map { interval in
            workoutDatesAndSteps
                .filter { interval.contains($0.0) }
                .reduce(0) { $0 + $1.1 }
        } ?? 0

        let activeDays = Set(workoutDatesAndSteps.map { calendar.startOfDay(for: $0.0) })

        return ProfileTrendSummary(
            currentSteps: currentSteps,
            previousSteps: previousSteps,
            daysWithData: activeDays.count
        )
    }

    private static func recommendedFirstClimb(
        from climbs: [Climb],
        fitnessLevel: FitnessLevel
    ) -> Climb? {
        let preferredID: String
        switch fitnessLevel {
        case .beginner:
            preferredID = "statue-of-liberty"
        case .intermediate:
            preferredID = "space-needle"
        case .advanced:
            preferredID = "empire-state-building"
        }

        return climbs.first { $0.id == preferredID }
            ?? climbs.sorted { $0.referenceStepCount < $1.referenceStepCount }.first
    }

    private static func achievementsFromFirstAscents(_ achievements: ProfileAchievementCounts) -> Int {
        // First Ascents are tracked separately from Top N rank achievements.
        // This hook keeps future server-provided FA achievement derivation isolated.
        _ = achievements
        return 0
    }

    private static func bestCompletedDurationByClimb(_ workouts: [ProfileWorkoutSummary]) -> [String: TimeInterval] {
        workouts.reduce(into: [:]) { result, workout in
            guard let climbId = workout.climbId,
                  let duration = workout.comparisonDurationSeconds,
                  duration > 0 else {
                return
            }
            if let existing = result[climbId] {
                result[climbId] = min(existing, duration)
            } else {
                result[climbId] = duration
            }
        }
    }

    private static func bestCompletedWorkoutByClimb(_ workouts: [ProfileWorkoutSummary]) -> [String: ProfileWorkoutSummary] {
        var best: [String: ProfileWorkoutSummary] = [:]

        for workout in workouts {
            guard let climbId = workout.climbId,
                  let duration = workout.comparisonDurationSeconds,
                  duration > 0 else {
                continue
            }

            if let existing = best[climbId],
               let existingDuration = existing.comparisonDurationSeconds,
               existingDuration <= duration {
                continue
            }

            best[climbId] = workout
        }

        return best
    }
}
