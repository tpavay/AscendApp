//
//  ProfileView.swift
//  AscendApp
//
//  Created by Codex on 5/22/26.
//

import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationViewModel.self) private var authVM
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @Query(sort: \ClimbAttempt.startedAt, order: .reverse) private var climbAttempts: [ClimbAttempt]
    @Query(sort: \BestEffortCacheEntry.sortKey) private var bestEffortCacheEntries: [BestEffortCacheEntry]

    @State private var firstAscents: [ProfileFirstAscentCardModel] = []
    @State private var rankCards: [ProfileRankCardModel] = []
    @State private var climbRanksByID: [String: Int] = [:]
    @State private var isLoadingCurrentRanks = true

    private var displayName: String {
        let trimmed = authVM.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Climber" : trimmed
    }

    private var completedClimbCount: Int {
        Set(completedAttempts.map(\.climbId)).count
    }

    private var completedClimbCards: [ProfileCompletedClimbCardModel] {
        loadCompletedClimbCards()
    }

    private var completedAttempts: [ClimbAttempt] {
        climbAttempts.filter { $0.status == .completed }
    }

    private var recentWorkouts: [Workout] {
        Array(workouts.prefix(3))
    }

    private var cacheSnapshot: BestEffortCacheSnapshot {
        BestEffortCacheSnapshot(entries: bestEffortCacheEntries, workouts: workouts)
    }

    private var featuredBestEffort: RankedBestEffort? {
        cacheSnapshot.board(scope: .allTime, context: .all).primaryEffort
    }

    private var trendSnapshot: ProfileTrendSnapshot {
        ProfileTrendSnapshot(workouts: workouts)
    }

    private var memberSinceText: String? {
        guard let date = authVM.user?.metadata.creationDate else { return nil }
        return "MEMBER SINCE \(Self.memberSinceFormatter.string(from: date).uppercased())"
    }

    private var highlightsTaskKey: String {
        let latestWorkout = workouts.first?.lastModifiedAt.timeIntervalSince1970 ?? 0
        let latestAttempt = climbAttempts.first.map { ClimbService.attemptSortDate(for: $0).timeIntervalSince1970 } ?? 0
        return [
            authVM.user?.uid ?? "signed-out",
            "\(workouts.count)",
            "\(completedAttempts.count)",
            "\(latestWorkout)",
            "\(latestAttempt)"
        ].joined(separator: "-")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                profileHeader

                if !firstAscents.isEmpty {
                    firstAscentsSection
                }

                if !completedClimbCards.isEmpty {
                    completedClimbsSection
                }

                currentRanksSection

                ProfileActivityCalendarView(workouts: workouts)

                recentWorkoutsSection

                profileProgressLinks
            }
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 118)
        }
        .scrollIndicators(.hidden)
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: highlightsTaskKey) {
            await loadProfileHighlights()
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                NavigationLink {
                    EditProfileView()
                } label: {
                    ProfileAvatarView(photoURL: authVM.displayPhotoURL, size: 128)
                        .overlay(alignment: .bottomTrailing) {
                            Circle()
                                .fill(Color.accent.opacity(0.94))
                                .frame(width: 38, height: 38)
                                .overlay {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.black)
                                }
                                .shadow(color: Color.accent.opacity(0.5), radius: 12, x: 0, y: 0)
                        }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(displayName)
                            .font(.montserratBold(size: 26))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)

                        Spacer(minLength: 0)

                        NavigationLink {
                            AccountView()
                        } label: {
                            AppIcon(token: .tabSettings, pointSize: 30)
                                .foregroundStyle(Color.accent)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Settings")
                    }
                }
            }

            if let memberSinceText {
                Text(memberSinceText)
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(.white.opacity(0.52))
                    .tracking(1.4)
                    .padding(.leading, 4)
            }
        }
    }

    private var firstAscentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProfileSectionHeader(
                iconName: "crown.fill",
                title: "FIRST ASCENTS HELD",
                trailingText: "\(firstAscents.count) TOTAL",
                accent: ProfileColors.gold
            )

            VStack(spacing: 6) {
                ForEach(firstAscents.prefix(3)) { ascent in
                    ProfileFirstAscentRow(ascent: ascent)
                }
            }
        }
    }

    private var completedClimbsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileSectionHeader(
                iconName: "mountain.2.fill",
                title: "CLIMBS COMPLETED",
                trailingText: "\(completedClimbCount) TOTAL",
                accent: Color.accent
            )

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(completedClimbCards) { card in
                        ProfileCompletedClimbCard(card: card)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private var currentRanksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileSectionHeader(
                iconName: "medal.fill",
                title: "CURRENT RANKS",
                trailingText: nil,
                accent: Color.accent
            )

            if isLoadingCurrentRanks {
                ProfileCurrentRanksLoadingView()
            } else if rankCards.isEmpty {
                ProfileEmptyCard(
                    title: "No global ranks yet.",
                    message: "Log workouts. Claim a spot."
                )
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(rankCards) { card in
                            ProfileRankCard(card: card)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("RECENT WORKOUTS")
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(.white)
                    .tracking(1.2)

                Spacer()

                NavigationLink {
                    WorkoutListView(
                        embedsInNavigationStack: false,
                        showsBackButton: true
                    )
                } label: {
                    Text("VIEW ALL")
                        .font(.montserratSemiBold(size: 12))
                        .foregroundStyle(Color.accent)
                        .tracking(1.2)
                }
                .buttonStyle(.plain)
            }

            if recentWorkouts.isEmpty {
                ProfileEmptyCard(
                    title: "No workouts yet.",
                    message: "Log a climb. Start the record."
                )
            } else {
                VStack(spacing: 6) {
                    ForEach(recentWorkouts) { workout in
                        NavigationLink {
                            WorkoutDetailView(workout: workout)
                        } label: {
                            ProfileRecentWorkoutRow(workout: workout)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var profileProgressLinks: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            NavigationLink {
                BestEffortsListView(workouts: workouts)
            } label: {
                ProfileBestEffortsCard(effort: featuredBestEffort)
            }
            .buttonStyle(.plain)

            NavigationLink {
                WorkoutTrendsView(workouts: workouts, initialMonth: Date())
            } label: {
                ProfileTrendsCard(snapshot: trendSnapshot)
            }
            .buttonStyle(.plain)
        }
    }

    @MainActor
    private func loadProfileHighlights() async {
        isLoadingCurrentRanks = true
        defer {
            isLoadingCurrentRanks = false
        }

        guard let userId = authVM.user?.uid else {
            firstAscents = []
            rankCards = []
            climbRanksByID = [:]
            return
        }

        let workoutSummaries = workouts.map(ProfileWorkoutSummary.init(workout:))
        let completedClimbSnapshots = loadCompletedClimbSnapshots()
        let displayName = displayName
        let photoURL = authVM.displayPhotoURL

        if !workouts.isEmpty {
            let leaderboardService = LeaderboardService.shared
            leaderboardService.configure(modelContext: modelContext)
            _ = try? leaderboardService.rebuildCurrentStatsIfNeeded(
                for: userId,
                workouts: workouts
            )
            await LeaderboardSyncCoordinator.shared.enqueueSync(
                userId: userId,
                displayName: displayName,
                photoURL: photoURL
            )
        }

        var loadedFirstAscents: [ProfileFirstAscentCardModel] = []
        var loadedRanks: [ProfileRankCardModel] = []
        var loadedClimbRanks: [String: Int] = [:]

        for snapshot in completedClimbSnapshots {
            let context = LiveReplayLeaderboardContext.liveClimb(
                climbId: snapshot.id,
                targetSteps: snapshot.targetSteps
            )

            if let summary = try? await LiveReplayLeaderboardService.shared.fetchSummary(context: context),
               summary.firstAscent?.userId == userId,
               let firstAscent = summary.firstAscent {
                loadedFirstAscents.append(
                    ProfileFirstAscentCardModel(
                        climbName: snapshot.name,
                        heightText: snapshot.heightText,
                        date: firstAscent.completedAt
                    )
                )
            }

            if let bestDuration = snapshot.bestCompletionDurationSeconds,
               let rank = try? await LiveReplayLeaderboardService.shared.fetchCompletionRank(
                context: context,
                completionDurationSeconds: TimeInterval(bestDuration)
               ) {
                loadedClimbRanks[snapshot.id] = rank.rank
            }
        }

        if !workoutSummaries.isEmpty {
            for target in ProfileRankTarget.defaultTargets {
                if let rank = try? await LeaderboardRepository.shared.getUserRank(
                    userId: userId,
                    metric: target.metric,
                    timeFrame: target.timeFrame
                ) {
                    loadedRanks.append(
                        ProfileRankCardModel(
                            title: "\(target.timeFrame.displayName) \(target.metric.displayName)",
                            rank: rank.rank,
                            valueText: target.valueText(from: workoutSummaries),
                            subtitle: target.metric.unit.uppercased()
                        )
                    )
                }
            }
        }

        firstAscents = loadedFirstAscents.sorted { $0.date > $1.date }
        climbRanksByID = loadedClimbRanks
        rankCards = loadedRanks
            .sorted {
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                return $0.title < $1.title
            }
            .prefix(8)
            .map { $0 }
    }

    @MainActor
    private func loadCompletedClimbSnapshots() -> [ProfileCompletedClimbSnapshot] {
        let bestDurationsByClimb = completedAttempts.reduce(into: [String: Int]()) { result, attempt in
            let duration = attempt.bestCompletionDurationSeconds ?? attempt.accumulatedDurationSeconds
            guard duration > 0 else { return }
            result[attempt.climbId] = min(result[attempt.climbId] ?? duration, duration)
        }

        guard let climbs = try? ClimbService.shared.loadClimbs() else { return [] }

        return climbs
            .filter { bestDurationsByClimb[$0.id] != nil }
            .map { climb in
                ProfileCompletedClimbSnapshot(
                    id: climb.id,
                    name: climb.name,
                    heightText: "\(Int(climb.referenceHeightFeet.rounded()).formatted(.number.grouping(.automatic))) ft",
                    targetSteps: climb.referenceStepCount,
                    bestCompletionDurationSeconds: bestDurationsByClimb[climb.id]
                )
            }
    }

    @MainActor
    private func loadCompletedClimbCards() -> [ProfileCompletedClimbCardModel] {
        let attemptsByClimb = Dictionary(grouping: completedAttempts, by: \.climbId)
        guard let climbs = try? ClimbService.shared.loadClimbs() else { return [] }

        return climbs.compactMap { climb in
            guard let attempts = attemptsByClimb[climb.id], !attempts.isEmpty else { return nil }

            let latestCompletedAt = attempts
                .map { ClimbService.attemptSortDate(for: $0) }
                .max() ?? Date()
            let bestDuration = attempts
                .compactMap { attempt -> Int? in
                    let duration = attempt.bestCompletionDurationSeconds ?? attempt.accumulatedDurationSeconds
                    return duration > 0 ? duration : nil
                }
                .min()

            return ProfileCompletedClimbCardModel(
                climb: climb,
                completionsCount: attempts.count,
                rank: climbRanksByID[climb.id],
                latestCompletedAt: latestCompletedAt,
                bestCompletionDurationSeconds: bestDuration
            )
        }
        .sorted { $0.latestCompletedAt > $1.latestCompletedAt }
    }

    private static let memberSinceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}

private enum ProfileColors {
    static let cardFill = Color.white.opacity(0.055)
    static let cardStroke = Color.white.opacity(0.12)
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.42)
    static let gold = Color(red: 1.0, green: 0.72, blue: 0.12)
    static let silver = Color(red: 0.78, green: 0.82, blue: 0.88)
    static let bronze = Color(red: 0.84, green: 0.43, blue: 0.16)
    static let fireRed = Color(red: 1.0, green: 0.18, blue: 0.08)
    static let fireOrange = Color(red: 1.0, green: 0.43, blue: 0.06)
    static let fireYellow = Color(red: 1.0, green: 0.82, blue: 0.14)
}

private struct ProfileSectionHeader: View {
    let iconName: String
    let title: String
    let trailingText: String?
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(accent)

            Text(title)
                .font(.montserratBold(size: 17))
                .foregroundStyle(.white)
                .tracking(1.5)

            Spacer()

            if let trailingText {
                Text(trailingText)
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(Color.accent)
                    .tracking(1.6)
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct ProfileAvatarView: View {
    let photoURL: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: photoURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                ZStack {
                    LinearGradient(
                        colors: [Color.accent.opacity(0.28), Color.white.opacity(0.08), Color.black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.accent, lineWidth: 2)
        }
        .shadow(color: Color.accent.opacity(0.28), radius: 18, x: 0, y: 0)
    }
}

private struct ProfileFirstAscentRow: View {
    let ascent: ProfileFirstAscentCardModel

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                LinearGradient(
                    colors: [
                        ProfileColors.gold.opacity(0.24),
                        Color.white.opacity(0.06),
                        Color.black.opacity(0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                AppIcon(token: .mountains, pointSize: 32)
                    .foregroundStyle(ProfileColors.gold.opacity(0.82))
            }
            .frame(width: 82, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(ascent.climbName.uppercased())
                    .font(.montserratBold(size: 15))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                Text(ascent.heightText)
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(ProfileColors.secondaryText)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(ProfileColors.gold)

                Text(ProfileFormatters.shortDate(ascent.date).uppercased())
                    .font(.montserratMedium(size: 10))
                    .foregroundStyle(ProfileColors.secondaryText)
                    .tracking(0.7)
            }
        }
        .padding(8)
        .background(ProfileColors.cardFill)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ProfileColors.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProfileCompletedClimbCard: View {
    let card: ProfileCompletedClimbCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ClimbArtworkView(climb: card.climb, variant: .thumb)
                .frame(width: 154, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if let rank = card.rank {
                        Text("#\(rank)")
                            .font(.montserratBold(size: 12))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.72))
                            .clipShape(Capsule())
                            .padding(7)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Text("\(card.completionsCount)x")
                        .font(.montserratBold(size: 10))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.accent)
                        .clipShape(Capsule())
                        .padding(7)
                }

            Text(card.climb.name.uppercased())
                .font(.montserratBold(size: 12))
                .foregroundStyle(.white)
                .tracking(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if let bestDuration = card.bestCompletionDurationSeconds {
                Text("BEST \(ProfileFormatters.durationClock(TimeInterval(bestDuration)))")
                    .font(.montserratMedium(size: 10))
                    .foregroundStyle(Color.accent)
                    .tracking(0.8)
                    .lineLimit(1)
            } else {
                Text(ProfileFormatters.shortDate(card.latestCompletedAt).uppercased())
                    .font(.montserratMedium(size: 10))
                    .foregroundStyle(ProfileColors.secondaryText)
                    .tracking(0.8)
                    .lineLimit(1)
            }
        }
        .frame(width: 154, alignment: .leading)
        .padding(8)
        .background(ProfileColors.cardFill)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ProfileColors.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProfileCurrentRanksLoadingView: View {
    var body: some View {
        HStack {
            Spacer()

            VStack(spacing: 12) {
                ProgressView()
                    .tint(Color.accent)

                Text("Loading ranks")
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(ProfileColors.secondaryText)
                    .tracking(0.9)
            }

            Spacer()
        }
        .frame(height: 142)
        .background(ProfileColors.cardFill)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ProfileColors.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProfileRankCard: View {
    let card: ProfileRankCardModel

    private var accent: Color {
        switch card.rank {
        case 1:
            return ProfileColors.gold
        case 2:
            return ProfileColors.silver
        case 3:
            return ProfileColors.bronze
        default:
            return Color.accent
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(card.title.uppercased())
                .font(.montserratMedium(size: 12))
                .foregroundStyle(.white.opacity(0.72))
                .tracking(1.2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 34)

            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "medal.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(accent)
                    .shadow(color: accent.opacity(0.3), radius: 10, x: 0, y: 0)

                Text("#\(card.rank)")
                    .font(.montserratBold(size: 30))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.78)
            }

            Text(card.valueText)
                .font(.montserratSemiBold(size: 13))
                .foregroundStyle(Color.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(card.subtitle)
                .font(.montserratMedium(size: 11))
                .foregroundStyle(ProfileColors.secondaryText)
                .tracking(1.1)
                .lineLimit(1)
        }
        .frame(width: 166, height: 142)
        .padding(12)
        .background(ProfileColors.cardFill)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ProfileColors.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProfileActivityCalendarView: View {
    let workouts: [Workout]

    @State private var selectedDate = Date()
    @State private var selectedCalendarDay: ProfileCalendarDay?

    private var calendar: Calendar {
        Calendar.current
    }

    private var calendarDays: [ProfileCalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate),
              let lastDayOfMonth = calendar.date(byAdding: DateComponents(day: -1), to: monthInterval.end) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let daysFromMonday = (firstWeekday + 5) % 7
        let gridStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: monthInterval.start) ?? monthInterval.start

        let lastWeekday = calendar.component(.weekday, from: lastDayOfMonth)
        let daysToSunday = (8 - lastWeekday) % 7
        let gridEnd = calendar.date(byAdding: .day, value: daysToSunday, to: lastDayOfMonth) ?? lastDayOfMonth

        var days: [ProfileCalendarDay] = []
        var currentDate = gridStart

        while currentDate <= gridEnd {
            let dayStart = calendar.startOfDay(for: currentDate)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let dayWorkouts = workouts.filter { workout in
                workout.date >= dayStart && workout.date < dayEnd
            }

            days.append(
                ProfileCalendarDay(
                    date: dayStart,
                    workouts: dayWorkouts,
                    isCurrentMonth: calendar.isDate(dayStart, equalTo: selectedDate, toGranularity: .month)
                )
            )

            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }

        return days
    }

    private var canGoToNextMonth: Bool {
        let nextMonthDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        return calendar.compare(nextMonthDate, to: Date(), toGranularity: .month) != .orderedDescending
    }

    private var maxDailyStepsInMonth: Int {
        calendarDays
            .filter(\.isCurrentMonth)
            .map(\.totalSteps)
            .max() ?? 0
    }

    private var currentWeekStreak: Int {
        Workout.calculateWeeklyStreak(from: workouts)
    }

    private var bestWeekStreak: Int {
        Workout.calculateLongestWeeklyStreak(from: workouts)
    }

    private var calendarWeekCount: Int {
        max(calendarDays.count / 7, 5)
    }

    private var calendarDayHeight: CGFloat {
        38
    }

    private var calendarGridSpacing: CGFloat {
        8
    }

    private var calendarCardHeight: CGFloat {
        let weekdayHeight: CGFloat = 18
        let legendHeight: CGFloat = 18
        let cardVerticalPadding: CGFloat = 24
        let legendSpacing: CGFloat = 12
        let gridHeight = weekdayHeight
            + (CGFloat(calendarWeekCount) * calendarDayHeight)
            + (CGFloat(calendarWeekCount) * calendarGridSpacing)
        return cardVerticalPadding + gridHeight + legendSpacing + legendHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ACTIVITY")
                    .font(.montserratBold(size: 17))
                    .foregroundStyle(.white)
                    .tracking(1.5)

                Spacer()

                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.accent)
                        .frame(width: 36, height: 32)
                }
                .buttonStyle(.plain)

                Text(monthYearFormatter.string(from: selectedDate).uppercased())
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(Color.accent)
                    .tracking(1.5)
                    .frame(minWidth: 112)

                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(canGoToNextMonth ? Color.accent : ProfileColors.tertiaryText)
                        .frame(width: 36, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!canGoToNextMonth)
            }

            HStack(alignment: .top, spacing: 8) {
                calendarCard

                ProfileWeekStreakRail(
                    currentStreak: currentWeekStreak,
                    bestStreak: bestWeekStreak
                )
                .frame(width: 82, height: calendarCardHeight)
            }
        }
    }

    private var calendarCard: some View {
        VStack(spacing: 12) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                spacing: calendarGridSpacing
            ) {
                ForEach(["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"], id: \.self) { day in
                    Text(day)
                        .font(.montserratMedium(size: 10))
                        .foregroundStyle(ProfileColors.secondaryText)
                        .frame(height: 18)
                }

                ForEach(calendarDays) { day in
                    calendarDay(day)
                }
            }

            calendarLegend
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: calendarCardHeight)
        .background(ProfileColors.cardFill)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ProfileColors.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func calendarDay(_ day: ProfileCalendarDay) -> some View {
        Button {
            guard day.isCurrentMonth else { return }
            selectedCalendarDay = day
        } label: {
            Text("\(calendar.component(.day, from: day.date))")
                .font(.montserratMedium(size: 18))
                .foregroundStyle(day.isCurrentMonth ? Color.white : ProfileColors.tertiaryText)
                .frame(maxWidth: .infinity)
                .frame(height: calendarDayHeight)
                .background(dayFill(for: day))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected(day) ? Color.accent : Color.clear, lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!day.isCurrentMonth)
    }

    private var calendarLegend: some View {
        HStack(spacing: 6) {
            Text("FEWER STEPS")
                .font(.montserratMedium(size: 8))
                .foregroundStyle(ProfileColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 5) {
                ForEach([0.15, 0.28, 0.41, 0.54, 0.67, 0.8, 1.0], id: \.self) { score in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(stepColor(score: score))
                        .frame(width: 10, height: 10)
                }
            }

            Text("MORE STEPS")
                .font(.montserratMedium(size: 8))
                .foregroundStyle(ProfileColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 18)
    }

    private func previousMonth() {
        selectedDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
        selectedCalendarDay = nil
    }

    private func nextMonth() {
        guard canGoToNextMonth else { return }
        selectedDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        selectedCalendarDay = nil
    }

    private func dayFill(for day: ProfileCalendarDay) -> LinearGradient {
        if !day.isCurrentMonth {
            return LinearGradient(
                colors: [Color.white.opacity(0.08), Color.white.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        guard day.totalSteps > 0, maxDailyStepsInMonth > 0 else {
            return LinearGradient(
                colors: [Color.white.opacity(0.105), Color.white.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        let score = min(Double(day.totalSteps) / Double(maxDailyStepsInMonth), 1)
        return LinearGradient(
            colors: [
                stepColor(score: max(score * 0.7, 0.18)).opacity(0.96),
                stepColor(score: score)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func stepColor(score: Double) -> Color {
        let clamped = min(max(score, 0), 1)
        let red = 0.17 + (0.53 * clamped)
        let green = 0.30 + (0.63 * clamped)
        let blue = 0.02 + (0.05 * clamped)
        return Color(red: red, green: green, blue: blue)
    }

    private func isSelected(_ day: ProfileCalendarDay) -> Bool {
        if let selectedCalendarDay {
            return calendar.isDate(day.date, inSameDayAs: selectedCalendarDay.date)
        }

        return day.isCurrentMonth && calendar.isDateInToday(day.date)
    }

    private var monthYearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }
}

private struct ProfileWeekStreakRail: View {
    let currentStreak: Int
    let bestStreak: Int

    var body: some View {
        VStack(spacing: 0) {
            streakBlock(
                title: "CURRENT\nWEEK STREAK",
                value: currentStreak,
                unitColor: ProfileColors.fireOrange,
                iconName: "flame.fill",
                iconStyle: AnyShapeStyle(fireGradient),
                glowColor: ProfileColors.fireOrange.opacity(0.34)
            )

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            ProfileColors.fireRed.opacity(0.38),
                            ProfileColors.gold.opacity(0.34),
                            Color.white.opacity(0.12)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 10)

            streakBlock(
                title: "BEST\nWEEK STREAK",
                value: bestStreak,
                unitColor: ProfileColors.gold,
                iconName: "trophy.fill",
                iconStyle: AnyShapeStyle(goldGradient),
                glowColor: ProfileColors.gold.opacity(0.28)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.055),
                    ProfileColors.fireOrange.opacity(0.035),
                    Color.white.opacity(0.025)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ProfileColors.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func streakBlock(
        title: String,
        value: Int,
        unitColor: Color,
        iconName: String,
        iconStyle: AnyShapeStyle,
        glowColor: Color
    ) -> some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.montserratMedium(size: 9))
                .foregroundStyle(ProfileColors.secondaryText)
                .tracking(0.8)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Image(systemName: iconName)
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(iconStyle)
                .shadow(color: glowColor, radius: 14, x: 0, y: 0)
                .padding(.top, 2)

            Text("\(value)")
                .font(.montserratBold(size: 30))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .shadow(color: glowColor, radius: 10, x: 0, y: 0)

            Text(value == 1 ? "WEEK" : "WEEKS")
                .font(.montserratSemiBold(size: 10))
                .foregroundStyle(unitColor)
                .tracking(0.8)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 6)
    }

    private var fireGradient: LinearGradient {
        LinearGradient(
            colors: [
                ProfileColors.fireYellow,
                ProfileColors.fireOrange,
                ProfileColors.fireRed
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var goldGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.95),
                ProfileColors.gold,
                Color(red: 0.86, green: 0.48, blue: 0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct ProfileRecentWorkoutRow: View {
    let workout: Workout

    private var highlightedPhoto: Photo? {
        workout.highlightedPhoto
    }

    var body: some View {
        HStack(spacing: 12) {
            if let highlightedPhoto {
                LoadablePhotoView(
                    photo: highlightedPhoto,
                    size: CGSize(width: 54, height: 54),
                    cornerRadius: 8
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.name.uppercased())
                    .font(.montserratBold(size: 14))
                    .foregroundStyle(.white)
                    .tracking(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(ProfileFormatters.shortDate(workout.date).uppercased())
                    .font(.montserratMedium(size: 11))
                    .foregroundStyle(ProfileColors.secondaryText)
                    .tracking(0.8)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(workout.steps.formatted(.number.grouping(.automatic)))
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(.white.opacity(0.82))

                Text("STEPS")
                    .font(.montserratMedium(size: 9))
                    .foregroundStyle(ProfileColors.secondaryText)
                    .tracking(1.1)
            }

            VStack(alignment: .trailing, spacing: 3) {
                Text(ProfileFormatters.durationClock(workout.duration))
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(.white.opacity(0.82))

                Text("DURATION")
                    .font(.montserratMedium(size: 9))
                    .foregroundStyle(ProfileColors.secondaryText)
                    .tracking(1.1)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(8)
        .background(ProfileColors.cardFill)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ProfileColors.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProfileBestEffortsCard: View {
    let effort: RankedBestEffort?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image("best-effort-laurel-wreath")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 44)
                    .opacity(0.88)

                Spacer()
            }

            Text("BEST EFFORTS")
                .font(.montserratBold(size: 15))
                .foregroundStyle(.white)
                .tracking(1.2)

            if let effort {
                Text(effort.metric.title)
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(ProfileColors.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(effort.compactValueText)
                        .font(.montserratBold(size: 18))
                        .foregroundStyle(Color.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(effort.dateText.uppercased())
                        .font(.montserratMedium(size: 9))
                        .foregroundStyle(ProfileColors.secondaryText)
                        .lineLimit(1)
                }
            } else {
                Text("No records yet.")
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(ProfileColors.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Text("More records")
                .font(.montserratMedium(size: 11))
                .foregroundStyle(ProfileColors.gold.opacity(0.76))
        }
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .leading)
        .padding(14)
        .background(ProfileColors.cardFill)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ProfileColors.gold.opacity(0.32), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProfileTrendsCard: View {
    let snapshot: ProfileTrendSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppIcon(token: .bestEffortChartLine, pointSize: 44)
                .foregroundStyle(Color.accent)

            Text("TRENDS")
                .font(.montserratBold(size: 15))
                .foregroundStyle(.white)
                .tracking(1.2)

            Text("Track volume, pace, and consistency.")
                .font(.montserratMedium(size: 12))
                .foregroundStyle(ProfileColors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Text(snapshot.changeText)
                .font(.montserratBold(size: 15))
                .foregroundStyle(snapshot.changeColor)

            Text("STEPS THIS MONTH")
                .font(.montserratMedium(size: 10))
                .foregroundStyle(ProfileColors.secondaryText)
                .tracking(1.1)
        }
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .leading)
        .padding(14)
        .background(ProfileColors.cardFill)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ProfileColors.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProfileEmptyCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.montserratBold(size: 16))
                .foregroundStyle(.white)

            Text(message)
                .font(.montserratMedium(size: 13))
                .foregroundStyle(ProfileColors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(ProfileColors.cardFill)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ProfileColors.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProfileCalendarDay: Identifiable {
    let date: Date
    let workouts: [Workout]
    let isCurrentMonth: Bool

    var id: Date { date }

    var totalSteps: Int {
        workouts.reduce(0) { $0 + $1.steps }
    }
}

private struct ProfileFirstAscentCardModel: Identifiable, Sendable {
    let id = UUID()
    let climbName: String
    let heightText: String
    let date: Date
}

private struct ProfileCompletedClimbCardModel: Identifiable {
    let climb: Climb
    let completionsCount: Int
    let rank: Int?
    let latestCompletedAt: Date
    let bestCompletionDurationSeconds: Int?

    var id: String { climb.id }
}

private struct ProfileRankCardModel: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let rank: Int
    let valueText: String
    let subtitle: String
}

private struct ProfileCompletedClimbSnapshot: Sendable {
    let id: String
    let name: String
    let heightText: String
    let targetSteps: Int
    let bestCompletionDurationSeconds: Int?
}

private struct ProfileWorkoutSummary: Sendable {
    let date: Date
    let duration: TimeInterval
    let steps: Int

    init(workout: Workout) {
        date = workout.date
        duration = workout.duration
        steps = workout.steps
    }
}

private struct ProfileRankTarget: Sendable {
    let metric: LeaderboardMetric
    let timeFrame: LeaderboardTimeFrame

    static let defaultTargets: [ProfileRankTarget] = [
        .init(metric: .climb, timeFrame: .weekly),
        .init(metric: .climb, timeFrame: .monthly),
        .init(metric: .climb, timeFrame: .allTime),
        .init(metric: .duration, timeFrame: .monthly),
        .init(metric: .pace, timeFrame: .allTime)
    ]

    func valueText(from workouts: [ProfileWorkoutSummary]) -> String {
        let filtered = workouts.filter { timeFrame.contains($0.date) }

        switch metric {
        case .climb:
            return filtered.reduce(0) { $0 + $1.steps }.formatted(.number.grouping(.automatic))
        case .duration:
            return ProfileFormatters.durationClock(filtered.reduce(0) { $0 + $1.duration })
        case .pace:
            let totalSteps = filtered.reduce(0) { $0 + $1.steps }
            let totalDuration = filtered.reduce(0) { $0 + $1.duration }
            guard totalDuration > 0 else { return "0" }
            let spm = Double(totalSteps) / (totalDuration / 60)
            return "\(Int(spm.rounded()))"
        case .workouts:
            return filtered.count.formatted(.number.grouping(.automatic))
        }
    }
}

private struct ProfileTrendSnapshot {
    let currentSteps: Int
    let previousSteps: Int

    init(workouts: [Workout], referenceDate: Date = Date(), calendar: Calendar = .current) {
        let currentInterval = calendar.dateInterval(of: .month, for: referenceDate)
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: referenceDate)
        let previousInterval = previousMonth.flatMap { calendar.dateInterval(of: .month, for: $0) }

        let comparisonPreviousInterval: DateInterval?
        if let previousInterval {
            let currentDay = calendar.component(.day, from: referenceDate)
            let previousMonthDays = calendar.range(of: .day, in: .month, for: previousInterval.start)?.count ?? currentDay
            let comparisonDayCount = min(currentDay, previousMonthDays)
            let end = calendar.date(byAdding: .day, value: comparisonDayCount, to: previousInterval.start) ?? previousInterval.end
            comparisonPreviousInterval = DateInterval(start: previousInterval.start, end: min(end, previousInterval.end))
        } else {
            comparisonPreviousInterval = nil
        }

        currentSteps = currentInterval.map { interval in
            workouts
                .filter { interval.contains($0.date) && $0.date <= referenceDate }
                .reduce(0) { $0 + $1.steps }
        } ?? 0

        previousSteps = comparisonPreviousInterval.map { interval in
            workouts
                .filter { interval.contains($0.date) }
                .reduce(0) { $0 + $1.steps }
        } ?? 0
    }

    var changeText: String {
        guard previousSteps > 0 else {
            return currentSteps.formatted(.number.grouping(.automatic))
        }

        let percent = Double(currentSteps - previousSteps) / Double(previousSteps) * 100
        let sign = percent >= 0 ? "+" : ""
        return "\(sign)\(Int(percent.rounded()))%"
    }

    var changeColor: Color {
        currentSteps >= previousSteps ? Color.accent : Color.red
    }
}

private enum ProfileFormatters {
    static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    static func durationClock(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }

        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}

#Preview("Profile") {
    NavigationStack {
        ProfileView()
    }
    .environment(AuthenticationViewModel())
    .environment(NetworkConnectivityService.shared)
    .modelContainer(
        for: [
            Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            ClimbAttempt.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self,
            LeaderboardStats.self
        ],
        inMemory: true
    )
    .preferredColorScheme(.dark)
}
