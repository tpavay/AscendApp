//
//  HomeView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(TabRouter.self) private var tabRouter
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @State private var importCoordinator = WorkoutImportCoordinator.shared
    @State private var homeDashboard = HomeDashboardViewModel()
    @State private var showingImportSheet = false
    @State private var showingClimbBrowse = false
    @State private var selectedHomeClimb: Climb?
    @State private var globeViewModel = GlobeViewModel()
    @AppStorage("firstLaunchDate") private var firstLaunchDate: Double = 0
    @State private var autoImportedReviewWorkout: Workout?

    private var isHomeTabSelected: Bool {
        tabRouter.selectedTab == .home
    }

    private var hasBlockingModalPresentation: Bool {
        showingImportSheet
    }

    private var greeting: String {
        // If first launch date not set, this is the first launch
        if firstLaunchDate == 0 {
            return "Welcome"
        }

        let firstDate = Date(timeIntervalSince1970: firstLaunchDate)
        let isFirstDay = Calendar.current.isDate(firstDate, inSameDayAs: Date())

        if isFirstDay {
            return "Welcome"
        }

        // Time-based greeting
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good Morning"
        case 12..<17:
            return "Good Afternoon"
        default:
            return "Good Evening"
        }
    }

    private var greetingWithName: String {
        if authVM.displayName.isEmpty {
            return greeting
        }
        // Use just the first name (first part before space)
        let firstName = authVM.displayName.split(separator: " ").first.map(String.init) ?? authVM.displayName
        return "\(greeting), \(firstName)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                AscendWordmark(
                    size: 16,
                    letterColor: colorScheme == .dark ? .white : .black
                )

                Spacer()

                importBell
                .onChange(of: importCoordinator.attentionCount) { oldValue, newValue in
                    print("🔄 HomeView detected count change from \(oldValue) to \(newValue)")
                    syncAutoImportedReviewPresentation()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 20) {
                    HomeWeeklyStatsStrip(stats: homeDashboard.weeklyStats)
                        .padding(.horizontal, 4)

                    ClimbCardView(
                        viewModel: globeViewModel,
                        onOpenClimb: { climb in
                            TelemetryManager.shared.track(
                                LiveClimbAnalyticsEvent.homeDailyTapped(
                                    climb: climb,
                                    homeState: globeViewModel.homeCardState
                                )
                            )
                            selectedHomeClimb = climb
                        }
                    )

                    HomeRankGlobeRow(
                        weeklyRank: homeDashboard.weeklyRank,
                        rankPercentile: homeDashboard.rankPercentile,
                        completedClimbCount: homeDashboard.completedClimbCount,
                        onRankTapped: { tabRouter.selectedTab = .leaderboard },
                        onGlobeTapped: { presentClimbBrowse() }
                    )

                    if !homeDashboard.recentPersonalRecords.isEmpty {
                        HomeRecentPRsSection(
                            records: homeDashboard.recentPersonalRecords,
                            workouts: workouts
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 124)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaPadding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .themedBackground()
        .navigationDestination(item: $selectedHomeClimb) { climb in
            ClimbDetailView(climb: climb, analyticsEntryPoint: .homeDaily)
        }
        .navigationDestination(isPresented: $showingClimbBrowse) {
            ClimbBrowseView(viewModel: globeViewModel, analyticsEntryPoint: .homeExplore)
        }
        .sheet(isPresented: $showingImportSheet) {
            WorkoutImportSheet()
        }
        .sheet(item: $autoImportedReviewWorkout, onDismiss: {
            importCoordinator.dismissCurrentAutoImportedReview()
        }) { workout in
            AutoImportedWorkoutReviewView(
                workout: workout,
                onDone: {
                    importCoordinator.completeAutoImportedReview(for: workout.id)
                    autoImportedReviewWorkout = nil
                },
                onDelete: {
                    importCoordinator.completeAutoImportedReview(for: workout.id)
                    autoImportedReviewWorkout = nil
                }
            )
            .appSheetStyle(.detents([.fraction(0.75), .large]), isInteractiveDismissDisabled: true)
        }
        .task {
            // Set first launch date if not already set
            if firstLaunchDate == 0 {
                firstLaunchDate = Date().timeIntervalSince1970
            }

            // Configure the unified import service with model context
            importCoordinator.configure(modelContext: modelContext)
            globeViewModel.loadIfNeeded(modelContext: modelContext)
            refreshHomeDashboard(forceRank: true)
            refreshLiveClimbCommunityStats()

            // Check for workouts from all sources on app launch
            await importCoordinator.refreshPendingImports(trigger: .homeEntry)
            syncAutoImportedReviewPresentation()
        }
        .onChange(of: tabRouter.selectedTab) { _, newValue in
            guard newValue == .home else { return }
            refreshHomeDashboard()
            refreshLiveClimbCommunityStats()
            Task {
                await importCoordinator.refreshPendingImports(trigger: .homeEntry)
                syncAutoImportedReviewPresentation()
            }
        }
        .onChange(of: importCoordinator.currentAutoImportedReviewWorkoutID) { _, _ in
            syncAutoImportedReviewPresentation()
        }
        .onChange(of: showingImportSheet) { _, isShowing in
            guard !isShowing else { return }
            syncAutoImportedReviewPresentation()
        }
        .onChange(of: authVM.user?.uid) { _, _ in
            refreshHomeDashboard(forceRank: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutsDidChange)) { _ in
            refreshHomeDashboard(forceRank: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Check for new workouts when app comes to foreground (throttled to prevent spam)
            refreshHomeDashboard(forceRank: true)
            refreshLiveClimbCommunityStats()
            Task {
                await importCoordinator.refreshPendingImports(trigger: .automatic)
                syncAutoImportedReviewPresentation()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbStateDidChange)) { _ in
            globeViewModel.refresh(modelContext: modelContext)
            refreshHomeDashboard()
            refreshLiveClimbCommunityStats()
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbCatalogDidChange)) { _ in
            globeViewModel.reloadCatalog(modelContext: modelContext)
            refreshHomeDashboard()
            refreshLiveClimbCommunityStats()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            // Reset throttling when app goes to background so next foreground check works
            importCoordinator.resetAutomaticCheckThrottle()
        }
    }

    private var importBell: some View {
        NotificationBellView(pendingImports: importCoordinator.attentionCount) {
            openImportInbox()
        }
        .frame(width: 44, height: 44)
    }

    private func presentClimbBrowse() {
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.homeExploreTapped(
                totalClimbs: globeViewModel.visibleClimbs.count
            )
        )
        globeViewModel.prepareForBrowseEntry()
        showingClimbBrowse = true
    }

    private func openImportInbox() {
        Task {
            _ = await importCoordinator.prepareImportInbox()
            showingImportSheet = true
        }
    }

    private func syncAutoImportedReviewPresentation() {
        guard isHomeTabSelected else { return }
        guard !hasBlockingModalPresentation else { return }

        if importCoordinator.presentPendingAutoImportedReviewOnHomeIfNeeded() {
            autoImportedReviewWorkout = resolveWorkout(id: importCoordinator.currentAutoImportedReviewWorkoutID)
            if autoImportedReviewWorkout == nil {
                importCoordinator.dismissCurrentAutoImportedReview()
            }
            return
        }

        if importCoordinator.currentAutoImportedReviewWorkoutID == nil {
            autoImportedReviewWorkout = nil
        }
    }

    private func refreshLiveClimbCommunityStats() {
        Task {
            await globeViewModel.refreshLiveClimbCommunityStats()
        }
    }

    private func refreshHomeDashboard(forceRank: Bool = false) {
        homeDashboard.refreshLocalData(modelContext: modelContext)
        homeDashboard.refreshWeeklyRank(
            userId: authVM.user?.uid,
            displayName: authVM.displayName,
            photoURL: authVM.customProfilePictureURL ?? authVM.photoURL,
            modelContext: modelContext,
            forceRemote: forceRank
        )
    }

    private func resolveWorkout(id: UUID?) -> Workout? {
        guard let id else { return nil }
        let workoutID = id
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.id == workoutID
            }
        )

        return try? modelContext.fetch(descriptor).first
    }
}

