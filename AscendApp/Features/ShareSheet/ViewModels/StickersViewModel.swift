import Foundation
import Observation
import SwiftData

/// Owns the Stickers tab: This climb or Totals, the period, the shared Font, Color and Shadow
/// style, and the totals data.
@MainActor
@Observable
final class StickersViewModel {
    enum Scope: Equatable {
        case climb
        case totals
    }

    enum Panel: Equatable {
        case font
        case color
        case shadow
    }

    private(set) var subject: ShareSheetSubject
    var scope: Scope = .climb
    var period: SharePeriod = .week
    var panel: Panel?
    private(set) var style: StickerStyle
    private(set) var totals: ShareTotalsSnapshot?

    private let modelContext: ModelContext
    private let userId: String?
    private let repository: ShareTotalsRepository
    private let store: StickerStyleStore
    private let now: @Sendable () -> Date
    private var loadGeneration = 0

    init(
        subject: ShareSheetSubject,
        modelContext: ModelContext,
        userId: String?,
        repository: ShareTotalsRepository = ShareTotalsRepository(),
        store: StickerStyleStore = StickerStyleStore(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.now = now
        self.subject = subject
        self.modelContext = modelContext
        self.userId = userId
        self.repository = repository
        self.store = store
        self.style = store.load()
    }

    func update(subject: ShareSheetSubject) {
        self.subject = subject
    }

    // MARK: - What the grid shows

    var climbKinds: [StickerKind] {
        StickerCatalog.climbStickers(for: subject)
    }

    var totalsKinds: [StickerKind] {
        totals.map(StickerCatalog.totalsStickers(for:)) ?? []
    }

    /// The live theme's stickers lead the This climb grid, since each one prints this climb's steps.
    var seasonalKinds: [SeasonalStickerKind] {
        scope == .climb ? SeasonalStickerCatalog.stickers(on: now()) : []
    }

    var items: [StickerItem] {
        let standard = (scope == .climb ? climbKinds : totalsKinds).map(StickerItem.standard)
        return seasonalKinds.map(StickerItem.seasonal) + standard
    }

    var seasonalYear: Int {
        Calendar.current.component(.year, from: now())
    }

    /// `Oct 9 · Just Climb`.
    var climbScopeTitle: String {
        "\(subject.dateText.capitalized) · \(subject.title)"
    }

    /// Light preview tiles keep a black sticker visible; the exported sticker stays transparent.
    var previewTilesAreLight: Bool {
        style.color == .black
    }

    // MARK: - Style

    func setFont(_ font: StickerStyle.Font) {
        style.font = font
        store.save(style)
    }

    func setColor(_ color: StickerStyle.Color) {
        style.color = color
        store.save(style)
    }

    func setShadow(_ shadow: StickerStyle.Shadow) {
        style.shadow = shadow
        store.save(style)
    }

    func togglePanel(_ panel: Panel) {
        self.panel = self.panel == panel ? nil : panel
    }

    // MARK: - Totals

    /// Draws the workout figures at once, then fills in the three standings when they arrive.
    func loadTotals() async {
        loadGeneration += 1
        let generation = loadGeneration
        totals = repository.snapshot(period: period, modelContext: modelContext)
        let full = await repository.snapshotWithStandings(
            period: period,
            userId: userId,
            modelContext: modelContext
        )
        guard generation == loadGeneration else { return }
        totals = full
    }
}
