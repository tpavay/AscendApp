import SwiftData
import SwiftUI

/// The share sheet: two tabs, Presets and Stickers, over one dark ground.
///
/// Presented from the finished-climb screen and from Workout Detail with the climb, the frozen
/// finish standing the presenter holds, and nothing else; every number on a card is resolved from
/// those.
struct ShareSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationViewModel.self) private var authVM
    @Query(sort: \BestEffortCacheEntry.sortKey) private var bestEffortCacheEntries: [BestEffortCacheEntry]

    private let workout: Workout
    private let climb: Climb?
    private let rankPosition: Int?
    private let rankField: Int?

    @State private var sheet = ShareSheetViewModel()
    @State private var presets: PresetsViewModel?
    @State private var stickers: StickersViewModel?

    init(workout: Workout, climb: Climb?, climbRank: Int?, climbRankTotal: Int?) {
        self.workout = workout
        self.climb = climb
        self.rankPosition = climbRank
        self.rankField = climbRankTotal
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(shareHex: 0x0B0B0B).ignoresSafeArea()

            if let presets, let stickers {
                VStack(spacing: 0) {
                    ShareSheetHeader(subject: presets.subject, onClose: { dismiss() })
                    ShareSheetTabs(selection: $sheet.tab, accent: Color(shareHex: PresetAccent.lime.hex))
                    switch sheet.tab {
                    case .presets:
                        PresetsTabView(model: presets, sheet: sheet, workout: workout, climb: climb)
                    case .stickers:
                        StickersTabView(model: stickers, sheet: sheet)
                    }
                }
                ShareSheetToastView(message: sheet.toast, raised: sheet.tab == .stickers || presets.panel != nil)
            } else {
                ProgressView().tint(.white)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: SubjectInputs(bestEffortCount: bestEffortCacheEntries.count, rankPosition: rankPosition, rankField: rankField)) {
            buildModels()
        }
        .task(id: climb?.id) {
            guard let climb, presets != nil, presets?.artwork.tower == nil else { return }
            presets?.artwork.tower = await sheet.shareExporter.loadClimbArtwork(for: climb)
        }
        .trackOnce(screen: .shareComposer)
    }

    /// What the subject is built from that can arrive after the sheet is up: the best-effort
    /// cache through `@Query`, and the frozen standing the presenter resolves after Share is tapped.
    private struct SubjectInputs: Hashable {
        let bestEffortCount: Int
        let rankPosition: Int?
        let rankField: Int?
    }

    /// Rebuilds the subject whenever its inputs change, keeping the climber's choices.
    private func buildModels() {
        let snapshot = BestEffortCacheSnapshot(entries: bestEffortCacheEntries, workouts: [workout])
        let subject = ShareSheetSubjectBuilder.make(
            workout: workout,
            climb: climb,
            rankPosition: rankPosition,
            rankField: rankField,
            bestEfforts: snapshot.efforts(for: workout),
            measurementSystem: SettingsManager.shared.measurementSystem
        )

        if presets == nil {
            presets = PresetsViewModel(subject: subject, hasTower: climb != nil)
            stickers = StickersViewModel(
                subject: subject,
                modelContext: modelContext,
                userId: authVM.user?.uid
            )
        } else {
            presets?.update(subject: subject)
            stickers?.update(subject: subject)
        }
    }
}
