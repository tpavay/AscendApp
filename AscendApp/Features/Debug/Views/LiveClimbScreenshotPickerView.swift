import SwiftUI
import SwiftData

#if DEBUG
struct LiveClimbScreenshotPickerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var climbs: [Climb] = []
    @State private var completedClimbIds: Set<String> = []
    @State private var selectedClimbId = GlobeViewModel.debugDailyRecommendedClimbId()
    @State private var loadErrorMessage: String?
    @State private var searchText = ""

    private let climbService = ClimbService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let selectedClimb {
                    selectedCard(for: selectedClimb)
                } else {
                    noSelectionCard
                }

                searchField

                if let loadErrorMessage {
                    errorState(loadErrorMessage)
                } else if visibleClimbs.isEmpty {
                    emptyState
                } else {
                    climbList
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .themedBackground()
        .preferredColorScheme(.dark)
        .navigationTitle("Live Climb Screenshots")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    clearSelection()
                }
                .disabled(selectedClimbId == nil)
            }
        }
        .task {
            loadClimbs()
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbStateDidChange)) { _ in
            selectedClimbId = GlobeViewModel.debugDailyRecommendedClimbId()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Home Live Climb Override")
                .font(.montserratBold(size: 22))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

            Text("Pick the climb shown on the Home Live Climb card for screenshots. This writes the same daily recommendation value Home already reads, and only exists in DEBUG builds.")
                .font(.montserratRegular(size: 13))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.64) : .gray)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func selectedCard(for climb: Climb) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Selected")
                .font(.montserratBold(size: 10))
                .tracking(1.2)
                .foregroundStyle(.accent)

            ClimbResultRowView(
                climb: climb,
                isCompleted: completedClimbIds.contains(climb.id)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.accent.opacity(0.72), lineWidth: 1)
            )
        }
    }

    private var noSelectionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No override selected")
                .font(.montserratSemiBold(size: 15))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

            Text("Home will use the normal daily recommendation until you choose a climb below.")
                .font(.montserratRegular(size: 13))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.58) : .gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colorScheme == .dark ? .white.opacity(0.05) : .black.opacity(0.03))
        )
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))

            TextField("Search climbs", text: $searchText)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.48))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var climbList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("All Climbs")
                .font(.montserratBold(size: 10))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.56))

            VStack(spacing: 8) {
                ForEach(visibleClimbs) { climb in
                    Button {
                        select(climb)
                    } label: {
                        ClimbResultRowView(
                            climb: climb,
                            isCompleted: completedClimbIds.contains(climb.id)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    selectedClimbId == climb.id ? Color.accent.opacity(0.72) : .clear,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use \(climb.name) as Home Live Climb")
                }
            }
        }
    }

    private var emptyState: some View {
        Text("No climbs available.")
            .font(.montserratRegular(size: 14))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 36)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.orange)

            Text(message)
                .font(.montserratRegular(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var selectedClimb: Climb? {
        guard let selectedClimbId else { return nil }
        return climbs.first(where: { $0.id == selectedClimbId })
    }

    private var visibleClimbs: [Climb] {
        let sortedClimbs = climbs.sorted { lhs, rhs in
            if lhs.referenceStepCount == rhs.referenceStepCount {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return lhs.referenceStepCount < rhs.referenceStepCount
        }

        let normalizedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return sortedClimbs }

        return sortedClimbs.filter { climb in
            climb.name.localizedStandardContains(normalizedQuery) ||
            climb.city.localizedStandardContains(normalizedQuery) ||
            climb.country.localizedStandardContains(normalizedQuery) ||
            climb.category.localizedStandardContains(normalizedQuery) ||
            climb.tags.contains { $0.localizedStandardContains(normalizedQuery) }
        }
    }

    private func loadClimbs() {
        do {
            climbs = try climbService.loadClimbs()
            completedClimbIds = climbService.completedClimbIds(modelContext: modelContext)
            selectedClimbId = GlobeViewModel.debugDailyRecommendedClimbId()
            loadErrorMessage = nil
        } catch {
            climbs = []
            loadErrorMessage = error.localizedDescription
        }
    }

    private func select(_ climb: Climb) {
        selectedClimbId = climb.id
        GlobeViewModel.debugSetDailyRecommendedClimbId(climb.id)
    }

    private func clearSelection() {
        selectedClimbId = nil
        GlobeViewModel.debugClearDailyRecommendedClimbId()
    }
}

#Preview {
    NavigationStack {
        LiveClimbScreenshotPickerView()
    }
    .modelContainer(for: [Workout.self, ClimbAttempt.self], inMemory: true)
}
#endif
