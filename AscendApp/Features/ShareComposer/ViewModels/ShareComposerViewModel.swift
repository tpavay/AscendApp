import CoreGraphics
import Foundation
import Observation
import UIKit

/// Owns the share composer's editing state: the chosen background, the placed
/// stat stickers, selection, and the snapping/trash geometry. SwiftUI-free per
/// CLAUDE.md (Foundation/Observation/CoreGraphics/UIKit only).
@MainActor
@Observable
final class ShareComposerViewModel {
    // Inputs for stat resolution
    let workout: Workout
    let measurementSystem: MeasurementSystem
    let stepHeight: Double
    let climb: Climb?
    let climbName: String?
    let climbRank: Int?
    let climbRankTotal: Int?

    // Editing state
    var background: ShareBackgroundSource?
    /// Color grade applied to the background only (swipe left/right to cycle).
    var backgroundFilter: ShareBackgroundFilter = .original
    /// Background pan/zoom. Scale is unitless (1 = fit); offset is a fraction of
    /// the canvas, so it maps identically to the high-res export size.
    var backgroundScale: CGFloat = 1
    var backgroundOffset: CGSize = .zero
    /// Core Image-processed background for geometric filters (nil for color grades).
    var processedBackgroundImage: UIImage?
    /// Cache so each geometric filter is computed once per chosen photo.
    @ObservationIgnored private var processedCache: [ShareBackgroundFilter: UIImage] = [:]
    var stickers: [ShareStickerInstance] = []
    var selectedID: UUID?
    /// User-chosen display name for the climb (stat values stay the truth; only
    /// the climb's title is renameable). `nil` = use the catalog name.
    var climbNameOverride: String?

    /// The workout's Best Efforts, injected from the Best Effort cache by the
    /// view (the resolver can't compute them from the Workout alone). Each has a
    /// unique `label` used as the sticker's `injectedStatKey`.
    var bestEffortStats: [ResolvedShareStat] = []
    /// This-week aggregate stats (steps, workouts, time, vertical), injected from
    /// the full workout history. Each has a unique `label` used as the key.
    var weeklyTotalStats: [ResolvedShareStat] = []

    // Transient drag feedback (driven by ShareStickerView callbacks)
    var draggingID: UUID?
    /// Canvas-space x where a vertical snap guide should render (nil = no snap).
    var verticalGuideX: CGFloat?
    /// Canvas-space y where a horizontal snap guide should render (nil = no snap).
    var horizontalGuideY: CGFloat?
    var isOverTrash = false

    /// Capture radius for magnetic snapping. The sticker glues to a guide line
    /// while the drag stays within this distance, then pops off beyond it.
    private let snapThreshold: CGFloat = 18

    init(
        workout: Workout,
        measurementSystem: MeasurementSystem,
        stepHeight: Double,
        climb: Climb? = nil,
        climbName: String? = nil,
        climbRank: Int? = nil,
        climbRankTotal: Int? = nil,
        initialBackground: ShareBackgroundSource? = nil
    ) {
        self.workout = workout
        self.measurementSystem = measurementSystem
        self.stepHeight = stepHeight
        self.climb = climb
        self.climbName = climbName
        self.climbRank = climbRank
        self.climbRankTotal = climbRankTotal
        self.background = initialBackground
    }

    /// Climb artwork offered as an image sticker (when sharing a climb). One
    /// variant only — the user resizes it freely once placed.
    var climbImageStickerVariants: [ClimbImageVariant] {
        climb == nil ? [] : [.thumb]
    }

    // MARK: - Stat resolution

    private var resolver: ShareStatResolver {
        ShareStatResolver(
            workout: workout,
            measurementSystem: measurementSystem,
            stepHeight: stepHeight,
            climbName: climbNameOverride ?? climbName,
            climbRank: climbRank,
            climbRankTotal: climbRankTotal
        )
    }

    var isClimb: Bool { climbName != nil }

    /// This-climb / this-workout stats that have a value, resolved for display.
    /// Best Efforts and Totals are surfaced as their own sections, not here.
    func climbStats() -> [ResolvedShareStat] {
        resolver.availableKinds().compactMap { resolver.resolve($0) }
    }

