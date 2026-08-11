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
    @Environment(ModerationStore.self) private var moderationStore

    @State private var viewModel: LeaderboardViewModel
    @State private var scrollResetTrigger = 0

    private let lockedMetric: LeaderboardMetric?
    private let selectableTimeFrames: [LeaderboardTimeFrame] = [.weekly, .monthly, .yearly, .allTime]

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
        .onChange(of: viewModel.selectedAgeGroup) { _, _ in
            demographicFilterChanged()
        }
        .onChange(of: viewModel.selectedBodyWeightFilter) { _, _ in
            demographicFilterChanged()
        }
        .onChange(of: viewModel.selectedLocationFilter) { _, _ in
            demographicFilterChanged()
        }
        .onChange(of: authVM.displayPhotoURL) { _, _ in
            syncCurrentUserEntry()
        }
        .onChange(of: authVM.displayName) { _, _ in
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

            periodWindowLabel

            demographicFilters
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

    /// Names the window the selected board covers.
    ///
    /// Weekly and monthly windows do not nest - the week of Jul 27 2026 runs into Aug 2 -
    /// so on the 1st a populated weekly board and an empty monthly board are both correct.
    /// Unlabelled, that pair reads as data loss. Labelled, it reads as a calendar.
    private var periodWindowLabel: some View {
        Text(viewModel.selectedPeriod.windowLabel.uppercased())
            .font(.montserratSemiBold(size: 10))
            .foregroundStyle(primaryTextColor.opacity(0.52))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityLabel("Showing \(viewModel.selectedPeriod.windowLabel)")
    }

    private var demographicFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ageFilterMenu
                bodyWeightFilterMenu
                locationFilterMenu

                if viewModel.hasActiveDemographicFilters {
                    Button {
                        HapticsManager.shared.trigger(.selection)
                        viewModel.clearDemographicFilters()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(primaryTextColor.opacity(0.72))
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear leaderboard filters")
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }

    private var ageFilterMenu: some View {
        Menu {
            Button {
                guard viewModel.selectedAgeGroup != nil else { return }
                HapticsManager.shared.trigger(.selection)
                viewModel.selectAgeGroup(nil)
            } label: {
                if viewModel.selectedAgeGroup == nil {
                    Label("All ages", systemImage: "checkmark")
                } else {
                    Text("All ages")
                }
            }

            ForEach(LeaderboardAgeGroup.allCases) { ageGroup in
                Button {
                    guard viewModel.selectedAgeGroup != ageGroup else { return }
                    HapticsManager.shared.trigger(.selection)
                    viewModel.selectAgeGroup(ageGroup)
                } label: {
                    if viewModel.selectedAgeGroup == ageGroup {
                        Label(ageGroup.displayName, systemImage: "checkmark")
                    } else {
                        Text(ageGroup.displayName)
                    }
                }
            }
        } label: {
            demographicFilterChip(
                title: viewModel.ageFilterTitle,
                isActive: viewModel.selectedAgeGroup != nil
            )
        }
        .buttonStyle(.plain)
    }

    private var bodyWeightFilterMenu: some View {
        Menu {
            ForEach(LeaderboardBodyWeightFilter.allCases) { filter in
                Button {
                    guard viewModel.selectedBodyWeightFilter != filter else { return }
                    HapticsManager.shared.trigger(.selection)
                    viewModel.selectBodyWeightFilter(filter)
                } label: {
                    if viewModel.selectedBodyWeightFilter == filter {
                        Label(filter.displayName, systemImage: "checkmark")
                    } else {
                        Text(filter.displayName)
                    }
                }
            }
        } label: {
            demographicFilterChip(
                title: viewModel.bodyWeightFilterTitle,
                isActive: viewModel.selectedBodyWeightFilter != .all
            )
        }
        .buttonStyle(.plain)
    }

    private var locationFilterMenu: some View {
        Menu {
            ForEach(viewModel.currentLocationFilterOptions) { filter in
                Button {
                    guard viewModel.selectedLocationFilter != filter else { return }
                    HapticsManager.shared.trigger(.selection)
                    viewModel.selectLocationFilter(filter)
                } label: {
                    let title = filter.displayName(currentUserProfile: viewModel.currentUserLocationProfile)
                    if viewModel.selectedLocationFilter == filter {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        } label: {
            demographicFilterChip(
                title: viewModel.locationFilterTitle,
                isActive: viewModel.selectedLocationFilter != .all
            )
        }
        .buttonStyle(.plain)
    }

    private func demographicFilterChip(title: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.montserratBold(size: 10))
                .foregroundStyle(isActive ? .accent : primaryTextColor.opacity(0.74))
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isActive ? .accent : primaryTextColor.opacity(0.54))
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(
            Capsule()
                .fill(isActive ? Color.accent.opacity(0.09) : Color.clear)
        )
        .overlay(
            Capsule()
                .stroke(
                    isActive
                        ? Color.accent
                        : (colorScheme == .dark ? .white.opacity(0.16) : .black.opacity(0.14)),
                    lineWidth: 1
                )
        )
        .contentShape(Capsule())
    }

    @ViewBuilder
    private var contentSection: some View {
        let entries = moderationStore.moderate(viewModel.displayedEntries)
        let standing = viewModel.userStanding

        if entries.isEmpty {
            if !viewModel.isLoading {
                if viewModel.isOffline {
                    offlineEmptyStateView
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else if viewModel.hasActiveDemographicFilters {
                    filteredEmptyStateView
                } else {
                    emptyStateView
                }
            }
        } else {
            leaderboardContent(entries: entries, standing: standing)
        }
    }

    // MARK: - Leaderboard Content

    private struct LeaderboardPresentationState {
        /// The climber's own row, pinned under the podium. `nil` when they already stand on
        /// the podium and must not be shown twice.
        enum PinnedRow {
            case ranked(ModeratedLeaderboardEntry)
            /// No rank this period, so the row renders without one rather than borrowing
            /// its list position. It still carries the climber's value, because the chase
            /// line under the row is measured from it.
            case unranked(value: Double, formattedValue: String)
        }

        let podiumEntries: [ModeratedLeaderboardEntry]
        let pinnedRow: PinnedRow?
        let listEntries: [ModeratedLeaderboardEntry]
    }

    private func leaderboardContent(
        entries: [ModeratedLeaderboardEntry],
        standing: LeaderboardUserStanding?
    ) -> some View {
        let state = presentationState(for: entries, standing: standing)

        return VStack(spacing: 16) {
            if !state.podiumEntries.isEmpty {
                LeaderboardPodiumView(
                    entries: state.podiumEntries,
                    metric: viewModel.selectedMetric,
                    usesContainerBackground: false
                )
                .padding(.horizontal, 20)
            }

            switch state.pinnedRow {
            case .none:
                EmptyView()

            case .ranked(let userEntry):
                LeaderboardUserRowView(
                    entry: userEntry,
                    metric: viewModel.selectedMetric,
                    crownGapText: crownGapText(
                        value: userEntry.value,
                        userId: userEntry.userId,
                        podiumEntries: state.podiumEntries
                    )
                )
                .padding(.top, 2)

            case .unranked(let value, let formattedValue):
                LeaderboardUserRowView(
                    unrankedFormattedValue: formattedValue,
                    displayName: currentUserDisplayName,
                    photoURL: authVM.displayPhotoURL,
                    metric: viewModel.selectedMetric,
                    crownGapText: crownGapText(
                        value: value,
                        userId: nil,
                        podiumEntries: state.podiumEntries
                    )
                )
                .padding(.top, 2)
            }

            if !state.listEntries.isEmpty {
                LeaderboardRowListView(
                    entries: state.listEntries,
                    metric: viewModel.selectedMetric,
                    onEntryAppear: { entry in
                        viewModel.loadMoreEntriesIfNeeded(currentEntryID: entry.id)
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

    private func presentationState(
        for entries: [ModeratedLeaderboardEntry],
        standing: LeaderboardUserStanding?
    ) -> LeaderboardPresentationState {
        let podiumEntries = ModeratedLeaderboardPodiumLayout.podiumEntries(from: entries)
        let listEntries = ModeratedLeaderboardPodiumLayout.listEntries(from: entries)

        switch standing {
        case .none:
            return LeaderboardPresentationState(
                podiumEntries: podiumEntries,
                pinnedRow: nil,
                listEntries: listEntries
            )

        case .unranked(let value, let formattedValue):
            // An unranked climber is in no entry list, so there is nothing to dedupe.
            return LeaderboardPresentationState(
                podiumEntries: podiumEntries,
                pinnedRow: .unranked(value: value, formattedValue: formattedValue),
                listEntries: listEntries
            )

        case .ranked(let entry):
            let userEntry = moderationStore.moderate(entry)
            guard shouldPinUserRow(userEntry, podiumEntries: podiumEntries) else {
                return LeaderboardPresentationState(
                    podiumEntries: podiumEntries,
                    pinnedRow: nil,
                    listEntries: listEntries
                )
            }

            return LeaderboardPresentationState(
                podiumEntries: podiumEntries,
                pinnedRow: .ranked(userEntry),
                listEntries: listEntries.filter { $0.userId != userEntry.userId }
            )
        }
    }

    private func shouldPinUserRow(
        _ entry: ModeratedLeaderboardEntry,
        podiumEntries: [ModeratedLeaderboardEntry]
    ) -> Bool {
        !podiumEntries.contains { $0.userId == entry.userId }
    }

    /// The chase line under the pinned row. An unranked climber passes `userId: nil` -
    /// they are on no rung, so no podium row can be theirs.
    private func crownGapText(
        value: Double,
        userId: String?,
        podiumEntries: [ModeratedLeaderboardEntry]
    ) -> String? {
        guard let leader = podiumEntries.first(where: { $0.rank == 1 }),
              leader.userId != userId
        else {
            return nil
        }

        let gap = leader.value - value
        guard gap > 0 else { return nil }

        return "\(formattedCrownGap(gap, for: viewModel.selectedMetric)) TO CROWN"
    }

    private func formattedCrownGap(_ gap: Double, for metric: LeaderboardMetric) -> String {
        switch metric {
        case .climb:
            return "\(Int(gap.rounded(.up)).formatted(.number.grouping(.automatic))) STEPS"
        case .workouts:
            return "\(Int(gap.rounded(.up)).formatted(.number.grouping(.automatic))) WORKOUTS"
        case .duration:
            return formattedDurationGap(gap)
        case .pace:
            return "\(gap.formatted(.number.precision(.fractionLength(1)))) SPM"
        }
    }

    private func formattedDurationGap(_ gap: Double) -> String {
        let totalSeconds = Int(gap.rounded(.up))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(twoDigit(minutes)):\(twoDigit(seconds))"
        }

        return "\(minutes):\(twoDigit(seconds))"
    }

    private func twoDigit(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
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
        LeaderboardEmptyBoardView(
            period: viewModel.selectedPeriod,
            metric: viewModel.selectedMetric
        )
    }

    private var filteredEmptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.accent)

            VStack(spacing: 5) {
                Text(viewModel.filteredEmptyStateTitle)
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(primaryTextColor)

                Text(viewModel.filteredEmptyStateMessage)
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(primaryTextColor.opacity(0.66))
                    .multilineTextAlignment(.center)
            }

            Button {
                HapticsManager.shared.trigger(.selection)
                viewModel.clearDemographicFilters()
            } label: {
                Text("Clear Filters")
                    .font(.montserratBold(size: 13))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .frame(height: 34)
                    .background(Capsule().fill(Color.accent))
            }
            .buttonStyle(.plain)
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
        viewModel.configure(
            userId: userId,
            displayName: currentUserNameOverride,
            modelContext: modelContext
        )
        await loadData()
        syncCurrentUserEntry()
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
            isNetworkConnected: connectivityService.isConnected
        )
    }

    private func resetScrollPosition() {
        scrollResetTrigger &+= 1
    }

    private func demographicFilterChanged() {
        resetScrollPosition()
        Task { await loadData() }
    }

    private func syncCurrentUserEntry() {
        viewModel.updateCurrentUserProfile(
            userId: authVM.user?.uid,
            displayName: currentUserNameOverride,
            photoURL: authVM.displayPhotoURL
        )
    }

    /// Nil until the account actually has a name. A fresh device reaches
    /// `.authenticated` before the profile fetch lands, and an empty override
    /// would replace the climber's published board name with a system handle.
    private var currentUserNameOverride: String? {
        let trimmed = authVM.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var currentUserDisplayName: String {
        currentUserNameOverride ?? PublicClimberIdentity.systemHandle(for: authVM.user?.uid)
    }
}

#Preview {
    NavigationStack {
        LeaderboardView()
            .environment(AuthenticationViewModel())
            .environment(ModerationStore.shared)
            .environment(NetworkConnectivityService.shared)
            .environment(TabRouter())
    }
    .modelContainer(for: [Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self], inMemory: true)
}
