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
    @EnvironmentObject private var tabRouter: TabRouter
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.modelContext) private var modelContext
    @Query private var workouts: [Workout]

    @State private var viewModel = LeaderboardViewModel()
    @State private var scrollResetTrigger = 0
    @State private var scrollProxy: ScrollViewProxy?
    @State private var isSearchExpanded = false
    @State private var showFilterSheet = false

    private enum ScrollTarget: Hashable {
        case top
        case userRow(String)
    }

    private var effectiveColorScheme: ColorScheme {
        colorScheme
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                    .onChange(of: viewModel.selectedMetric) { _, _ in
                        resetScrollPosition()
                        Task { await loadData() }
                    }
                    .onChange(of: viewModel.selectedTimeFrame) { _, _ in
                        resetScrollPosition()
                        Task { await loadData() }
                    }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            Color.clear
                                .frame(height: 0)
                                .id(ScrollTarget.top)

                            if viewModel.isOffline && viewModel.hasCachedEntries {
                                offlineBanner
                            } else if let error = viewModel.errorMessage, viewModel.hasCachedEntries {
                                errorBanner(error)
                            }

                            contentSection
                        }
                        .padding(.vertical, 16)
                    }
                    .onChange(of: scrollResetTrigger) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(ScrollTarget.top, anchor: .top)
                        }
                    }
                    .onAppear {
                        scrollProxy = proxy
                    }
                }
            }

            if shouldShowBlockingLoader {
                blockingLoader
                    .allowsHitTesting(false)
            }
        }
        .themedBackground()
        .navigationTitle("Leaderboard")
        .task {
            resetScrollPosition()
            await setupAndLoad()
        }
        .refreshable {
            await refreshData()
        }
        .onChange(of: tabRouter.selectedTab) { _, newTab in
            guard newTab == .leaderboard else { return }
            resetScrollPosition()
        }
    }

    private var dynamicTitle: String {
        let timeFrame = viewModel.selectedTimeFrame.displayName
        let metric = viewModel.selectedMetric.displayName(for: SettingsManager.shared.preferredWorkoutMetric)
        return "\(timeFrame) \(metric)"
    }

    private var header: some View {
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
                selectedMetric: $viewModel.selectedMetric
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
                .fill(colorScheme == .dark ? Color("Jet") : Color.gray.opacity(0.08))
        )
    }

    @ViewBuilder
    private var contentSection: some View {
        let entries = viewModel.displayedEntries
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

    private var shouldShowBlockingLoader: Bool {
        viewModel.displayedEntries.isEmpty && viewModel.isLoading
    }

    private var blockingLoader: some View {
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
                .fill(colorScheme == .dark ? Color("Jet") : Color.white)
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        )
    }

    // MARK: - Leaderboard Content

    /// Whether the user is in the top 5
    private var isUserInTop5: Bool {
        guard let userEntry = viewModel.userEntry else { return false }
        return userEntry.rank <= 5
    }

    /// Entries for the top 5 carousel
    private var top5Entries: [LeaderboardEntry] {
        Array(viewModel.displayedEntries.prefix(5))
    }

    /// Entries for the rankings list (#6+)
    private var remainingEntries: [LeaderboardEntry] {
        Array(viewModel.displayedEntries.dropFirst(5))
    }

    @ViewBuilder
    private func leaderboardContent(entries: [LeaderboardEntry]) -> some View {
        VStack(spacing: 20) {
            // "You're in #XX" banner (only when user is NOT in top 5)
            if let userEntry = viewModel.userEntry, !isUserInTop5 {
                UserPositionBanner(
                    entry: userEntry,
                    metric: viewModel.selectedMetric,
                    onTap: {
                        scrollToUserPosition()
                    }
                )
            }

            // Top 5 Carousel
            if !top5Entries.isEmpty {
                Top5CarouselView(
                    entries: top5Entries,
                    metric: viewModel.selectedMetric,
                    currentUserId: authVM.user?.uid
                )
            }

            // Rankings list (#6+)
            if !remainingEntries.isEmpty {
                LazyVStack(spacing: 12) {
                    ForEach(remainingEntries) { entry in
                        LeaderboardRow(
                            entry: entry,
                            metric: viewModel.selectedMetric
                        )
                        .id(ScrollTarget.userRow(entry.userId))
                        .onAppear {
                            viewModel.loadMoreEntriesIfNeeded(currentEntry: entry)
                        }
                    }
                }
            } else if entries.count <= 5 && entries.count > 0 {
                // Only top 5 or fewer entries exist - show simple message if user is the only one
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

    private func scrollToUserPosition() {
        guard let userEntry = viewModel.userEntry else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            scrollProxy?.scrollTo(ScrollTarget.userRow(userEntry.userId), anchor: .center)
        }
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
}

#Preview {
    NavigationStack {
        LeaderboardView()
            .environment(AuthenticationViewModel())
            .environmentObject(TabRouter())
    }
    .modelContainer(for: Workout.self, inMemory: true)
}
