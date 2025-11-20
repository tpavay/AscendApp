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
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.modelContext) private var modelContext
    @Query private var workouts: [Workout]

    @State private var viewModel = LeaderboardViewModel()

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: 24) {
                    titleHeader
                    filterBar
                    resetNotice

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

            if shouldShowBlockingLoader {
                blockingLoader
                    .allowsHitTesting(false)
            }
        }
        .themedBackground()
        .navigationTitle("Leaderboard")
        .task {
            await setupAndLoad()
        }
        .refreshable {
            await refreshData()
        }
    }

    private var titleHeader: some View {
        HStack {
            Text("Leaderboards")
                .font(.montserratBold(size: 32))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var filterBar: some View {
        LeaderboardFilterBar(
            searchText: $viewModel.searchText,
            selectedMetric: $viewModel.selectedMetric,
            selectedTimeFrame: $viewModel.selectedTimeFrame
        )
        .onChange(of: viewModel.selectedMetric) { _, _ in
            Task { await loadData() }
        }
        .onChange(of: viewModel.selectedTimeFrame) { _, _ in
            Task { await loadData() }
        }
    }

    private var resetNotice: some View {
        Text(viewModel.resetStatusText)
            .font(.montserratRegular(size: 13))
            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
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
            photoURL: authVM.photoURL,
            workouts: workouts
        )
    }
}

#Preview {
    NavigationStack {
        LeaderboardView()
            .environment(AuthenticationViewModel())
    }
    .modelContainer(for: Workout.self, inMemory: true)
}
