import SwiftUI

/// Every closed Steps board, frozen at its final result, one period at a time.
struct PastChampionsView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(ModerationStore.self) private var moderationStore
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: PastChampionsViewModel

    init(timeFrame: LeaderboardTimeFrame = .weekly) {
        _viewModel = State(initialValue: PastChampionsViewModel(timeFrame: timeFrame))
    }

    init(viewModel: PastChampionsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                topBar
                timeFrameFilters
                stepper
                content
            }
            .padding(.bottom, 40)
        }
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .trackOnce(screen: .pastChampions)
        .task {
            await viewModel.load()
        }
    }

    private var topBar: some View {
        ZStack {
            Text("PAST CHAMPIONS")
                .font(.montserratBold(size: 12))
                .tracking(3.6)
                .foregroundStyle(.white.opacity(0.86))
                .accessibilityAddTraits(.isHeader)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.white.opacity(0.1)))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var timeFrameFilters: some View {
        HStack(spacing: 8) {
            ForEach(PastChampionsViewModel.timeFrames) { timeFrame in
                let isSelected = viewModel.selectedTimeFrame == timeFrame
                Button {
                    HapticsManager.shared.trigger(.selection)
                    Task { await viewModel.select(timeFrame) }
                } label: {
                    Text(timeFrame.displayName.uppercased())
                        .font(.montserratBold(size: 10))
                        .foregroundStyle(isSelected ? Color.accent : .white.opacity(0.74))
                        .padding(.horizontal, 13)
                        .frame(height: 30)
                        .background(Capsule().fill(isSelected ? Color.accent.opacity(0.09) : .clear))
                        .overlay(
                            Capsule().stroke(isSelected ? Color.accent : .white.opacity(0.16), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private var stepper: some View {
        HStack {
            stepButton(systemName: "chevron.left", label: "Earlier", isEnabled: viewModel.canGoBack) {
                await viewModel.stepBack()
            }

            Spacer(minLength: 8)

            VStack(spacing: 3) {
                Text(stepperTitle)
                    .font(.montserratBold(size: 18))
                    .tracking(0.7)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(stepperSubtitle)
                    .font(.montserratBold(size: 10))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            stepButton(systemName: "chevron.right", label: "Later", isEnabled: viewModel.canGoForward) {
                await viewModel.stepForward()
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "111113"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private func stepButton(
        systemName: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            HapticsManager.shared.trigger(.selection)
            Task { await action() }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(hex: "1F1F21")))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.3)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private var stepperTitle: String {
        guard let period = viewModel.period else { return "-" }
        return ChampionTitleLine.periodName(for: period)
    }

    private var stepperSubtitle: String {
        guard let period = viewModel.period else { return "" }
        let window: String? = switch period.timeFrame {
        case .weekly: period.windowLabel.uppercased()
        case .monthly: LeaderboardPeriod.yearStyle.format(period.startAt)
        default: nil
        }
        let status = viewModel.state == .loaded ? "FINAL" : ""
        return [window, status].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .tint(.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
        case .missing:
            message(
                title: "No final board for \(periodSubject).",
                detail: "Boards freeze a few minutes after they close."
            )
        case .failed:
            VStack(spacing: 14) {
                message(title: "Past boards stalled.", detail: "Check your connection and try again.")
                Button("Try again") {
                    Task { await viewModel.retry() }
                }
                .font(.montserratBold(size: 13))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .frame(height: 34)
                .background(Capsule().fill(Color.accent))
            }
        case .loaded:
            loadedBoard
        }
    }

    @ViewBuilder
    private var loadedBoard: some View {
        let entries = moderationStore.moderate(viewModel.placings.entries(currentUserId: authVM.user?.uid))
        if entries.isEmpty {
            message(
                title: "Nobody climbed \(periodSubject).",
                detail: "An empty board crowns nobody."
            )
        } else {
            VStack(spacing: 16) {
                LeaderboardPodiumView(
                    entries: ModeratedLeaderboardPodiumLayout.podiumEntries(from: entries),
                    metric: .climb,
                    awardedTitle: viewModel.awardedTitle
                )
                .padding(.horizontal, 20)

                let listEntries = ModeratedLeaderboardPodiumLayout.listEntries(from: entries)
                if !listEntries.isEmpty {
                    LeaderboardRowListView(
                        entries: listEntries,
                        metric: .climb,
                        onEntryAppear: { _ in }
                    )
                }

                footer
            }
        }
    }

    private var footer: some View {
        Text(footerText)
            .font(.montserratBold(size: 11))
            .tracking(1.2)
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.top, 4)
    }

    private var footerText: String {
        guard let result = viewModel.result else { return "" }
        let climbers = "\(result.climberCount.formatted()) \(result.climberCount == 1 ? "CLIMBER" : "CLIMBERS")"
        let mostClimbs = moderationStore.moderate(
            viewModel.mostClimbsPlacings.entries(currentUserId: authVM.user?.uid)
        )
        guard let count = result.mostClimbs?.count, !mostClimbs.isEmpty else {
            return climbers
        }
        let names = ChampionNames.joined(mostClimbs.map(\.identity.displayName)).uppercased()
        return "\(climbers) · MOST CLIMBS: \(names) (\(count.formatted()))"
    }

    private var periodSubject: String {
        guard let period = viewModel.period else { return "this period" }
        switch period.timeFrame {
        case .weekly: return "week \(ChampionTitleLine.weekNumber(of: period))"
        default: return ChampionTitleLine.periodName(for: period).capitalized
        }
    }

    private func message(title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.white.opacity(0.66))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 20)
    }
}
