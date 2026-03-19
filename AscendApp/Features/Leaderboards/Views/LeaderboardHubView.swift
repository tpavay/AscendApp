//
//  LeaderboardHubView.swift
//  AscendApp
//

import SwiftUI
import SwiftData

struct LeaderboardHubView: View {
    private enum LoadMode {
        case fast
        case refresh
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(TabRouter.self) private var tabRouter
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.modelContext) private var modelContext
    @Query private var workouts: [Workout]
    @State private var settingsManager = SettingsManager.shared

    @State private var selectedTimeFrame: LeaderboardTimeFrame = .weekly
    @State private var previewEntries: [LeaderboardMetric: [LeaderboardEntry]] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var activeLoadID = UUID()

    private let repository = LeaderboardRepository.shared
    private let leaderboardService = LeaderboardService.shared
    private let previewLimit = 3

    private var preferredMetric: WorkoutMetric {
        settingsManager.preferredWorkoutMetric
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                hubHeader

                if hasAnyEntries {
                    ForEach(LeaderboardMetric.allCases) { metric in
                        LeaderboardCategoryCard(
                            metric: metric,
                            entries: previewEntries[metric] ?? [],
                            preferredMetric: preferredMetric,
                            selectedTimeFrame: selectedTimeFrame
                        )
                    }
                } else if isLoading {
                    loadingState
                } else if let errorMessage {
                    globalErrorState(message: errorMessage)
                } else {
                    globalEmptyState
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .themedBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await loadPreviews(mode: .fast) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, tabRouter.selectedTab == .leaderboard else { return }
            Task { await loadPreviews(mode: .fast) }
        }
        .onChange(of: selectedTimeFrame) { _, _ in
            Task { await loadPreviews(mode: .fast) }
        }
        .refreshable {
            await loadPreviews(mode: .refresh)
        }
    }

    private var hasAnyEntries: Bool {
        previewEntries.values.contains { !$0.isEmpty }
    }

