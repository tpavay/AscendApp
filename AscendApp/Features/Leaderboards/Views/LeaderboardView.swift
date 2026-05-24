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
    @Environment(NetworkConnectivityService.self) private var connectivityService

    @State private var viewModel: LeaderboardViewModel
    @State private var scrollResetTrigger = 0

    private let lockedMetric: LeaderboardMetric?
    private let selectableTimeFrames: [LeaderboardTimeFrame] = [.daily, .weekly, .monthly, .yearly, .allTime]

    private enum ScrollTarget: Hashable {
        case top
    }

    @MainActor
    init(lockedMetric: LeaderboardMetric? = nil, initialTimeFrame: LeaderboardTimeFrame = .weekly) {
        self.lockedMetric = lockedMetric

        let vm = LeaderboardViewModel()
        if let lockedMetric {
            vm.selectedMetric = lockedMetric
        }
        vm.selectedTimeFrame = initialTimeFrame
        _viewModel = State(initialValue: vm)
    }

    private var metricTitle: String {
        viewModel.selectedMetric.displayName
    }

    private var isLockedMetricView: Bool {
        lockedMetric != nil
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Color.clear
                            .frame(height: 0)
                            .id(ScrollTarget.top)

                        header
                            .padding(.top, 18)
                            .padding(.bottom, 16)

                        if let error = viewModel.errorMessage, viewModel.hasCachedEntries {
                            StatusBannerView(
                                message: error,
                                style: .warning
                            )
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                        }

                        contentSection
                    }
                    .padding(.bottom, 124)
                }
                .refreshable {
                    await refreshData()
                }
                .onChange(of: scrollResetTrigger) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(ScrollTarget.top, anchor: .top)
                    }
                }
            }

            if shouldShowBlockingLoader {
                blockingLoader
                    .allowsHitTesting(false)
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isLockedMetricView)
        .toolbar(.hidden, for: .navigationBar)
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
        .onChange(of: authVM.displayName) { _, _ in
            syncCurrentUserEntry()
        }
        .onChange(of: authVM.displayPhotoURL) { _, _ in
            syncCurrentUserEntry()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if isLockedMetricView {
                    OnboardingBackButton {
                        HapticsManager.shared.trigger(.lightImpact)
                        dismiss()
                    }
                }

                if isLockedMetricView {
                    titleLabel
                } else {
                    metricTitleMenu
                }

                Spacer(minLength: 10)
            }

            timeFrameFilters
        }
        .padding(.horizontal, 20)
    }

    private var titleLabel: some View {
        metricTitleText(metricTitle)
    }

    private func metricTitleText(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.montserratBold(size: 34))
            .foregroundStyle(primaryTextColor)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var metricTitleMenu: some View {
        Menu {
            metricMenuOptions
        } label: {
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    ForEach(LeaderboardMetric.allCases) { metric in
                        metricTitleText(metric.displayName)
                            .hidden()
                    }

                    titleLabel
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(primaryTextColor.opacity(0.82))
                    .padding(.top, 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var metricMenuOptions: some View {
        ForEach(LeaderboardMetric.allCases) { metric in
            Button {
                guard viewModel.selectedMetric != metric else { return }
                HapticsManager.shared.trigger(.selection)
                viewModel.selectedMetric = metric
            } label: {
                Label(
                    metric.displayName,
                    systemImage: metric.icon
                )
            }
        }
    }

    private var timeFrameFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(selectableTimeFrames) { timeFrame in
                    let isSelected = viewModel.selectedTimeFrame == timeFrame
                    Button {
                        guard viewModel.selectedTimeFrame != timeFrame else { return }
                        HapticsManager.shared.trigger(.selection)
                        viewModel.selectedTimeFrame = timeFrame
                    } label: {
                        Text(timeFrame.displayName.uppercased())
                            .font(.montserratBold(size: 10))
                            .foregroundStyle(isSelected ? .accent : primaryTextColor.opacity(0.74))
                            .lineLimit(1)
                            .padding(.horizontal, 13)
                            .frame(height: 30)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.accent.opacity(0.09) : Color.clear)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        isSelected
                                            ? Color.accent
                                            : (colorScheme == .dark ? .white.opacity(0.16) : .black.opacity(0.14)),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
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

    // MARK: - Leaderboard Content

    private struct LeaderboardPresentationState {
        let podiumEntries: [LeaderboardEntry]
        let pinnedUserEntry: LeaderboardEntry?
        let listEntries: [LeaderboardEntry]
    }

    private func leaderboardContent(entries: [LeaderboardEntry]) -> some View {
        let state = presentationState(for: entries)

        return VStack(spacing: 16) {
            if !state.podiumEntries.isEmpty {
                LeaderboardPodiumView(
                    entries: state.podiumEntries,
                    metric: viewModel.selectedMetric,
                    usesContainerBackground: false
                )
                .padding(.horizontal, 20)
            }

            if let userEntry = state.pinnedUserEntry {
                LeaderboardUserRowView(
                    entry: userEntry,
                    metric: viewModel.selectedMetric
                )
                .padding(.top, 2)
            }

            if !state.listEntries.isEmpty {
                LeaderboardRowListView(
                    entries: state.listEntries,
                    metric: viewModel.selectedMetric,
                    onEntryAppear: { entry in
                        viewModel.loadMoreEntriesIfNeeded(currentEntry: entry)
                    }
                )
                .padding(.top, 2)
            } else if entries.count == 1, let entry = entries.first, entry.isCurrentUser {
                Text("You own this board. Keep it there.")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(primaryTextColor.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                    .padding(.horizontal, 40)
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

        if shouldPinUserRow(userEntry) {
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
        entry.rank > 3
    }

    private var shouldShowBlockingLoader: Bool {
        viewModel.displayedEntries.isEmpty && viewModel.isLoading
    }

    private var blockingLoader: some View {
        ZStack {
            backgroundColor.opacity(colorScheme == .dark ? 0.72 : 0.58)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.accent)

                Text("Loading leaderboard...")
                    .font(.montserratSemiBold(size: 15))
                    .foregroundStyle(primaryTextColor)
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorScheme == .dark ? Color.jet : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08), lineWidth: 1)
            )
        }
    }

    // MARK: - Empty and Error States

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.red)

            Text("Leaderboard stalled.")
                .font(.montserratBold(size: 20))
                .foregroundStyle(primaryTextColor)

            Text(message)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 42)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.accent)

            Text("No entries yet.")
                .font(.montserratBold(size: 20))
                .foregroundStyle(primaryTextColor)

            Text("Take the first spot.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(primaryTextColor.opacity(0.66))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 20)
    }

    private var offlineEmptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.orange)

            Text("You're offline.")
                .font(.montserratBold(size: 20))
                .foregroundStyle(primaryTextColor)

            Text("Pull to retry when the connection is back.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(primaryTextColor.opacity(0.66))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 20)
    }

    // MARK: - Data Loading

    private func setupAndLoad() async {
        guard let userId = authVM.user?.uid else { return }
        if let lockedMetric {
            viewModel.selectedMetric = lockedMetric
        }
        viewModel.configure(userId: userId, modelContext: modelContext)
        await loadData()
    }

    private func loadData() async {
        guard let userId = authVM.user?.uid else { return }
        await viewModel.loadLeaderboard(
            userId: userId,
            isNetworkConnected: connectivityService.isConnected
        )
    }

    private func refreshData() async {
        guard let userId = authVM.user?.uid else { return }
        await viewModel.refreshLeaderboard(
            userId: userId,
            displayName: authVM.displayName,
            photoURL: authVM.displayPhotoURL,
            isNetworkConnected: connectivityService.isConnected
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
            .environment(NetworkConnectivityService.shared)
            .environment(TabRouter())
    }
    .modelContainer(for: [Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self], inMemory: true)
}
