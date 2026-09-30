import SwiftData
import SwiftUI

struct OtherUserProfileView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ModerationStore.self) private var moderationStore
    @Query(sort: \Workout.date, order: .reverse) private var viewerWorkouts: [Workout]
    @Query(sort: \ClimbAttempt.startedAt, order: .reverse) private var viewerClimbAttempts: [ClimbAttempt]
    @Query(sort: \BestEffortCacheEntry.sortKey) private var viewerBestEffortCacheEntries: [BestEffortCacheEntry]

    @State private var viewModel = ProfileScreenViewModel()
    @State private var settingsManager = SettingsManager.shared
    @State private var catalogRevision = 0
    @State private var selectedTab: ProfileComparisonTab = .bio

    let initialIdentity: ResolvedUserIdentity
    let moderationSource: ModerationSource

    init(
        identity: ResolvedUserIdentity,
        moderationSource: ModerationSource = .profile
    ) {
        self.initialIdentity = identity
        self.moderationSource = moderationSource
    }

    private var userId: String {
        initialIdentity.userId ?? ""
    }

    private var climbs: [Climb] {
        _ = catalogRevision
        return (try? ClimbService.shared.loadAllClimbs()) ?? []
    }

    private var viewerDisplayName: String {
        let trimmed = authVM.displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty
            ? PublicClimberIdentity.systemHandle(for: authVM.user?.uid)
            : trimmed
    }

    private var viewerSnapshot: ProfileSnapshot {
        ProfileSnapshotBuilder.makeOwnSnapshot(
            demographics: viewModel.ownDemographics(
                userId: authVM.user?.uid ?? "viewer",
                displayName: viewerDisplayName,
                photoURL: authVM.displayPhotoURL,
                joinedAt: authVM.user?.metadata.creationDate
            ),
            workouts: viewerWorkouts,
            climbAttempts: viewerClimbAttempts,
            bestEffortCacheEntries: viewerBestEffortCacheEntries,
            achievements: viewModel.achievements,
            standings: viewModel.standings,
            climbs: climbs,
            fitnessLevel: settingsManager.fitnessLevel
        )
    }

    private var loadingSnapshot: ProfileSnapshot {
        ProfileSnapshotBuilder.makeRemoteSnapshot(
            demographics: viewModel.otherUserDemographics(userId: userId),
            stats: .empty,
            achievements: .empty,
            standings: [],
            workoutSummaries: [],
            firstAscentsHeld: [],
            openFirstAscents: [],
            climbs: climbs
        )
    }

    private var taskKey: String {
        let latestWorkout = viewerWorkouts.first?.lastModifiedAt.timeIntervalSince1970 ?? 0
        let latestAttempt = viewerClimbAttempts.first?.startedAt.timeIntervalSince1970 ?? 0
        return "\(userId)-\(viewerWorkouts.count)-\(viewerClimbAttempts.count)-\(latestWorkout)-\(latestAttempt)-\(catalogRevision)"
    }

    private var otherSnapshot: ProfileSnapshot {
        viewModel.otherUserSnapshot ?? loadingSnapshot
    }

    var body: some View {
        let viewer = viewerSnapshot
        let other = otherSnapshot
        let isInitialRemoteLoad = viewModel.otherUserSnapshot == nil
        let isInitialViewerIdentityLoad =
            authVM.user != nil && !viewModel.hasLoadedOwnIdentity
        let comparison = viewModel.comparison ?? ProfileSnapshotBuilder.comparison(viewer: viewer, otherUser: other)
        let headToHeadResults = ProfileSnapshotBuilder.headToHeadResults(
            viewer: viewer,
            otherUser: other,
            climbs: climbs
        )

        ScrollView {
            ProfileComparisonContent(
                viewerIdentity: viewModel.resolvedOwnIdentity(
                    using: moderationStore,
                    userId: authVM.user?.uid ?? "viewer",
                    displayName: viewerDisplayName,
                    photoURL: authVM.displayPhotoURL,
                    joinedAt: authVM.user?.metadata.creationDate
                ),
                otherIdentity: viewModel.resolvedOtherIdentity(
                    using: moderationStore,
                    fallback: initialIdentity
                ),
                viewer: viewer,
                otherUser: other,
                comparison: comparison,
                headToHeadResults: headToHeadResults,
                measurementSystem: settingsManager.measurementSystem,
                isViewerLoading: isInitialViewerIdentityLoad,
                isOtherLoading: isInitialRemoteLoad,
                selectedTab: $selectedTab
            )
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            ProfileComparisonTopBar(
                reportedUserId: userId,
                moderationSource: moderationSource
            ) {
                HapticsManager.shared.trigger(.lightImpact)
                dismiss()
            }
        }
        .background(ProfileVisualStyle.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: taskKey) {
            if let user = authVM.user {
                await viewModel.loadOwnSupport(
                    userId: user.uid,
                    displayName: authVM.displayName,
                    photoURL: authVM.displayPhotoURL,
                    joinedAt: user.metadata.creationDate,
                    climbs: climbs,
                    modelContext: modelContext,
                    taskKey: "comparison-own-\(taskKey)"
                )
            }

            await viewModel.loadOtherUser(
                userId: userId,
                initialIdentity: initialIdentity,
                viewerSnapshot: viewerSnapshot,
                climbs: climbs,
                taskKey: taskKey
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbCatalogDidChange)) { _ in
            catalogRevision += 1
        }
        .trackOnce(screen: .otherUserProfile)
    }

}