private struct HomeExploreGlobeCard: View {
    let climbs: [Climb]
    let communityClimbersCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                thumbnailStack

                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
                        .font(.montserratBold(size: 15))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)

                    Text(subtitleText)
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                AppIcon(token: .disclosureChevronRight, pointSize: 14, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.48))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open the Live Climbs globe")
    }

    private var thumbnailStack: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.black.opacity(0.42))

            ForEach(Array(stackedClimbs.enumerated()), id: \.offset) { index, climb in
                ClimbArtworkView(climb: climb, variant: .thumb)
                    .frame(width: 30, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
                    .offset(x: CGFloat(index) * 23)
                    .zIndex(Double(index))
            }
            .padding(.leading, 4)
        }
        .frame(width: 80, height: 40)
        .clipped()
        .accessibilityHidden(true)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(hex: "111111"))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
    }

    private var stackedClimbs: [Climb] {
        let featuredIDs = [
            "mount-etna",
            "empire-state-building",
            "burj-khalifa"
        ]

        let featuredClimbs = featuredIDs.compactMap { id in
            climbs.first { $0.id == id }
        }

        return Array(uniqueClimbs(featuredClimbs + climbs).prefix(3))
    }

    private var titleText: String {
        if communityClimbersCount == 1 {
            return "Join 1 climber worldwide"
        }

        if communityClimbersCount > 0 {
            return "Join \(communityClimbersCount.formatted()) climbers worldwide"
        }

        return "Join climbers worldwide"
    }

    private var subtitleText: String {
        if climbs.count >= 100 {
            return "100+ climbs from Etna to Dubai"
        }

        if climbs.count > 0 {
            return "\(climbs.count.formatted()) climbs from Etna to Dubai"
        }

        return "From Etna to Dubai"
    }

    private func uniqueClimbs(_ climbs: [Climb]) -> [Climb] {
        var seenIDs: Set<String> = []
        var unique: [Climb] = []

        for climb in climbs {
            guard !seenIDs.contains(climb.id) else { continue }
            seenIDs.insert(climb.id)
            unique.append(climb)
        }

        return unique.isEmpty ? [.preview] : unique
    }
}

