//
//  LeaderboardView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI
import SwiftData

struct LeaderboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.modelContext) private var modelContext
    @Query private var workouts: [Workout]

    @State private var viewModel: LeaderboardViewModel
    @State private var scrollResetTrigger = 0
    @State private var isSearchExpanded = false
    @State private var showFilterSheet = false
    @State private var settingsManager = SettingsManager.shared
    @FocusState private var isSearchFocused: Bool

    private let lockedMetric: LeaderboardMetric?

    private enum ScrollTarget: Hashable {
        case top
    }

    @MainActor
    init(lockedMetric: LeaderboardMetric? = nil) {
        self.lockedMetric = lockedMetric

        let vm = LeaderboardViewModel()
        if let lockedMetric {
            vm.selectedMetric = lockedMetric
            vm.selectedTimeFrame = .weekly
        }
        _viewModel = State(initialValue: vm)
    }

    private var effectiveColorScheme: ColorScheme {
        colorScheme
    }

    private var navigationTitleText: String {
        if let lockedMetric {
            return lockedMetric.displayName(for: settingsManager.preferredWorkoutMetric)
        }
        return "Leaderboards"
    }

    private var lockedTimeFrames: [LeaderboardTimeFrame] {
        [.weekly, .monthly, .allTime]
    }

    private var isLockedMetricView: Bool {
        lockedMetric != nil
    }

    private var lockedListSurfaceColor: Color {
        colorScheme == .dark ? .jet : .night.opacity(0.07)
    }

    @ViewBuilder
    private var screenBackground: some View {
        if isLockedMetricView {
            lockedListSurfaceColor
                .ignoresSafeArea()
        } else {
            ThemedBackground()
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if !isLockedMetricView {
                    header
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: isLockedMetricView ? 0 : 20) {
                            Color.clear
                                .frame(height: 0)
                                .id(ScrollTarget.top)

                            if viewModel.isOffline && viewModel.hasCachedEntries {
                                offlineBanner
                                    .padding(.bottom, isLockedMetricView ? 12 : 0)
                            } else if let error = viewModel.errorMessage, viewModel.hasCachedEntries {
                                errorBanner(error)
                                    .padding(.bottom, isLockedMetricView ? 12 : 0)
                            }

                            contentSection
                        }
                        .padding(.top, isLockedMetricView ? 0 : 16)
                        .padding(.bottom, 16)
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if isLockedMetricView {
                            LeaderboardStickyHeaderView(
                                title: navigationTitleText,
                                selectedTimeFrame: $viewModel.selectedTimeFrame,
                                timeFrames: lockedTimeFrames,
                                onBack: { dismiss() }
                            )
                        }
                    }
                    .onChange(of: scrollResetTrigger) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(ScrollTarget.top, anchor: .top)
                        }
                    }
                }
            }

            if shouldShowBlockingLoader {
                blockingLoader
                    .allowsHitTesting(false)
            }
        }
        .background {
            screenBackground
        }
        .navigationTitle(isLockedMetricView ? "" : navigationTitleText)
        .navigationBarTitleDisplayMode(isLockedMetricView ? .inline : .large)
        .navigationBarBackButtonHidden(isLockedMetricView)
        .toolbar(isLockedMetricView ? .hidden : .visible, for: .navigationBar)
        .task {
            resetScrollPosition()
            await setupAndLoad()
        }
        .onChange(of: viewModel.selectedMetric) { _, newMetric in
            if let lockedMetric, newMetric != lockedMetric {
                viewModel.selectedMetric = lockedMetric
                return
            }
            resetScrollPosition()
            Task { await loadData() }
        }
        .onChange(of: viewModel.selectedTimeFrame) { _, _ in
            resetScrollPosition()
            Task { await loadData() }
        }
        .refreshable {
            await refreshData()
        }
        .onChange(of: authVM.displayName) { _, _ in
            syncCurrentUserEntry()
        }
        .onChange(of: authVM.displayPhotoURL) { _, _ in
            syncCurrentUserEntry()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    isSearchFocused = false
                } label: {
                    Text("Done")
                        .font(.montserratSemiBold(size: 16))
                }
            }
        }
    }

    private var dynamicTitle: String {
        let timeFrame = viewModel.selectedTimeFrame.displayName
        let metric = viewModel.selectedMetric.displayName(for: SettingsManager.shared.preferredWorkoutMetric)
        return "\(timeFrame) \(metric)"
    }

    @ViewBuilder
    private var header: some View {
        unlockedHeader
    }

    private var unlockedHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Dynamic title
                Text(dynamicTitle)
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                Spacer()

                // Search button
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSearchExpanded.toggle()
                    }
                    HapticsManager.shared.trigger(.lightImpact)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                }

                // Filter button
                Button {
                    showFilterSheet = true
                    HapticsManager.shared.trigger(.lightImpact)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, isSearchExpanded ? 12 : 16)

            // Expandable search field
            if isSearchExpanded {
                searchField
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
            }

            Rectangle()
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
                .frame(height: 1)
        }
        .background(
            (effectiveColorScheme == .dark ? Color.jet : Color.white)
                .opacity(0.95)
        )
        .sheet(isPresented: $showFilterSheet) {
            LeaderboardFilterSheet(
                selectedTimeFrame: $viewModel.selectedTimeFrame,
                selectedMetric: $viewModel.selectedMetric,
                allowsMetricSelection: true
            )
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search for a player", text: $viewModel.searchText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .font(.montserratRegular(size: 14))
                .focused($isSearchFocused)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isSearchExpanded = false
                    viewModel.searchText = ""
                }
            } label: {
                Text("Cancel")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? .jet : .night.opacity(0.07))
        )
    }

    @ViewBuilder
    private var contentSection: some View {
        let entries = viewModel.displayedEntries
        if isLockedMetricView {
            lockedMetricContentSection(entries: entries)
        } else {
            if entries.isEmpty {
                if !viewModel.isLoading {
                    if viewModel.isOffline {
                        offlineEmptyStateView
                    } else if let error = viewModel.errorMessage {
                        errorView(error)
                    } else {
                        emptyStateView
                    }
                }
            } else {
                leaderboardContent(entries: entries)
            }
        }
    }

    @ViewBuilder
    private func lockedMetricContentSection(entries: [LeaderboardEntry]) -> some View {
        let state = presentationState(for: entries)

        VStack(spacing: 0) {
            if !state.podiumEntries.isEmpty {
                LeaderboardHeroView(
                    podiumEntries: state.podiumEntries,
                    metric: viewModel.selectedMetric
                )
            }

            if entries.isEmpty, !viewModel.isLoading {
                if viewModel.isOffline {
                    offlineEmptyStateView
                        .padding(.top, 26)
                        .padding(.bottom, 20)
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                        .padding(.top, 26)
                        .padding(.bottom, 20)
                } else {
                    emptyStateView
                        .padding(.top, 26)
                        .padding(.bottom, 20)
                }
            } else {
                VStack(spacing: 12) {
                    if let userEntry = state.pinnedUserEntry {
                        LeaderboardUserRowView(
                            entry: userEntry,
                            metric: viewModel.selectedMetric
                        )
                    }

                    if !state.listEntries.isEmpty {
                        LeaderboardRowListView(
                            entries: state.listEntries,
                            metric: viewModel.selectedMetric,
                            onEntryAppear: { entry in
                                viewModel.loadMoreEntriesIfNeeded(currentEntry: entry)
                            }
                        )
                    } else if entries.count == 1, let entry = entries.first, entry.isCurrentUser {
                        Text("You're the first on this leaderboard!")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                            .multilineTextAlignment(.center)
                            .padding(.top, 14)
                            .padding(.horizontal, 40)
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
        }
        .background(
            isLockedMetricView
                ? lockedListSurfaceColor
                : Color.clear
        )
    }

    private var shouldShowBlockingLoader: Bool {
        viewModel.displayedEntries.isEmpty && viewModel.isLoading
    }

    private var blockingLoader: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.38 : 0.12)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                Text("Loading leaderboard…")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark ? Color.jet : Color.white)
            )
        }
    }

    // MARK: - Leaderboard Content

    private struct LeaderboardPresentationState {
        let podiumEntries: [LeaderboardEntry]
        let pinnedUserEntry: LeaderboardEntry?
        let listEntries: [LeaderboardEntry]
    }

    @ViewBuilder
    private func leaderboardContent(entries: [LeaderboardEntry]) -> some View {
        let state = presentationState(for: entries)

        VStack(spacing: 20) {
            LeaderboardPodiumView(
                entries: state.podiumEntries,
                metric: viewModel.selectedMetric
            )

            if let userEntry = state.pinnedUserEntry {
                LeaderboardUserRowView(
                    entry: userEntry,
                    metric: viewModel.selectedMetric
                )
            }

            if !state.listEntries.isEmpty {
                LeaderboardRowListView(
                    entries: state.listEntries,
                    metric: viewModel.selectedMetric,
                    onEntryAppear: { entry in
                        viewModel.loadMoreEntriesIfNeeded(currentEntry: entry)
                    }
                )
            } else if entries.count <= 3 && entries.count > 0 {
                if entries.count == 1, let entry = entries.first, entry.isCurrentUser {
                    VStack(spacing: 8) {
                        Text("You're the first on this leaderboard!")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 40)
                }
            }
        }
    }

    private func presentationState(for entries: [LeaderboardEntry]) -> LeaderboardPresentationState {
        let podiumEntries = entries.filter { $0.rank <= 3 }
        let listEntries = entries.filter { $0.rank > 3 }

        guard let userEntry = viewModel.userEntry else {
            return LeaderboardPresentationState(
                podiumEntries: podiumEntries,
                pinnedUserEntry: nil,
                listEntries: listEntries
            )
        }

        let shouldPinUserRow = shouldPinUserRow(userEntry)
        if shouldPinUserRow {
            let dedupedRows = listEntries.filter { $0.userId != userEntry.userId }
            return LeaderboardPresentationState(
                podiumEntries: podiumEntries,
                pinnedUserEntry: userEntry,
                listEntries: dedupedRows
            )
        }

        return LeaderboardPresentationState(
            podiumEntries: podiumEntries,
            pinnedUserEntry: nil,
            listEntries: listEntries
        )
    }

    private func shouldPinUserRow(_ entry: LeaderboardEntry) -> Bool {
        guard entry.rank > 5 else { return false }
        let trimmedSearch = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSearch.isEmpty
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.red)

            Text("Error")
                .font(.montserratBold(size: 24))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

            Text(message)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 40)
    }

    private var offlineBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.orange)

            Text("Offline - showing cached data")
                .font(.montserratRegular(size: 13))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.orange.opacity(0.15) : Color.orange.opacity(0.1))
        )
        .padding(.horizontal, 20)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(message)
                .font(.montserratRegular(size: 13))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.red.opacity(0.2) : Color.red.opacity(0.1))
        )
        .padding(.horizontal, 20)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 42))
                .foregroundStyle(.accent)

            Text("No leaderboard data yet")
                .font(.montserratBold(size: 20))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

            Text("Pull to refresh after you've completed a workout to see how you stack up.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 40)
    }

    private var offlineEmptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 50))
                .foregroundStyle(.orange)

            Text("You're Offline")
                .font(.montserratBold(size: 24))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

            Text("Please check your internet connection and pull to refresh.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Data Loading

    private func setupAndLoad() async {
        guard let userId = authVM.user?.uid else { return }
        if let lockedMetric {
            viewModel.selectedMetric = lockedMetric
            if !lockedTimeFrames.contains(viewModel.selectedTimeFrame) {
                viewModel.selectedTimeFrame = .weekly
            }
        }
        viewModel.configure(userId: userId, modelContext: modelContext)
        await loadData()
    }

    private func loadData() async {
        guard let userId = authVM.user?.uid else { return }
        await viewModel.loadLeaderboard(userId: userId)
    }

    private func refreshData() async {
        guard let userId = authVM.user?.uid else { return }
        await viewModel.refreshLeaderboard(
            userId: userId,
            displayName: authVM.displayName,
            photoURL: authVM.displayPhotoURL,
            workouts: workouts
        )
    }

    private func resetScrollPosition() {
        scrollResetTrigger &+= 1
    }

    private func syncCurrentUserEntry() {
        viewModel.updateCurrentUserProfile(
            userId: authVM.user?.uid,
            displayName: authVM.displayName,
            photoURL: authVM.displayPhotoURL
        )
    }
}

#Preview {
    NavigationStack {
        LeaderboardView()
            .environment(AuthenticationViewModel())
            .environment(TabRouter())
    }
    .modelContainer(for: [Workout.self, WorkoutSourceLink.self], inMemory: true)
}
