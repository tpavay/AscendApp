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
    @State private var showingImportSheet = false
    @State private var showingWorkoutEntrySheet = false
    @State private var showingWorkoutForm = false
    @State private var showingCompletedView = false
    @State private var completedWorkout: Workout?
    @State private var showingRoutinesView = false
    @State private var showingClimbBrowse = false
    @State private var selectedHomeClimb: Climb?
    @State private var globeViewModel = GlobeViewModel()
    @AppStorage("firstLaunchDate") private var firstLaunchDate: Double = 0
    @State private var autoImportedReviewWorkout: Workout?

    private var isHomeTabSelected: Bool {
        tabRouter.selectedTab == .home
    }

    private var hasBlockingModalPresentation: Bool {
        showingWorkoutEntrySheet ||
        showingWorkoutForm ||
        showingCompletedView ||
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
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Text(greetingWithName)
                        .font(.montserratSemiBold(size: 20))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    Spacer()

                    importBell
                    .onChange(of: importCoordinator.attentionCount) { oldValue, newValue in
                        print("🔄 HomeView detected count change from \(oldValue) to \(newValue)")
                        syncAutoImportedReviewPresentation()
                    }
                }

                VStack(spacing: 20) {
                    ThisWeekCard(workouts: workouts)

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

                    HomeExploreGlobeCard(climbs: globeViewModel.visibleClimbs) {
                        presentClimbBrowse()
                    }

                    RoutinesHomeCard()

                    HomeLogWorkoutButton {
                        showingWorkoutEntrySheet = true
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .safeAreaPadding(.top, 8)
        .themedBackground()
        .navigationDestination(item: $selectedHomeClimb) { climb in
            ClimbDetailView(climb: climb, analyticsEntryPoint: .homeDaily)
        }
        .navigationDestination(isPresented: $showingClimbBrowse) {
            ClimbBrowseView(viewModel: globeViewModel, analyticsEntryPoint: .homeExplore)
        }
        .navigationDestination(isPresented: $showingRoutinesView) {
            RoutinesView()
        }
        .sheet(isPresented: $showingWorkoutEntrySheet) {
            HomeWorkoutActionSheet(
                onManualEntry: presentWorkoutForm,
                onStartRoutine: presentRoutines,
                onImportWorkouts: presentImportSheet,
                pendingImportCount: importCoordinator.attentionCount
            )
            .appSheetStyle(.fitted())
        }
        .sheet(isPresented: $showingWorkoutForm) {
            WorkoutFormView(
                showingWorkoutForm: $showingWorkoutForm,
                onWorkoutCompleted: { workout in
                    completedWorkout = workout
                    showingWorkoutForm = false

                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        showingCompletedView = true
                    }
                }
            )
            .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: $showingCompletedView) {
            if let completedWorkout {
                WorkoutShareCarouselView(
                    workout: completedWorkout,
                    workoutCount: workouts.count,
                    onDismiss: {
                        showingCompletedView = false
                    }
                )
            }
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

            // Check for workouts from all sources on app launch
            await importCoordinator.refreshPendingImports(trigger: .homeEntry)
            syncAutoImportedReviewPresentation()
        }
        .onChange(of: tabRouter.selectedTab) { _, newValue in
            guard newValue == .home else { return }
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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Check for new workouts when app comes to foreground (throttled to prevent spam)
            Task {
                await importCoordinator.refreshPendingImports(trigger: .automatic)
                syncAutoImportedReviewPresentation()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbStateDidChange)) { _ in
            globeViewModel.refresh(modelContext: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbCatalogDidChange)) { _ in
            globeViewModel.reloadCatalog(modelContext: modelContext)
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

    private func presentWorkoutForm() {
        showingWorkoutEntrySheet = false

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            showingWorkoutForm = true
        }
    }

    private func presentRoutines() {
        showingWorkoutEntrySheet = false

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            showingRoutinesView = true
        }
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

    private func presentImportSheet() {
        showingWorkoutEntrySheet = false

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await importCoordinator.refreshPendingImports(trigger: .manualReview)
            showingImportSheet = true
        }
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

                    Text("From Etna to Dubai")
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(.white.opacity(0.56))
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
        if climbs.count >= 100 {
            return "Explore 100+ climbs"
        }

        if climbs.count > 0 {
            return "Explore \(climbs.count.formatted()) climbs"
        }

        return "Explore climbs"
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
            ClimbAttempt.self
        ],
        inMemory: true
    )
}