/// Everything the comparison scrolls: both climbers, the tab picker, and the selected tab.
/// Split from `OtherUserProfileView` so it renders from two snapshots alone, with no account,
/// store, or network behind it - which is how the evidence suite photographs the real layout.
struct ProfileComparisonContent: View {
    let viewerIdentity: ResolvedUserIdentity
    let otherIdentity: ResolvedUserIdentity
    let viewer: ProfileSnapshot
    let otherUser: ProfileSnapshot
    let comparison: ProfileComparisonSummary
    let headToHeadResults: [ProfileHeadToHeadClimbResult]
    let measurementSystem: MeasurementSystem
    let isViewerLoading: Bool
    let isOtherLoading: Bool
    @Binding var selectedTab: ProfileComparisonTab

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ProfileComparisonHeader(
                viewerIdentity: viewerIdentity,
                otherIdentity: otherIdentity,
                isViewerLoading: isViewerLoading,
                isOtherLoading: isOtherLoading
            )

            ProfileComparisonTabPicker(selection: $selectedTab)
                .padding(.top, 20)

            Group {
                switch selectedTab {
                case .bio:
                    ProfileComparisonBioTab(
                        viewer: viewer,
                        otherUser: otherUser,
                        measurementSystem: measurementSystem,
                        isViewerLoading: isViewerLoading,
                        isOtherLoading: isOtherLoading
                    )
                case .headToHead:
                    ProfileComparisonHeadToHeadTab(
                        comparison: comparison,
                        results: headToHeadResults,
                        isLoading: isOtherLoading
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 118)
        }
    }
}

enum ProfileComparisonTab: String, CaseIterable, Identifiable {
    case bio = "Bio"
    case headToHead = "Head-to-head"

    var id: String { rawValue }
}

private struct ProfileComparisonTopBar: View {
    let reportedUserId: String
    let moderationSource: ModerationSource
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.13))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer()

            Text("PROFILE COMPARISON")
                .font(.montserratBold(size: 13))
                .foregroundStyle(ProfileVisualStyle.secondaryText)
                .tracking(3.2)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer()

            ProfileModerationMenu(
                reportedUserId: reportedUserId,
                source: moderationSource
            )
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ProfileVisualStyle.secondaryText)
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .background(ProfileVisualStyle.background.opacity(0.96))
    }
}

struct ProfileComparisonHeader: View {
    @Environment(ChampionRegistry.self) private var championRegistry: ChampionRegistry?

    let viewerIdentity: ResolvedUserIdentity
    let otherIdentity: ResolvedUserIdentity
    let isViewerLoading: Bool
    let isOtherLoading: Bool