    private func loadPreviews(mode: LoadMode) async {
        let loadID = UUID()
        activeLoadID = loadID
        isLoading = true
        errorMessage = nil

        defer {
            if activeLoadID == loadID {
                isLoading = false
            }
        }

        guard let userId = authVM.user?.uid else {
            if activeLoadID == loadID {
                previewEntries = [:]
                errorMessage = "Sign in to view leaderboard data."
            }
            return
        }

        if mode == .refresh {
            do {
                leaderboardService.configure(modelContext: modelContext)
                try leaderboardService.updateAllTimeFrames(for: userId, workouts: workouts)
                try await leaderboardService.syncToFirestore(
                    userId: userId,
                    displayName: authVM.displayName,
                    photoURL: authVM.displayPhotoURL
                )
            } catch {
                // Continue to fetch remote standings even if local sync fails.
            }
        }

        var fetchedEntries: [LeaderboardMetric: [LeaderboardEntry]] = [:]
        var failedMetrics = 0
        let repository = self.repository
        let previewLimit = self.previewLimit
        let preferredMetric = self.preferredMetric
        let metricResults = await withTaskGroup(
            of: (LeaderboardMetric, [FirestoreLeaderboardStats]?, Bool).self,
            returning: [(LeaderboardMetric, [FirestoreLeaderboardStats]?, Bool)].self
        ) { group in
            for metric in LeaderboardMetric.allCases {
                group.addTask {
                    do {
                        let stats = try await repository.fetchLeaderboard(
                            metric: metric,
                            timeFrame: selectedTimeFrame,
                            limit: previewLimit,
                            preferredWorkoutMetric: preferredMetric,
                            source: mode == .fast ? .default : .server
                        )
                        return (metric, stats, false)
                    } catch {
                        if mode == .refresh {
                            do {
                                let cachedStats = try await repository.fetchLeaderboard(
                                    metric: metric,
                                    timeFrame: selectedTimeFrame,
                                    limit: previewLimit,
                                    preferredWorkoutMetric: preferredMetric,
                                    source: .cache
                                )
                                return (metric, cachedStats, false)
                            } catch {
                                // Fall through to failed metric accounting.
                            }
                        }

                        return (metric, nil, true)
                    }
                }
            }

            var results: [(LeaderboardMetric, [FirestoreLeaderboardStats]?, Bool)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        for (metric, stats, didFail) in metricResults {
            if let stats {
                fetchedEntries[metric] = makePreviewEntries(from: stats, metric: metric, userId: userId)
            } else {
                fetchedEntries[metric] = []
            }

            if didFail {
                failedMetrics += 1
            }
        }

        guard activeLoadID == loadID else { return }
        previewEntries = fetchedEntries
        if failedMetrics == LeaderboardMetric.allCases.count {
            errorMessage = "Couldn’t load leaderboard previews right now."
        }
    }

    private func makePreviewEntries(
        from stats: [FirestoreLeaderboardStats],
        metric: LeaderboardMetric,
        userId: String
    ) -> [LeaderboardEntry] {
        stats.enumerated().map { index, stat in
            let value = stat.value(for: metric, preferredWorkoutMetric: preferredMetric)
            return LeaderboardEntry(
                userId: stat.userId,
                displayName: stat.displayName,
                photoURL: stat.photoURL.flatMap { URL(string: $0) },
                rank: index + 1,
                value: value,
                formattedValue: formatValue(value, for: metric),
                isCurrentUser: stat.userId == userId
            )
        }
    }

    private func formatValue(_ value: Double, for metric: LeaderboardMetric) -> String {
        switch metric {
        case .climb, .workouts:
            return value.formatted(.number.precision(.fractionLength(0)))
        case .duration:
            let totalSeconds = Int(value.rounded())
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(minutes)m"
        case .pace:
            return value.formatted(.number.precision(.fractionLength(1)))
        }
    }

    private let hubTimeFrames: [LeaderboardTimeFrame] = [.weekly, .monthly, .allTime]

    private var hubHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Leaderboards")
                .font(.montserratBold(size: 34))
                .foregroundStyle(.primary)

            LeaderboardPickerView(
                selectedTimeFrame: $selectedTimeFrame,
                timeFrames: hubTimeFrames
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var globalEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)

            Text("No leaderboard data yet")
                .font(.montserratSemiBold(size: 20))
                .foregroundStyle(.primary)

            Text("Complete a workout and pull to refresh to populate weekly standings.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private var loadingState: some View {
        VStack(spacing: 0) {
            Text("Loading leaderboard…")
                .font(.montserratSemiBold(size: 18))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private func globalErrorState(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }
}

private struct LeaderboardCategoryCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let metric: LeaderboardMetric
    let entries: [LeaderboardEntry]
    let preferredMetric: WorkoutMetric
    let selectedTimeFrame: LeaderboardTimeFrame

    private var title: String {
        metric.displayName(for: preferredMetric)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(title)
                    .font(.montserratSemiBold(size: 18))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                Spacer()

                NavigationLink {
                    LeaderboardView(lockedMetric: metric, initialTimeFrame: selectedTimeFrame)
                } label: {
                    Text("See all")
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                }
            }

            if !entries.isEmpty {
                VStack(spacing: 10) {
                    ForEach(entries) { entry in
                        LeaderboardCategoryRow(
                            entry: entry,
                            metric: metric,
                            preferredMetric: preferredMetric
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.vertical, 4)
    }
}

private struct LeaderboardCategoryRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: LeaderboardEntry
    let metric: LeaderboardMetric
    let preferredMetric: WorkoutMetric

    private var unitLabel: String {
        metric.unit(for: preferredMetric)
    }

    private var medalRingGradient: AngularGradient? {
        switch entry.rank {
        case 1:
            return AngularGradient(
                colors: [
                    Color(red: 1.0, green: 0.94, blue: 0.62),
                    Color(red: 0.95, green: 0.76, blue: 0.24),
                    Color(red: 0.68, green: 0.50, blue: 0.09),
                    Color(red: 1.0, green: 0.94, blue: 0.62)
                ],
                center: .center
            )
        case 2:
            return AngularGradient(
                colors: [
                    Color(red: 0.98, green: 0.99, blue: 1.0),
                    Color(red: 0.74, green: 0.78, blue: 0.86),
                    Color(red: 0.55, green: 0.60, blue: 0.68),
                    Color(red: 0.98, green: 0.99, blue: 1.0)
                ],
                center: .center
            )
        case 3:
            return AngularGradient(
                colors: [
                    Color(red: 0.93, green: 0.71, blue: 0.48),
                    Color(red: 0.72, green: 0.45, blue: 0.24),
                    Color(red: 0.49, green: 0.30, blue: 0.16),
                    Color(red: 0.93, green: 0.71, blue: 0.48)
                ],
                center: .center
            )
        default:
            return nil
        }
    }

    private var medalRingGlow: Color {
        switch entry.rank {
        case 1:
            return Color(red: 0.96, green: 0.78, blue: 0.25)
        case 2:
            return Color(red: 0.79, green: 0.83, blue: 0.92)
        case 3:
            return Color(red: 0.79, green: 0.50, blue: 0.28)
        default:
            return .clear
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.montserratBold(size: 16))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                .frame(width: 18, alignment: .leading)

            avatar
                .frame(width: 46, height: 46)

            Text(entry.displayName)
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(entry.isCurrentUser ? .accent : (colorScheme == .dark ? .white : .black))
                .lineLimit(1)

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(entry.formattedValue)
                    .font(.montserratBold(size: 17))
                    .foregroundStyle(entry.isCurrentUser ? .accent : (colorScheme == .dark ? .white : .black))

                if !unitLabel.isEmpty {
                    Text(unitLabel)
                        .font(.montserratRegular(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.gray.opacity(0.06))
        )
    }

    @ViewBuilder
    private var avatar: some View {
        let ringGradient = medalRingGradient

        if let photoURL = entry.photoURL {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .clipShape(.circle)
                default:
                    placeholderAvatar
                }
            }
            .ifLet(ringGradient) { view, gradient in
                view
                    .overlay(
                        Circle()
                            .stroke(gradient, lineWidth: 3)
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                AngularGradient(
                                    colors: [
                                        .white.opacity(0.5),
                                        .clear,
                                        .white.opacity(0.28),
                                        .clear,
                                        .white.opacity(0.5)
                                    ],
                                    center: .center
                                ),
                                lineWidth: 1.2
                            )
                            .padding(1.5)
                    }
                    .shadow(color: medalRingGlow.opacity(colorScheme == .dark ? 0.54 : 0.3), radius: 8, x: 0, y: 2)
            }
            .id(photoURL)
        } else {
            placeholderAvatar
                .ifLet(ringGradient) { view, gradient in
                    view
                        .overlay(
                            Circle()
                                .stroke(gradient, lineWidth: 3)
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    AngularGradient(
                                        colors: [
                                            .white.opacity(0.5),
                                            .clear,
                                            .white.opacity(0.28),
                                            .clear,
                                            .white.opacity(0.5)
                                        ],
                                        center: .center
                                    ),
                                    lineWidth: 1.2
                                )
                                .padding(1.5)
                        }
                        .shadow(color: medalRingGlow.opacity(colorScheme == .dark ? 0.54 : 0.3), radius: 8, x: 0, y: 2)
                }
        }
    }

    private var placeholderAvatar: some View {
        Circle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.gray.opacity(0.22))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.65) : .gray)
            )
    }
}

private extension View {
    @ViewBuilder
    func ifLet<T, Content: View>(_ value: T?, transform: (Self, T) -> Content) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

#Preview {
    NavigationStack {
        LeaderboardHubView()
            .environment(AuthenticationViewModel())
            .environment(TabRouter())
    }
}
