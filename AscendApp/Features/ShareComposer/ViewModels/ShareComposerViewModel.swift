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
    let climbName: String?
    let climbRank: Int?
    let climbRankTotal: Int?

    // Editing state
    var background: ShareBackgroundSource?
    var stickers: [ShareStickerInstance] = []
    var selectedID: UUID?

    /// The workout's headline Best Effort, injected from the Best Effort cache
    /// by the view (the resolver can't compute it from the Workout alone).
    var primaryBestEffortStat: ResolvedShareStat?

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
        climbName: String? = nil,
        climbRank: Int? = nil,
        climbRankTotal: Int? = nil,
        initialBackground: ShareBackgroundSource? = nil
    ) {
        self.workout = workout
        self.measurementSystem = measurementSystem
        self.stepHeight = stepHeight
        self.climbName = climbName
        self.climbRank = climbRank
        self.climbRankTotal = climbRankTotal
        self.background = initialBackground
    }

    // MARK: - Stat resolution

    private var resolver: ShareStatResolver {
        ShareStatResolver(
            workout: workout,
            measurementSystem: measurementSystem,
            stepHeight: stepHeight,
            climbName: climbName,
            climbRank: climbRank,
            climbRankTotal: climbRankTotal
        )
    }

    var isClimb: Bool { climbName != nil }

    /// Catalog of stats that have a value for this workout, resolved for display.
    func availableStats() -> [ResolvedShareStat] {
        var stats = resolver.availableKinds().compactMap { resolver.resolve($0) }
        if let primaryBestEffortStat {
            stats.append(primaryBestEffortStat)
        }
        return stats
    }

    func resolve(_ kind: ShareStatStickerKind) -> ResolvedShareStat? {
        if kind == .bestEffort { return primaryBestEffortStat }
        return resolver.resolve(kind)
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
}