    /// Resolve a single stat reference. Injected kinds (`.bestEffort`, `.totals`)
    /// look up their value by key; everything else resolves from the workout.
    func resolved(_ ref: ShareStatRef) -> ResolvedShareStat? {
        switch ref.kind {
        case .bestEffort: return injected(ref.injectedStatKey, in: bestEffortStats)
        case .totals: return injected(ref.injectedStatKey, in: weeklyTotalStats)
        default: return resolver.resolve(ref.kind)
        }
    }

    /// All resolved metrics for a sticker (one for a single sticker, several for
    /// a composite). Unresolvable refs are dropped.
    func resolvedStats(for instance: ShareStickerInstance) -> [ResolvedShareStat] {
        instance.statRefs.compactMap { resolved($0) }
    }

    /// The sticker's primary resolved value (used for the font-preview sheet).
    func resolve(_ instance: ShareStickerInstance) -> ResolvedShareStat? {
        resolved(instance.primaryStatRef)
    }

    private func injected(_ key: String?, in list: [ResolvedShareStat]) -> ResolvedShareStat? {
        if let key, let match = list.first(where: { $0.label == key }) { return match }
        return list.first
    }

    // MARK: - Structure (composite stickers)

    func setLayout(_ layout: ShareStatLayout, for id: UUID) {
        guard let i = stickers.firstIndex(where: { $0.id == id }) else { return }
        stickers[i].layout = layout
    }

    /// Metrics offered for a sticker's structure sheet — same family as the
    /// sticker's primary metric (workout/climb stats, best efforts, or totals).
    func paletteRefs(for instance: ShareStickerInstance) -> [ShareStatRef] {
        switch instance.kind {
        case .bestEffort:
            return bestEffortStats.map { ShareStatRef(kind: .bestEffort, injectedStatKey: $0.label) }
        case .totals:
            return weeklyTotalStats.map { ShareStatRef(kind: .totals, injectedStatKey: $0.label) }
        default:
            return resolver.availableKinds().map { ShareStatRef(kind: $0, injectedStatKey: nil) }
        }
    }

    /// Add/remove a metric on a composite sticker. Keeps at least one metric
    /// (removing the primary promotes the first extra) and caps the total at 4.
    func toggleStat(_ ref: ShareStatRef, for id: UUID) {
        guard let i = stickers.firstIndex(where: { $0.id == id }) else { return }
        var sticker = stickers[i]
        if sticker.primaryStatRef == ref {
            guard !sticker.extraStats.isEmpty else { return } // never remove the last metric
            let promoted = sticker.extraStats.removeFirst()
            sticker.kind = promoted.kind
            sticker.injectedStatKey = promoted.injectedStatKey
        } else if let idx = sticker.extraStats.firstIndex(of: ref) {
            sticker.extraStats.remove(at: idx)
        } else if sticker.statRefs.count < 4 {
            sticker.extraStats.append(ref)
        }
        stickers[i] = sticker
    }

    // MARK: - Climb rename

    func setClimbName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        climbNameOverride = trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Sticker mutations

    func addSticker(kind: ShareStatStickerKind, style: ShareStickerStyle = .display) {
        // Stagger new stickers slightly so stacking is visible.
        let offset = CGFloat(stickers.count % 5) * 0.04
        let instance = ShareStickerInstance(
            kind: kind,
            style: style,
            position: CGPoint(x: 0.5, y: 0.42 + offset)
        )
        stickers.append(instance)
        selectedID = instance.id
    }

    func addClimbImageSticker(variant: ClimbImageVariant) {
        let offset = CGFloat(stickers.count % 5) * 0.04
        let instance = ShareStickerInstance(
            kind: .climbName, // unused for image stickers
            position: CGPoint(x: 0.5, y: 0.42 + offset),
            climbImageVariant: variant
        )
        stickers.append(instance)
        selectedID = instance.id
    }

