import SwiftUI

/// A single placed sticker on the canvas: renders the stat content and owns the
/// simultaneous pan / pinch-scale / rotate gestures plus its selection chrome.
///
/// Position is stored normalized on the instance; this view converts to/from
/// canvas-space. Trash detection, snapping, and guide lines are delegated up to
/// the canvas via closures so this view stays focused on one sticker.
struct ShareStickerView: View {
    @Binding var instance: ShareStickerInstance
    /// Resolved metrics (one for a single sticker, several for a composite).
    let stats: [ResolvedShareStat]
    let climb: Climb?
    let canvasSize: CGSize
    /// Proportional scale (canvasWidth / reference 390) so stickers render at the
    /// same relative size in the editing canvas and the high-res export.
    var canvasScale: CGFloat = 1
    let isSelected: Bool
    /// True while this sticker is being dragged over the trash zone — it shrinks
    /// to preview deletion, then springs back if dragged out.
    var isOverTrash: Bool = false

    let onSelect: () -> Void
    /// Live canvas-space center during a drag (for trash-hover + guide feedback).
    let onDragChanged: (CGPoint) -> Void
    /// Returns a possibly snapped canvas-space center for the given raw center.
    let snapCenter: (CGPoint) -> CGPoint
    /// Final canvas-space center when the drag ends (for trash deletion).
    let onDragEnded: (CGPoint) -> Void

    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var gestureScale: CGFloat = 1
    @GestureState private var gestureRotation: Angle = .zero
    /// Tracks whether rotation is currently inside a 90° snap zone, so the snap
    /// haptic fires once on entry rather than every frame.
    @State private var rotationSnapped = false

    /// Capture window around each 90° multiple where rotation snaps (≈5°).
    private let rotationSnapThreshold = Double.pi / 36

    private var baseCenter: CGPoint {
        CGPoint(x: instance.position.x * canvasSize.width,
                y: instance.position.y * canvasSize.height)
    }

    var body: some View {
        let rawCenter = CGPoint(x: baseCenter.x + dragTranslation.width,
                                y: baseCenter.y + dragTranslation.height)
        // Live magnetic snap: the sticker glues to the active guide line while
        // dragging (not just on release), giving the "sticky" feel.
        let displayCenter = snapCenter(rawCenter)
        // Live rotation snap to 0/90/180/270 so the user can feel alignment.
        let displayRotation = snappedAngle(instance.rotationRadians + gestureRotation.radians)

        ShareStickerVisual(instance: instance, stats: stats, climb: climb)
            .padding(10)
            .scaleEffect(instance.scale * gestureScale * canvasScale * (isOverTrash ? 0.35 : 1))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOverTrash)
            .rotationEffect(.radians(displayRotation))
            .position(displayCenter)
            .gesture(combinedGesture)
            .onTapGesture { onSelect() }
    }

    // MARK: - Rotation snapping

    /// Nearest 90° multiple if within the snap threshold, else the raw angle.
    private func snappedAngle(_ radians: Double) -> Double {
        let quarter = Double.pi / 2
        let nearest = (radians / quarter).rounded() * quarter
        return abs(radians - nearest) <= rotationSnapThreshold ? nearest : radians
    }

    private func isNearRotationSnap(_ radians: Double) -> Bool {
        let quarter = Double.pi / 2
        let nearest = (radians / quarter).rounded() * quarter
        return abs(radians - nearest) <= rotationSnapThreshold
    }

    private var combinedGesture: some Gesture {
        let drag = DragGesture()
            .updating($dragTranslation) { value, state, _ in state = value.translation }
            .onChanged { value in
                onSelect()
                let center = CGPoint(x: baseCenter.x + value.translation.width,
                                     y: baseCenter.y + value.translation.height)
                onDragChanged(center)
            }
            .onEnded { value in
                let raw = CGPoint(x: baseCenter.x + value.translation.width,
                                  y: baseCenter.y + value.translation.height)
                let snapped = snapCenter(raw)
                instance.position = CGPoint(x: snapped.x / canvasSize.width,
                                            y: snapped.y / canvasSize.height)
                onDragEnded(snapped)
            }

        let magnify = MagnifyGesture()
            .updating($gestureScale) { value, state, _ in state = value.magnification }
            .onChanged { _ in onSelect() }
            .onEnded { value in
                instance.scale = max(0.3, min(instance.scale * value.magnification, 6))
            }

        let rotate = RotateGesture()
            .updating($gestureRotation) { value, state, _ in state = value.rotation }
            .onChanged { value in
                onSelect()
                let live = instance.rotationRadians + value.rotation.radians
                let near = isNearRotationSnap(live)
                if near && !rotationSnapped { HapticsManager.shared.trigger(.lightImpact) }
                rotationSnapped = near
            }
            .onEnded { value in
                rotationSnapped = false
                instance.rotationRadians = snappedAngle(instance.rotationRadians + value.rotation.radians)
            }

        return drag.simultaneously(with: magnify).simultaneously(with: rotate)
    }
}