    var body: some View {
        // Top-aligned so a title line under one name never lifts that side's picture off
        // the other's; VS sits at the pictures' centre.
        HStack(alignment: .top, spacing: 18) {
            competitor(
                identity: viewerIdentity,
                tint: Color.ascendAccent,
                fallbackName: "Climber",
                isLoading: isViewerLoading
            )

            Text("VS")
                .font(.montserratBold(size: 18))
                .foregroundStyle(ProfileVisualStyle.tertiaryText)
                .frame(width: 46, height: 76)

            competitor(
                identity: otherIdentity,
                tint: ProfileVisualStyle.opponentBlue,
                fallbackName: "Climber",
                isLoading: isOtherLoading
            )
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
    }

    private func competitor(
        identity: ResolvedUserIdentity,
        tint: Color,
        fallbackName: String,
        isLoading: Bool
    ) -> some View {
        VStack(spacing: 12) {
            if isLoading {
                AscendSkeletonCircle(size: 76, tint: tint)
            } else {
                ClimberAvatar(
                    userId: identity.userId,
                    photoURL: identity.photoURL,
                    placeholder: .profileDefault,
                    size: 76,
                    border: .init(color: tint, width: 2)
                )
                .accessibilityHidden(true)
            }

            if isLoading {
                AscendSkeletonText(width: 78, height: 18)
            } else {
                VStack(spacing: 6) {
                    Text(resolvedName(identity.displayName, fallback: fallbackName))
                        .font(.montserratBold(size: 18))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    if let titleLine = titleLine(for: identity) {
                        Text(titleLine.text)
                            .font(.montserratBold(size: 10))
                            .tracking(1.4)
                            .foregroundStyle(titleLine.leadingTitle.tint)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The comparison names a champion's title under their name; the crown is on the picture.
    private func titleLine(for identity: ResolvedUserIdentity) -> ChampionTitleLine? {
        guard let championRegistry else { return nil }
        return ChampionTitleLine.make(
            titles: championRegistry.titles(for: identity.userId),
            reigns: championRegistry.reigns
        )
    }

    private func resolvedName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return trimmed
    }
}

private struct ProfileComparisonTabPicker: View {
    @Binding var selection: ProfileComparisonTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ProfileComparisonTab.allCases) { tab in
                Button {
                    HapticsManager.shared.trigger(.lightImpact)
                    selection = tab
                } label: {
                    VStack(spacing: 14) {
                        Text(tab.rawValue)
                            .font(.montserratBold(size: 14))
                            .foregroundStyle(selection == tab ? .white : ProfileVisualStyle.tertiaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Rectangle()
                            .fill(selection == tab ? Color.ascendAccent : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ProfileVisualStyle.cardStroke)
                .frame(height: 1)
        }
    }
}

private struct ProfileComparisonBioTab: View {
    let viewer: ProfileSnapshot
    let otherUser: ProfileSnapshot
    let measurementSystem: MeasurementSystem
    let isViewerLoading: Bool
    let isOtherLoading: Bool

    private var heartRateComparison: ProfileHeartRateComparison {
        ProfileHeartRateComparison(
            viewer: viewer.stats.heartRate,
            other: otherUser.stats.heartRate,
            isOtherLoading: isOtherLoading
        )
    }

    var body: some View {
        let heartRate = heartRateComparison
        VStack(alignment: .leading, spacing: 30) {
            ProfileComparisonSection(title: "PROFILE") {
                VStack(spacing: 0) {
                    comparisonInfoRow(
                        label: "Joined",
                        viewerValue: valueOrDash(ProfileIdentityFormatter.joinedMonthText(for: viewer.demographics.joinedAt)),
                        otherValue: valueOrDash(ProfileIdentityFormatter.joinedMonthText(for: otherUser.demographics.joinedAt)),
                        isViewerLoading: isViewerLoading,
                        isOtherLoading: isOtherLoading
                    )
                    comparisonInfoRow(
                        label: "Age",
                        viewerValue: valueOrDash(viewer.demographics.age.map { "\($0)" }),
                        otherValue: valueOrDash(otherUser.demographics.age.map { "\($0)" }),
                        isViewerLoading: isViewerLoading,
                        isOtherLoading: isOtherLoading
                    )
                    comparisonInfoRow(
                        label: "Height",
                        viewerValue: formatHeight(viewer.demographics.heightCm),
                        otherValue: formatHeight(otherUser.demographics.heightCm),
                        isViewerLoading: isViewerLoading,
                        isOtherLoading: isOtherLoading
                    )
                    comparisonInfoRow(
                        label: "Weight",
                        viewerValue: formatWeight(viewer.demographics.weightKg),
                        otherValue: formatWeight(otherUser.demographics.weightKg),
                        isViewerLoading: isViewerLoading,
                        isOtherLoading: isOtherLoading
                    )
                    comparisonInfoRow(
                        label: "Best streak",
                        viewerValue: formatStreak(viewer.stats.bestStreakWeeks),
                        otherValue: formatStreak(otherUser.stats.bestStreakWeeks),
                        isViewerLoading: false,
                        isOtherLoading: isOtherLoading,
                        showDivider: false
                    )
                }
            }

            ProfileComparisonSection(title: "ALL-TIME") {
                VStack(spacing: 0) {
                    ProfileComparisonStatRow(
                        label: "Steps",
                        viewerValueText: viewer.stats.lifetimeTotalSteps.formatted(.number.grouping(.automatic)),
                        otherValueText: otherUser.stats.lifetimeTotalSteps.formatted(.number.grouping(.automatic)),
                        viewerValue: Double(viewer.stats.lifetimeTotalSteps),
                        otherValue: Double(otherUser.stats.lifetimeTotalSteps),
                        isOtherLoading: isOtherLoading
                    )
                    ProfileComparisonStatRow(
                        label: "Climbs",
                        viewerValueText: viewer.stats.totalClimbs.formatted(.number.grouping(.automatic)),
                        otherValueText: otherUser.stats.totalClimbs.formatted(.number.grouping(.automatic)),
                        viewerValue: Double(viewer.stats.totalClimbs),
                        otherValue: Double(otherUser.stats.totalClimbs),
                        isOtherLoading: isOtherLoading
                    )
                    ProfileComparisonStatRow(
                        label: "Duration",
                        viewerValueText: ProfileDateFormatters.compactDuration(TimeInterval(viewer.stats.lifetimeDurationSeconds)),
                        otherValueText: ProfileDateFormatters.compactDuration(TimeInterval(otherUser.stats.lifetimeDurationSeconds)),
                        viewerValue: Double(viewer.stats.lifetimeDurationSeconds),
                        otherValue: Double(otherUser.stats.lifetimeDurationSeconds),
                        isOtherLoading: isOtherLoading
                    )
                    ProfileComparisonStatRow(
                        label: "Avg steps/climb",
                        viewerValueText: formatAverageSteps(viewer.stats.averageStepsPerClimb),
                        otherValueText: formatAverageSteps(otherUser.stats.averageStepsPerClimb),
                        viewerValue: viewer.stats.averageStepsPerClimb ?? 0,
                        otherValue: otherUser.stats.averageStepsPerClimb ?? 0,
                        isOtherLoading: isOtherLoading
                    )
                    ProfileComparisonStatRow(
                        label: "Avg climb time",
                        viewerValueText: formatAverageDuration(viewer.stats.averageClimbDurationSeconds),
                        otherValueText: formatAverageDuration(otherUser.stats.averageClimbDurationSeconds),
                        viewerValue: viewer.stats.averageClimbDurationSeconds ?? 0,
                        otherValue: otherUser.stats.averageClimbDurationSeconds ?? 0,
                        isOtherLoading: isOtherLoading
                    )
                    ProfileComparisonStatRow(
                        label: "Avg steps/min",
                        viewerValueText: formatSPM(viewer.stats.averageStepsPerMinute),
                        otherValueText: formatSPM(otherUser.stats.averageStepsPerMinute),
                        viewerValue: viewer.stats.averageStepsPerMinute,
                        otherValue: otherUser.stats.averageStepsPerMinute,
                        isOtherLoading: isOtherLoading,
                        showDivider: false
                    )
                }
            }

            // HEART RATE and ACHIEVEMENTS are the two sections whose height and existence vary
            // with the data, so they come last and PROFILE and ALL-TIME never move.
            if !heartRate.isEmpty {
                ProfileComparisonSection(title: "HEART RATE") {
                    VStack(spacing: 0) {
                        ForEach(heartRate.rows) { row in
                            // No bar: a higher heart rate is not a win, and a proportional bar
                            // would crown whoever's heart worked hardest.
                            comparisonInfoRow(
                                label: row.kind.label,
                                viewerValue: ProfileHeartRateComparison.text(for: row.viewerBpm),
                                otherValue: ProfileHeartRateComparison.text(for: row.otherBpm),
                                isViewerLoading: false,
                                isOtherLoading: isOtherLoading,
                                showDivider: row.id != heartRate.rows.last?.id
                            )
                        }
                    }
                }
            }

            PublicProfileAchievementsSection(
                viewer: ProfileAchievementTally(
                    ladder: viewer.achievements,
                    firstAscentsHeld: viewer.firstAscentsHeld.count
                ),
                other: ProfileAchievementTally(
                    ladder: otherUser.achievements,
                    firstAscentsHeld: otherUser.firstAscentsHeld.count
                ),
                isOtherLoading: isOtherLoading
            )
        }
    }

    private func comparisonInfoRow(
        label: String,
        viewerValue: String,
        otherValue: String,
        isViewerLoading: Bool,
        isOtherLoading: Bool,
        showDivider: Bool = true
    ) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Group {
                    if isViewerLoading {
                        AscendSkeletonText(width: 64, height: 17)
                    } else {
                        Text(viewerValue)
                            .font(.montserratBold(size: 16))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(label)
                    .font(.montserratBold(size: 12))
                    .foregroundStyle(ProfileVisualStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: 116, alignment: .center)

                Group {
                    if isOtherLoading {
                        AscendSkeletonText(width: 64, height: 17)
                    } else {
                        Text(otherValue)
                            .font(.montserratBold(size: 16))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 14)

            if showDivider {
                Rectangle()
                    .fill(ProfileVisualStyle.cardStroke)
                    .frame(height: 1)
            }
        }
    }

    private func valueOrDash(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return value
    }

    private func formatHeight(_ heightCm: Double?) -> String {
        guard let heightCm, heightCm > 0 else { return "-" }
        return measurementSystem.formatHeightCentimeters(heightCm)
    }

    private func formatWeight(_ weightKg: Double?) -> String {
        guard let weightKg, weightKg > 0 else { return "-" }
        let converted = MeasurementSystem.metric.convertWeight(weightKg, to: measurementSystem)
        return measurementSystem.formatWeight(converted)
    }

    private func formatStreak(_ weeks: Int) -> String {
        weeks > 0 ? "\(weeks) wk" : "-"
    }

    private func formatAverageSteps(_ value: Double?) -> String {
        guard let value else { return "-" }
        return Int(value.rounded()).formatted(.number.grouping(.automatic))
    }

    private func formatAverageDuration(_ value: TimeInterval?) -> String {
        guard let value else { return "-" }
        return ProfileDateFormatters.durationClock(value)
    }

    private func formatSPM(_ value: Double) -> String {
        value > 0 ? "\(Int(value.rounded()))" : "-"
    }
}

private struct ProfileComparisonStatRow: View {
    let label: String
    let viewerValueText: String
    let otherValueText: String
    let viewerValue: Double
    let otherValue: Double
    var isOtherLoading = false
    var showDivider = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewerValueText)
                    .font(.montserratBold(size: 17))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(label)
                    .font(.montserratBold(size: 12))
                    .foregroundStyle(ProfileVisualStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .frame(width: 118, alignment: .center)

                Group {
                    if isOtherLoading {
                        AscendSkeletonText(width: 78, height: 18)
                    } else {
                        Text(otherValueText)
                            .font(.montserratBold(size: 17))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            ProfileComparisonStatBar(
                viewerValue: viewerValue,
                otherValue: otherValue,
                isLoadingOtherValue: isOtherLoading
            )

            if showDivider {
                Rectangle()
                    .fill(ProfileVisualStyle.cardStroke)
                    .frame(height: 1)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 10)
    }
}

private struct ProfileComparisonHeadToHeadTab: View {
    let comparison: ProfileComparisonSummary
    let results: [ProfileHeadToHeadClimbResult]
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ProfileComparisonSection(title: "HEAD-TO-HEAD RECORD") {
                VStack(spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        if isLoading {
                            AscendSkeletonText(width: 44, height: 42)
                        } else {
                            Text("\(comparison.viewerWins)")
                                .font(.montserratBold(size: 40))
                                .foregroundStyle(Color.ascendAccent)
                        }

                        Text("-")
                            .font(.montserratBold(size: 28))
                            .foregroundStyle(ProfileVisualStyle.tertiaryText)

                        if isLoading {
                            AscendSkeletonText(width: 44, height: 42)
                        } else {
                            Text("\(comparison.otherUserWins)")
                                .font(.montserratBold(size: 40))
                                .foregroundStyle(ProfileVisualStyle.opponentBlue)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    ProfileComparisonStatBar(
                        viewerValue: Double(comparison.viewerWins),
                        otherValue: Double(comparison.otherUserWins),
                        isLoadingOtherValue: isLoading
                    )

                    if isLoading {
                        AscendSkeletonText(width: 58, height: 12)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if comparison.ties > 0 {
                        Text("\(comparison.ties) tied")
                            .font(.montserratBold(size: 11))
                            .foregroundStyle(ProfileVisualStyle.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }

            ProfileComparisonSection(title: "SHARED CLIMBS") {
                if isLoading && results.isEmpty {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { _ in
                            ProfileHeadToHeadLoadingRow()
                        }
                    }
                } else if let emptyMessage {
                    ProfileComparisonEmptyState(message: emptyMessage)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { result in
                            ProfileHeadToHeadClimbRow(result: result)
                        }
                    }
                }
            }
        }
    }

    private var emptyMessage: String? {
        switch comparison.state {
        case .viewerEmpty:
            return "You have no climbs to compare. Complete a climb to start competing."
        case .otherEmpty:
            return "No public climbs yet. If you know this person, tell them to get on the stair stepper ASAP."
        case .noSharedClimbs:
            return "No shared landmarks yet. Finish one of their climbs to see how you stack up."
        case .hidden:
            return results.isEmpty ? "No shared landmarks yet. Finish one of their climbs to see how you stack up." : nil
        case .shared:
            return results.isEmpty ? "No shared landmarks yet. Finish one of their climbs to see how you stack up." : nil
        }
    }
}

private struct ProfileComparisonEmptyState: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.montserratMedium(size: 14))
            .foregroundStyle(ProfileVisualStyle.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(ProfileVisualStyle.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(ProfileVisualStyle.cardStroke, lineWidth: 1)
            }
    }
}

private struct ProfileHeadToHeadLoadingRow: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                AscendSkeletonText(width: 58, height: 16)
                    .frame(width: 72, alignment: .leading)

                VStack(spacing: 6) {
                    AscendSkeletonText(width: 144, height: 15)
                    AscendSkeletonText(width: 72, height: 11)
                }
                .frame(maxWidth: .infinity)

                AscendSkeletonText(width: 58, height: 16)
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.vertical, 16)

            Rectangle()
                .fill(ProfileVisualStyle.cardStroke)
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct ProfileHeadToHeadClimbRow: View {
    let result: ProfileHeadToHeadClimbResult

    private var viewerValueText: String {
        switch result.measure {
        case let .completionTime(viewerSeconds, _):
            return ProfileDateFormatters.durationClock(viewerSeconds)
        case let .mostSteps(viewerSteps, _):
            return viewerSteps.formatted(.number.grouping(.automatic))
        }
    }

    private var otherValueText: String {
        switch result.measure {
        case let .completionTime(_, otherUserSeconds):
            return ProfileDateFormatters.durationClock(otherUserSeconds)
        case let .mostSteps(_, otherUserSteps):
            return otherUserSteps.formatted(.number.grouping(.automatic))
        }
    }

    /// Names what the two numbers are, since a landmark's are times and the Just Climb's steps.
    private var detailText: String {
        switch result.measure {
        case .completionTime:
            let steps = result.stepCount.map { $0.formatted(.number.grouping(.automatic)) }
            return steps.map { "\($0) steps" } ?? "Fastest time"
        case .mostSteps:
            return "Most steps"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(viewerValueText)
                    .font(.montserratBold(size: 15))
                    .foregroundStyle(result.winner == .viewer ? Color.ascendAccent : ProfileVisualStyle.tertiaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: 72, alignment: .leading)

                VStack(spacing: 3) {
                    Text(result.climbName)
                        .font(.montserratBold(size: 14))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(detailText)
                        .font(.montserratMedium(size: 11))
                        .foregroundStyle(ProfileVisualStyle.tertiaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                Text(otherValueText)
                    .font(.montserratBold(size: 15))
                    .foregroundStyle(result.winner == .otherUser ? ProfileVisualStyle.opponentBlue : ProfileVisualStyle.tertiaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.vertical, 16)

            Rectangle()
                .fill(ProfileVisualStyle.cardStroke)
                .frame(height: 1)
        }
    }
}
