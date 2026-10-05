import SwiftUI

/// Filter climbers: tick the climbers Everyone narrows down to. The climbers whose best is nearest
/// the climber's come first, then everyone on the board, most steps first; the choice is kept for
/// every climb after. Named by the captain on 2026-09-29 ("Filter Climbers", "Done" with the
/// number chosen).
struct AscendMountainFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ModerationStore.self) private var moderationStore

    /// The step count the nearest climbers are measured from: the climber's own best.
    let nearSteps: Int
    let onDone: ([String]) -> Void

    /// Owned here, so a parent redrawing never swaps in an empty list mid-search.
    @State private var directory: MountainClimberDirectory
    @State private var chosen: [String]
    @State private var query = ""

    init(
        board: MountainRaceBoard,
        context: LiveReplayLeaderboardContext,
        chosen: [String],
        nearSteps: Int,
        onDone: @escaping ([String]) -> Void
    ) {
        self.nearSteps = nearSteps
        self.onDone = onDone
        _directory = State(initialValue: MountainClimberDirectory(board: board, context: context))
        _chosen = State(initialValue: chosen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            searchField

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    allClimbersRow

                    if query.isEmpty, !closeRows.isEmpty {
                        sectionLabel("CLOSE TO YOUR BEST")
                        ForEach(closeRows) { climberRow($0, detail: closeDetail(for: $0)) }
                    }

                    sectionLabel(query.isEmpty ? "EVERYONE" : "RESULTS")
                    ForEach(everyoneRows) { climberRow($0, detail: "Best \($0.finalSteps.formatted()) steps") }

                    footer
                }
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.immediately)

            doneButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .task { await directory.load(nearSteps: nearSteps) }
        .task(id: searchReadKey) { await readOnForSearch() }
        .trackOnce(screen: .mountainRaceFilter)
    }

    // MARK: - Rows

    private var closeRows: [ModeratedReplayLeaderboardRow] {
        visible(moderationStore.moderate(directory.closeToYourBest))
    }

    private var everyoneRows: [ModeratedReplayLeaderboardRow] {
        let rows = visible(moderationStore.moderate(directory.everyone))
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.identity.displayName.localizedStandardContains(query) }
    }

    /// Only climbers who can be named and raced: a hidden identity - blocked, or not yet cleared -
    /// is not offered, and neither is a row with no climber behind it.
    private func visible(_ rows: [ModeratedReplayLeaderboardRow]) -> [ModeratedReplayLeaderboardRow] {
        rows.filter { !$0.identity.isHidden && $0.userId != nil }
    }

    private func closeDetail(for row: ModeratedReplayLeaderboardRow) -> String {
        let side = row.finalSteps >= nearSteps ? "just ahead of your best" : "just behind your best"
        return "Best \(row.finalSteps.formatted()) steps · \(side)"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FILTER CLIMBERS")
                .font(.montserratBold(size: 22))
                .foregroundStyle(.white)
            Text("Only the climbers you tick race you.")
                .font(.montserratMedium(size: 13))
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.5))
            TextField("Search climbers", text: $query)
                .font(.montserratMedium(size: 15))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.08)))
    }

    private var allClimbersRow: some View {
        selectableRow(
            title: "All climbers",
            detail: "Race everyone",
            isOn: chosen.isEmpty,
            isEnabled: true
        ) {
            chosen = []
        }
    }

    private func climberRow(_ row: ModeratedReplayLeaderboardRow, detail: String) -> some View {
        let userId = row.userId ?? row.id
        let isOn = chosen.contains(userId)
        return selectableRow(
            title: row.identity.displayName,
            detail: detail,
            isOn: isOn,
            isEnabled: isOn || chosen.count < MountainRaceSelection.chosenLimit
        ) {
            if isOn {
                chosen.removeAll { $0 == userId }
            } else {
                chosen.append(userId)
            }
        }
    }

    private func selectableRow(
        title: String,
        detail: String,
        isOn: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.montserratBold(size: 15))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(.white.opacity(0.56))
                }
                .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isOn ? Color.accent : .white.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isOn ? Color.accent : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.montserratBold(size: 11))
            .tracking(1.2)
            .foregroundStyle(.white.opacity(0.5))
            .padding(.top, 10)
    }

    // MARK: - Loading

    @ViewBuilder
    private var footer: some View {
        if directory.didFail {
            Button {
                Task { await directory.retry(nearSteps: nearSteps) }
            } label: {
                Text("Couldn't load climbers. Tap to try again.")
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        } else if directory.canLoadMore, query.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 44)
                .onAppear { Task { await directory.loadMore() } }
        } else if directory.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    /// Reads on while a search has found few and the board may hold more.
    private var searchReadKey: String {
        "\(query)|\(directory.everyone.count)"
    }

    private func readOnForSearch() async {
        guard !query.isEmpty, directory.shouldReadOnForSearch(matches: everyoneRows.count) else { return }
        await directory.loadMore()
    }

    private var doneButton: some View {
        Button {
            onDone(chosen)
            dismiss()
        } label: {
            Text(chosen.isEmpty ? "DONE · ALL CLIMBERS" : "DONE · \(chosen.count) CHOSEN")
                .font(.montserratBold(size: 14))
                .tracking(1.1)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accent))
        }
        .buttonStyle(.plain)
    }
}
