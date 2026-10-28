import Foundation
import Observation
import UIKit

/// Owns the Presets tab: which layout and background are showing, the climber's remembered
/// choices, the open panel, and the one best effort they picked to feature.
///
/// SwiftUI-free. The remembered choices live in `UserDefaults`; a chosen photo and the landmark
/// background belong to this climb and are never stored.
@MainActor
@Observable
final class PresetsViewModel {
    enum Panel: String, Equatable {
        case background
        case font
        case stats
        case accent
    }

    private(set) var subject: ShareSheetSubject
    /// Whether the climb is a landmark with hero artwork to sit behind the card.
    let hasTower: Bool

    private(set) var preferences: PresetPreferences
    private let store: PresetPreferencesStore
    private let clock: () -> Date
    private let calendar: Calendar

    /// A background chosen for this climb only: the landmark's tower or a photograph.
    private(set) var sessionBackground: PresetCardBackground?
    var panel: Panel?
    private(set) var pickedBestEffortID: String?

    /// The layout on screen. Swiping onto a layout does not by itself change the remembered one.
    private(set) var currentLayout: PresetLayout

    var artwork = PresetCardArtwork.none

    init(
        subject: ShareSheetSubject,
        hasTower: Bool,
        store: PresetPreferencesStore = PresetPreferencesStore(),
        clock: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        let saved = store.load()
        self.subject = subject
        self.hasTower = hasTower
        self.store = store
        self.clock = clock
        self.calendar = calendar
        self.preferences = saved
        // A landmark climb always opens on its own tower.
        self.sessionBackground = hasTower ? .tower : nil
        self.currentLayout = .classic
        self.currentLayout = Self.resolvedLayout(saved.layout, subject: subject, preferences: saved)
    }

    /// The best-effort cache arrives after the sheet is up; the climber's choices stay.
    func update(subject: ShareSheetSubject) {
        self.subject = subject
        if !layouts.contains(currentLayout) {
            currentLayout = .classic
        }
        if let picked = pickedBestEffortID, !subject.bestEfforts.contains(where: { $0.id == picked }) {
            pickedBestEffortID = nil
        }
    }

    // MARK: - What is showing

    /// The layouts this climb can swipe through, in order.
    var layouts: [PresetLayout] {
        Self.availableLayouts(subject: subject, preferences: preferences)
    }

    var layoutIndex: Int {
        layouts.firstIndex(of: currentLayout) ?? 0
    }

    var layoutCaption: String {
        let index = layoutIndex
        let hint = index == 0 ? "swipe for more" : "\(index + 1) of \(layouts.count)"
        return "\(currentLayout.title) · \(hint)"
    }

    /// What is behind the card: this climb's own tower or photo, else a live seasonal background,
    /// else the remembered flat one.
    var background: PresetCardBackground {
        if let sessionBackground { return sessionBackground }
        if let seasonal = preferences.seasonal, seasonal.isAvailable(on: clock(), calendar: calendar) {
            return .seasonal(seasonal)
        }
        return .flat(preferences.background)
    }

    var seasonalBackgrounds: [SeasonalBackground] {
        SeasonalBackground.available(on: clock(), calendar: calendar)
    }

    var availableStats: [PresetStat] {
        PresetCardModel.availableStats(for: subject)
    }

    var cardModel: PresetCardModel {
        cardModel(for: currentLayout)
    }

    func cardModel(for layout: PresetLayout) -> PresetCardModel {
        PresetCardModel(
            subject: subject,
            preferences: preferences,
            layout: layout,
            background: background,
            pickedBestEffortID: pickedBestEffortID,
            copyYear: SeasonalTheme.copyYear(on: clock(), calendar: calendar)
        )
    }

    /// `N shown`: Steps plus every switched-on stat that has a value, with best efforts counting
    /// only when the climb earned any.
    var shownStatCount: Int {
        let on = availableStats.filter { preferences.isOn($0) }
        return 1 + on.count
    }

    // MARK: - Layout

    func select(layout: PresetLayout) {
        guard layouts.contains(layout) else { return }
        currentLayout = layout
        // Swiping to a layout is browsing; only the layouts a climber stays on are remembered.
        preferences.layout = layout
        store.save(preferences)
    }

    func swipe(by delta: Int) {
        let target = layoutIndex + delta
        guard layouts.indices.contains(target) else { return }
        select(layout: layouts[target])
    }

    // MARK: - Customisation

    func selectBackground(_ flat: PresetFlatBackground) {
        sessionBackground = nil
        preferences.background = flat
        preferences.seasonal = nil
        persist()
    }

    func selectSeasonal(_ seasonal: SeasonalBackground) {
        guard seasonal.isAvailable(on: clock(), calendar: calendar) else { return }
        sessionBackground = nil
        preferences.seasonal = seasonal
        persist()
    }

    func selectTower() {
        guard hasTower else { return }
        sessionBackground = .tower
    }

    func selectPhoto(_ image: UIImage) {
        artwork.photo = image
        artwork.photoScale = 1
        artwork.photoOffset = .zero
        sessionBackground = .photo
    }

    func frame(scale: CGFloat, offset: CGSize) {
        artwork.photoScale = min(max(scale, 1), 4)
        artwork.photoOffset = offset
    }

    func setFont(_ font: PresetFont) {
        preferences.font = font
        persist()
    }

    func setAccent(_ accent: PresetAccent) {
        preferences.accent = accent
        persist()
    }

    func toggle(_ stat: PresetStat) {
        preferences.toggle(stat)
        persist()
    }

    func pickBestEffort(_ id: String?) {
        pickedBestEffortID = id
    }

    /// Black, Classic, Bold, Lime, Time plus SPM plus Rank (plus Best efforts when earned).
    func reset() {
        preferences = .defaults
        sessionBackground = hasTower ? .tower : nil
        pickedBestEffortID = nil
        store.reset()
        currentLayout = Self.resolvedLayout(.classic, subject: subject, preferences: preferences)
    }

    func togglePanel(_ panel: Panel) {
        self.panel = self.panel == panel ? nil : panel
    }

    // MARK: - Rules

    static func availableLayouts(subject: ShareSheetSubject, preferences: PresetPreferences) -> [PresetLayout] {
        PresetLayout.available(
            hasRank: subject.hasRank,
            rankStatOn: preferences.isOn(.rank),
            hasSplits: subject.hasSplits
        )
    }

    /// A saved layout the climb cannot show (a rank layout with no rank, a split layout with no
    /// splits) falls back to Classic.
    static func resolvedLayout(
        _ saved: PresetLayout,
        subject: ShareSheetSubject,
        preferences: PresetPreferences
    ) -> PresetLayout {
        availableLayouts(subject: subject, preferences: preferences).contains(saved) ? saved : .classic
    }

    private func persist() {
        store.save(preferences)
        // Turning Rank off removes the rank layouts from the swipe order.
        if !layouts.contains(currentLayout) {
            currentLayout = .classic
            preferences.layout = .classic
            store.save(preferences)
        }
    }
}
