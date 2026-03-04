//
//  LeaderboardHubView.swift
//  AscendApp
//

import SwiftUI

struct LeaderboardHubView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @State private var settingsManager = SettingsManager.shared

    @State private var previewEntries: [LeaderboardMetric: [LeaderboardEntry]] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let repository = LeaderboardRepository.shared
    private let previewLimit = 3

    private var preferredMetric: WorkoutMetric {
        settingsManager.preferredWorkoutMetric
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(LeaderboardMetric.allCases) { metric in
                    LeaderboardCategoryCard(
                        metric: metric,
                        entries: previewEntries[metric] ?? [],
                        preferredMetric: preferredMetric,
                        isLoading: isLoading,
                        errorMessage: errorMessage
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .themedBackground()
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadPreviews()
        }
        .refreshable {
            await loadPreviews()
        }
    }

    private func loadPreviews() async {
        guard let userId = authVM.user?.uid else { return }

        isLoading = true
        errorMessage = nil

        var fetchedEntries: [LeaderboardMetric: [LeaderboardEntry]] = [:]
        var failedMetrics = 0

        for metric in LeaderboardMetric.allCases {
            do {
                let stats = try await repository.fetchLeaderboard(
                    metric: metric,
                    timeFrame: .weekly,
                    limit: previewLimit,
                    preferredWorkoutMetric: preferredMetric
                )

                let entries = stats.enumerated().map { index, stat in
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

                fetchedEntries[metric] = entries
            } catch {
                failedMetrics += 1
                fetchedEntries[metric] = []
            }
        }

        previewEntries = fetchedEntries
        if failedMetrics == LeaderboardMetric.allCases.count {
            errorMessage = "Couldn’t load leaderboard previews right now."
        }
        isLoading = false
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
}

private struct LeaderboardCategoryCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let metric: LeaderboardMetric
    let entries: [LeaderboardEntry]
    let preferredMetric: WorkoutMetric
    let isLoading: Bool
    let errorMessage: String?

    private var title: String {
        metric.displayName(for: preferredMetric)
    }

    private var subtitle: String {
        "Weekly standings"
    }

    private var emptyStateText: String {
        if let errorMessage {
            return errorMessage
        }
        if isLoading {
            return "Loading..."
        }
        return "No data yet"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.montserratSemiBold(size: 18))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    Text(subtitle)
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    LeaderboardView(lockedMetric: metric)
                } label: {
                    Text("See all")
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(.accent)
                }
            }

            if entries.isEmpty {
                Text(emptyStateText)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
            } else {
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
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .padding(.vertical, 8)
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

    var body: some View {
        HStack(spacing: 10) {
            Text("\(entry.rank)")
                .font(.montserratBold(size: 13))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                .frame(width: 14, alignment: .leading)

            avatar
                .frame(width: 40, height: 40)

            Text(entry.displayName)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(entry.isCurrentUser ? .accent : (colorScheme == .dark ? .white : .black))
                .lineLimit(1)

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(entry.formattedValue)
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(entry.isCurrentUser ? .accent : (colorScheme == .dark ? .white : .black))

                if !unitLabel.isEmpty {
                    Text(unitLabel)
                        .font(.montserratRegular(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.gray.opacity(0.06))
        )
    }

    @ViewBuilder
    private var avatar: some View {
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
            .id(photoURL)
        } else {
            placeholderAvatar
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

#Preview {
    NavigationStack {
        LeaderboardHubView()
            .environment(AuthenticationViewModel())
    }
}