    /// Curated stats for the recap card's stat row (duration · steps · calories,
    /// dropping any that don't resolve for this workout).
    func recapStats() -> [ResolvedShareStat] {
        [ShareStatStickerKind.duration, .steps, .calories]
            .compactMap { resolved(ShareStatRef(kind: $0, injectedStatKey: nil)) }
    }

    /// Add an injected stat (Best Effort or Totals) as a sticker, keyed so it
    /// resolves back to the right value from the injected lists.
    func addInjectedSticker(_ stat: ResolvedShareStat) {
        let offset = CGFloat(stickers.count % 5) * 0.04
        let instance = ShareStickerInstance(
            kind: stat.kind,
            position: CGPoint(x: 0.5, y: 0.42 + offset),
            injectedStatKey: stat.label
        )
        stickers.append(instance)
        selectedID = instance.id
    }

    /// Switch to a freshly chosen background, clearing any placed stickers and
    /// resetting the filter + transform so the user starts the new canvas clean.
    func resetForNewBackground(_ source: ShareBackgroundSource) {
        stickers.removeAll()
        selectedID = nil
        backgroundFilter = .original
        backgroundScale = 1
        backgroundOffset = .zero
        processedBackgroundImage = nil
        processedCache.removeAll()
        background = source
    }

    /// Filters available for the current background. Geometric (Core Image)
    /// filters need a still photo, so presets/videos only get color grades.
    var availableFilters: [ShareBackgroundFilter] {
        if case .photo = background { return ShareBackgroundFilter.allCases }
        return ShareBackgroundFilter.allCases.filter { !$0.isGeometric }
    }

    /// Cycle the background filter (driven by a horizontal swipe on the canvas).
    func cycleFilter(forward: Bool) {
        let all = availableFilters
        let idx = all.firstIndex(of: backgroundFilter) ?? 0
        let next = forward ? (idx + 1) % all.count : (idx - 1 + all.count) % all.count
        backgroundFilter = all[next]
        refreshProcessedBackground()
    }

    func setFilter(_ filter: ShareBackgroundFilter) {
        guard availableFilters.contains(filter) else { return }
        backgroundFilter = filter
        refreshProcessedBackground()
    }

    /// Compute (and cache) the Core Image-processed background for geometric
    /// filters; color/original grades use the unprocessed photo + SwiftUI modifiers.
    private func refreshProcessedBackground() {
        guard backgroundFilter.isGeometric, case .photo(let image) = background else {
            processedBackgroundImage = nil
            return
        }
        if let cached = processedCache[backgroundFilter] {
            processedBackgroundImage = cached
            return
        }
        let result = ShareImageFilter.apply(backgroundFilter, to: image)
        if let result { processedCache[backgroundFilter] = result }
        processedBackgroundImage = result
    }

    // MARK: - Background transform (free-form pan / zoom)

    /// The background is "free-form" once scaled or moved away from its default
    /// fit. In that state a drag repositions it; at the default fit a horizontal
    /// drag instead cycles the filter (and double-tap returns to this state).
    var backgroundIsManipulated: Bool {
        abs(backgroundScale - 1) > 0.01 || backgroundOffset != .zero
    }

    func commitBackgroundZoom(_ factor: CGFloat) {
        // Free-form: allow shrinking below fit (zoom out) and growing up to 5×.
        backgroundScale = min(max(backgroundScale * factor, 0.3), 5)
    }

    func commitBackgroundPan(dxFraction: CGFloat, dyFraction: CGFloat) {
        backgroundOffset = CGSize(width: backgroundOffset.width + dxFraction,
                                  height: backgroundOffset.height + dyFraction)
    }

    func resetBackgroundTransform() {
        backgroundScale = 1
        backgroundOffset = .zero
    }

    func deleteSticker(_ id: UUID) {
        stickers.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
    }

    func select(_ id: UUID) {
        selectedID = id
    }

    func deselect() {
        selectedID = nil
    }

    // MARK: - Drag feedback / snapping / trash

    /// Trash zone rect in canvas space (bottom-center).
    func trashRect(in canvasSize: CGSize) -> CGRect {
        let w: CGFloat = 150, h: CGFloat = 84
        return CGRect(x: (canvasSize.width - w) / 2, y: canvasSize.height - h - 24, width: w, height: h)
    }