private struct HomeWeeklyStatsStrip: View {
    let stats: HomeWeeklyStats

    var body: some View {
        HStack(spacing: 8) {
            Text("This week")
                .font(.montserratMedium(size: 13))
                .foregroundStyle(Color.primary.opacity(0.6))

            dot

            statRow(value: "\(stats.climbs)", label: stats.climbs == 1 ? "climb" : "climbs")

            dot

            Text(stats.durationText)
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(Color.primary)

            dot

            statRow(value: stats.steps.formatted(), label: "steps")

            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: \(stats.climbs) climbs, \(stats.durationText), \(stats.steps.formatted()) steps")
    }

    private var dot: some View {
        Text("·")
            .font(.montserratRegular(size: 13))
            .foregroundStyle(Color.primary.opacity(0.4))
    }

    private func statRow(value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(Color.primary)

            Text(label)
                .font(.montserratRegular(size: 13))
                .foregroundStyle(Color.primary.opacity(0.6))
        }
    }
}

private struct HomeRankGlobeRow: View {
    let weeklyRank: Int?
    let rankPercentile: Int?
    let completedClimbCount: Int
    let onRankTapped: () -> Void
    let onGlobeTapped: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HomeRankCard(
                rank: weeklyRank,
                percentile: rankPercentile,
                action: onRankTapped
            )

            HomeMyGlobeCard(
                count: completedClimbCount,
                action: onGlobeTapped
            )
        }
    }
}

private struct HomeRankCard: View {
    let rank: Int?
    let percentile: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text("YOUR RANK THIS WEEK")
                    .font(.montserratSemiBold(size: 10))
                    .tracking(1.2)
                    .foregroundStyle(Color.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(rank.map { "#\($0)" } ?? "—")
                    .font(.montserratBold(size: 34))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(percentileText)
                    .font(.montserratMedium(size: 10))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .frame(minHeight: 116)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var percentileText: String {
        if let rank, rank == 1 {
            return "TOP OF THE LEADERBOARD"
        }
        guard let percentile else { return "Climb to be ranked" }
        return "TOP \(percentile)% OF CLIMBERS"
    }

    private var accessibilityLabel: String {
        guard let rank else { return "Not yet ranked. Climb to be ranked." }
        if rank == 1 {
            return "Your rank this week: number 1. Top of the leaderboard."
        }
        if let percentile {
            return "Your rank this week: \(rank), top \(percentile) percent of climbers."
        }
        return "Your rank this week: \(rank)"
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(hex: "111111"))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
    }
}

private struct HomeMyGlobeCard: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MY GLOBE")
                        .font(.montserratSemiBold(size: 10))
                        .tracking(1.2)
                        .foregroundStyle(Color.accent)

                    Text("\(count)")
                        .font(.montserratBold(size: 34))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(count == 1 ? "climb completed" : "climbs completed")
                        .font(.montserratMedium(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image("HomeMyGlobeArtwork")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(minHeight: 116)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("My globe: \(count) \(count == 1 ? "climb" : "climbs") completed")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(hex: "111111"))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
    }
}

private struct HomeRecentPRsSection: View {
    let records: [HomeRecentPRRecord]
    let workouts: [Workout]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("RECENT PERSONAL RECORDS")
                    .font(.montserratSemiBold(size: 11))
                    .tracking(1.2)
                    .foregroundStyle(Color.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer()

                NavigationLink {
                    BestEffortsListView(workouts: workouts)
                } label: {
                    HStack(spacing: 4) {
                        Text("VIEW ALL")
                            .font(.montserratSemiBold(size: 11))
                            .tracking(0.8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View all personal records")
            }

            HStack(spacing: 12) {
                ForEach(records) { record in
                    NavigationLink {
                        BestEffortRecordDetailView(
                            metric: record.metric,
                            workouts: workouts
                        )
                    } label: {
                        HomePRCard(record: record)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct HomePRCard: View {
    let record: HomeRecentPRRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.label)
                .font(.montserratSemiBold(size: 9))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(record.value)
                .font(.montserratBold(size: 22))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 74, maxHeight: 74, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "111111"))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.label): \(record.value)\(record.isNew ? ", new personal record" : "")")
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environment(AuthenticationViewModel())
            .environment(TabRouter())
    }
    .modelContainer(
        for: [
            Workout.self,
            WorkoutSourceLink.self,
            Routine.self,
            RoutineFolder.self,
            ClimbAttempt.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self
        ],
        inMemory: true
    )
}
