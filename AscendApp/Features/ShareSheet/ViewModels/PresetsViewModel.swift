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
    private let analytics: ShareSheetAnalyticsReporter?

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
        calendar: Calendar = .current,
        analytics: ShareSheetAnalyticsReporter? = nil
    ) {
        let saved = store.load()
        self.analytics = analytics
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
        caption(at: layoutIndex)
    }

    /// The line under the page marks for the layout at `index`.
    func caption(at index: Int) -> String {
        let layouts = layouts
        guard layouts.indices.contains(index) else { return "" }
        let hint = index == 0 ? "swipe for more" : "\(index + 1) of \(layouts.count)"
        return "\(layouts[index].title) · \(hint)"
    }

    /// What is behind the card: this climb's own tower or photo, else the saved seasonal
    /// background while its window is live and Black once it has closed, else the remembered flat
    /// one.
    var background: PresetCardBackground {
        if let sessionBackground { return sessionBackground }
        if let seasonal = preferences.seasonal {
            return seasonal.isAvailable(on: clock(), calendar: calendar) ? .seasonal(seasonal) : .flat(.black)
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
        cardModel(for: layout, background: background)
    }

    /// The card as it would draw on `background`, which a swatch renders to show that choice.
    func swatchModel(for background: PresetCardBackground) -> PresetCardModel {
        cardModel(for: currentLayout, background: background)
    }

    private func cardModel(for layout: PresetLayout, background: PresetCardBackground) -> PresetCardModel {
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
        let changed = layout != currentLayout
        currentLayout = layout
        // Landing on the layout already showing is not a choice, so it reports nothing.
        if changed { analytics?.cardSelected(layout) }
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
        let before = background
        sessionBackground = nil
        preferences.background = flat
        preferences.seasonal = nil
        persist()
        reportBackgroundEdit(from: before, value: flat.rawValue)
    }

    func selectSeasonal(_ seasonal: SeasonalBackground) {
        guard seasonal.isAvailable(on: clock(), calendar: calendar) else { return }
        let before = background
        sessionBackground = nil
        preferences.seasonal = seasonal
        persist()
        reportBackgroundEdit(from: before, value: ShareBackgroundKind.seasonal.rawValue)
    }

    func selectTower() {
        guard hasTower else { return }
        let before = background
        sessionBackground = .tower
        reportBackgroundEdit(from: before, value: ShareBackgroundKind.tower.rawValue)
    }

    func selectPhoto(_ image: UIImage) {
        artwork.photo = image
        artwork.photoScale = 1
        artwork.photoOffset = .zero
        sessionBackground = .photo
        analytics?.edited(.photo, value: ShareBackgroundKind.photo.rawValue)
    }

    /// Choosing the background already showing is not an edit.
    private func reportBackgroundEdit(from before: PresetCardBackground, value: String) {
        guard background != before else { return }
        analytics?.edited(.background, value: value)
    }

    func frame(scale: CGFloat, offset: CGSize) {
        artwork.frame(scale: scale, offset: offset)
    }

    func setFont(_ font: PresetFont) {
        let changed = preferences.font != font
        preferences.font = font
        persist()
        if changed { analytics?.edited(.font, value: font.rawValue) }
    }

    func setAccent(_ accent: PresetAccent) {
        let changed = preferences.accent != accent
        preferences.accent = accent
        persist()
        if changed { analytics?.edited(.accent, value: accent.rawValue) }
    }

    func toggle(_ stat: PresetStat) {
        preferences.toggle(stat)
        persist()
        analytics?.edited(.stat, value: "\(stat.rawValue)_\(preferences.isOn(stat) ? "on" : "off")")
    }

    func pickBestEffort(_ id: String?) {
        let changed = pickedBestEffortID != id
        pickedBestEffortID = id
        // Which effort was picked is the climber's own record, so only that one was chosen is reported.
        if changed { analytics?.edited(.bestEffort, value: id == nil ? "none" : "chosen") }
    }

    /// Black, Classic, Bold, Lime, Time plus SPM plus Rank (plus Best efforts when earned).
    func reset() {
        let hadEdits = preferences != .defaults
        preferences = .defaults
        sessionBackground = hasTower ? .tower : nil
        pickedBestEffortID = nil
        store.reset()
        currentLayout = Self.resolvedLayout(.classic, subject: subject, preferences: preferences)
        if hadEdits { analytics?.edited(.reset, value: "defaults") }
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