    private func verticalSnapTargets(_ canvasSize: CGSize) -> [CGFloat] {
        [canvasSize.width / 2, canvasSize.width * 0.12, canvasSize.width * 0.88]
    }

    private func horizontalSnapTargets(_ canvasSize: CGSize) -> [CGFloat] {
        [canvasSize.height / 2]
    }

    func handleDragChanged(id: UUID, center: CGPoint, canvasSize: CGSize) {
        let isNewDrag = draggingID != id
        draggingID = id
        // Drag start
        if isNewDrag { HapticsManager.shared.trigger(.lightImpact) }

        // Trash hover (heavier haptic on entering the zone)
        let nowOverTrash = trashRect(in: canvasSize).contains(center)
        if nowOverTrash && !isOverTrash { HapticsManager.shared.trigger(.heavyImpact) }
        isOverTrash = nowOverTrash

        // Snap guides — fire a light haptic when entering a new snap line.
        let newVX = verticalSnapTargets(canvasSize).first { abs(center.x - $0) <= snapThreshold }
        if newVX != nil, verticalGuideX == nil { HapticsManager.shared.trigger(.lightImpact) }
        verticalGuideX = newVX

        let newHY = horizontalSnapTargets(canvasSize).first { abs(center.y - $0) <= snapThreshold }
        if newHY != nil, horizontalGuideY == nil { HapticsManager.shared.trigger(.lightImpact) }
        horizontalGuideY = newHY
    }

    /// Snap a raw canvas-space center to the nearest center/edge target when close.
    func snappedCenter(_ raw: CGPoint, canvasSize: CGSize) -> CGPoint {
        let x = verticalSnapTargets(canvasSize).first { abs(raw.x - $0) <= snapThreshold } ?? raw.x
        let y = horizontalSnapTargets(canvasSize).first { abs(raw.y - $0) <= snapThreshold } ?? raw.y
        return CGPoint(x: x, y: y)
    }

    func handleDragEnded(id: UUID, center: CGPoint, canvasSize: CGSize) {
        if trashRect(in: canvasSize).contains(center) {
            deleteSticker(id)
        }
        draggingID = nil
        isOverTrash = false
        verticalGuideX = nil
        horizontalGuideY = nil
    }

    // MARK: - Totals injection

    /// Compute this-week aggregates (Monday-based, local week) from the full
    /// workout history and publish them as Totals stat stickers.
    func injectWeeklyTotals(from workouts: [Workout], now: Date = Date()) {
        let calendar = WeekConfiguration.calendar()
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else {
            weeklyTotalStats = []
            return
        }
        let weekWorkouts = workouts.filter { $0.date >= week.start && $0.date < week.end }
        guard !weekWorkouts.isEmpty else {
            weeklyTotalStats = []
            return
        }

        let steps = weekWorkouts.reduce(0) { $0 + $1.steps }
        let count = weekWorkouts.count
        let duration = weekWorkouts.reduce(0.0) { $0 + $1.duration }
        let vertical = weekWorkouts.reduce(0.0) {
            $0 + $1.totalVerticalClimb(stepHeight: stepHeight, measurementSystem: measurementSystem)
        }

        var stats: [ResolvedShareStat] = []
        if steps > 0 {
            stats.append(ResolvedShareStat(kind: .totals, label: "STEPS THIS WEEK",
                                           value: steps.formatted(.number.grouping(.automatic))))
        }
        stats.append(ResolvedShareStat(kind: .totals, label: "WORKOUTS THIS WEEK", value: "\(count)"))
        stats.append(ResolvedShareStat(kind: .totals, label: "TIME THIS WEEK", value: Self.durationText(duration)))
        if vertical > 0 {
            let v = vertical.formatted(.number.precision(.fractionLength(vertical < 100 ? 1 : 0)))
            stats.append(ResolvedShareStat(kind: .totals, label: "VERTICAL THIS WEEK",
                                           value: "\(v) \(measurementSystem.distanceAbbreviation)"))
        }
        weeklyTotalStats = stats
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
