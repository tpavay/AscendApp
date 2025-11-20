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

    private enum ScrollTarget: Hashable {
        case top
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
                        LazyVStack(spacing: 24) {
                            Color.clear
                                .frame(height: 0)
                                .id(ScrollTarget.top)

                            if viewModel.isLoading && viewModel.hasCachedEntries {
                                loadingNotice
                            }

                            if let error = viewModel.errorMessage, viewModel.hasCachedEntries {
                                errorBanner(error)
                            }

                            contentSection
                        }
                        .padding(.vertical, 20)
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

    private var header: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Leaderboards")
                        .font(.montserratBold(size: 32))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                    Spacer()
                }

                LeaderboardFilterBar(
                    searchText: $viewModel.searchText,
                    selectedMetric: $viewModel.selectedMetric,
                    selectedTimeFrame: $viewModel.selectedTimeFrame
                )

                Text(viewModel.resetStatusText)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)

            Rectangle()
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))
                .frame(height: 1)
        }
        .background(
            (effectiveColorScheme == .dark ? Color.jet : Color.white)
                .opacity(0.95)
        )
    }

    private var filterBar: some View {
        LeaderboardFilterBar(
            searchText: $viewModel.searchText,
            selectedMetric: $viewModel.selectedMetric,
            selectedTimeFrame: $viewModel.selectedTimeFrame
        )
    }

    @ViewBuilder
    private var contentSection: some View {
        let entries = viewModel.displayedEntries
        if entries.isEmpty {
            if !viewModel.isLoading {
                if let error = viewModel.errorMessage {
                    errorView(error)
                } else {
                    emptyStateView
                }
            }
        } else {
            leaderboardContent(entries: entries)
        }
    }

    private var loadingNotice: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Updating leaderboard…")
                .font(.montserratRegular(size: 14))
        }
        .foregroundStyle(colorScheme == .dark ? .white : .black)
        .padding(.horizontal, 20)
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

    @ViewBuilder
    private func leaderboardContent(entries: [LeaderboardEntry]) -> some View {
        VStack(spacing: 24) {
            if let userEntry = viewModel.userEntry {
                VStack(spacing: 12) {
                    Text("Your Position")
                        .font(.montserratSemiBold(size: 14))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)

                    CurrentUserPositionCard(entry: userEntry, metric: viewModel.selectedMetric)
                }
            }

            LazyVStack(spacing: 12) {
                HStack {
                    Text("Rankings")
                        .font(.montserratBold(size: 20))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    Spacer()
                }
                .padding(.horizontal, 20)

                ForEach(entries) { entry in
                    LeaderboardRow(
                        entry: entry,
                        metric: viewModel.selectedMetric
                    )
                    .onAppear {
                        viewModel.loadMoreEntriesIfNeeded(currentEntry: entry)
                    }
                }
            }
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
            RoundedRectangle(cornerRadius: 16)
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
