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
                VStack(spacing: 24) {
                    // Filter bar with metrics on top
                    LeaderboardFilterBar(
                        selectedMetric: $viewModel.selectedMetric,
                        selectedTimeFrame: $viewModel.selectedTimeFrame
                    )
                    .onChange(of: viewModel.selectedMetric) { _, _ in
                        Task { await loadData() }
                    }
                    .onChange(of: viewModel.selectedTimeFrame) { _, _ in
                        Task { await loadData() }
                    }

                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else if let error = viewModel.errorMessage {
                        errorView(error)
                    } else {
                        leaderboardContent
                    }
                }
                .padding(.vertical, 20)
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

    // MARK: - Leaderboard Content

    @ViewBuilder
    private var leaderboardContent: some View {
        VStack(spacing: 24) {
            // Top 3 Podium
            let topThree = Array(viewModel.leaderboardEntries.prefix(3))
            if !topThree.isEmpty {
                PodiumView(topThree: topThree, metric: viewModel.selectedMetric)
            }

            // Current user position (if not in top 3)
            if let userEntry = viewModel.userEntry, userEntry.rank > 3 {
                VStack(spacing: 12) {
                    Text("Your Position")
                        .font(.montserratSemiBold(size: 14))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)

                    CurrentUserPositionCard(entry: userEntry, metric: viewModel.selectedMetric)
                }
            }

            // Rest of leaderboard (4+)
            let remainingEntries = Array(viewModel.leaderboardEntries.dropFirst(3))
            if !remainingEntries.isEmpty {
                VStack(spacing: 12) {
                    HStack {
                        Text("Rankings")
                            .font(.montserratBold(size: 20))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)

                        Spacer()
                    }
                    .padding(.horizontal, 20)

                    ForEach(remainingEntries) { entry in
                        LeaderboardRow(
                            entry: entry,
                            metric: viewModel.selectedMetric
                        )
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
