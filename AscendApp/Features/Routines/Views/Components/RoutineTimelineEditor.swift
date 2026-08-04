import SwiftUI

/// The routine builder's hero surface. The timeline is the routine: every block carries its
/// own level and duration, and five gestures author it - tap to select, drag up for the
/// level, drag sideways for the time, long-press to reorder, and + below to add.
struct RoutineTimelineEditor: View {
    let intervals: [RoutineInterval]
    let selectedIntervalId: UUID?
    var plotHeight: CGFloat = 210

    let onSelect: (UUID) -> Void
    let onSetLevel: (UUID, Int) -> Void
    let onSetDuration: (UUID, TimeInterval) -> Void
    let onAdjustLevel: (UUID, Int) -> Void
    let onAdjustDuration: (UUID, Int) -> Void
    let onCycleStepType: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onMove: (Int, Int) -> Void
    let onInteractingChange: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var adjustSession: AdjustSession?
    @State private var reorderSession: ReorderSession?
    @State private var plotWidth: CGFloat = 0

    private static let plotCoordinateSpace = "routine-timeline-plot"

    var body: some View {
        VStack(spacing: 0) {
            if intervals.isEmpty {
                ghostPlot
                emptyState
            } else {
                plot
                ruler
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.jetLighter.opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(RoutineIntervalVoiceOver.timelineLabel)
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            resetInteraction()
        }
        .onDisappear {
            resetInteraction()
        }
    }

    // MARK: - Plot

    private var plot: some View {
        GeometryReader { proxy in
            // Widths are solved in the same layout pass they are drawn in; `plotWidth` is
            // only kept so a drag can convert finger travel into 30-second steps.
            let widths = RoutineTimelineLayout.blockWidths(
                durations: intervals.map(\.duration),
                availableWidth: proxy.size.width
            )

            HStack(alignment: .bottom, spacing: RoutineTimelineLayout.blockSpacing) {
                ForEach(Array(intervals.enumerated()), id: \.element.id) { index, interval in
                    blockView(
                        interval: interval,
                        index: index,
                        width: widths[safe: index] ?? 0,
                        widths: widths
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .onAppear { plotWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, width in plotWidth = width }
        }
        .frame(height: plotHeight)
        .coordinateSpace(.named(Self.plotCoordinateSpace))
        .animation(resizeAnimation, value: intervals)
    }

    /// A routine has a silhouette before you own one.
    private var ghostPlot: some View {
        GeometryReader { proxy in
            let widths = RoutineTimelineLayout.blockWidths(
                durations: Self.ghostShape.map(\.width),
                availableWidth: proxy.size.width
            )

            HStack(alignment: .bottom, spacing: RoutineTimelineLayout.blockSpacing) {
                ForEach(Array(Self.ghostShape.enumerated()), id: \.offset) { index, shape in
                    UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous)
                        .fill(.white.opacity(0.045))
                        .frame(width: widths[safe: index] ?? 0, height: plotHeight * shape.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: plotHeight)
        .accessibilityHidden(true)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Nothing to climb yet.")
                .font(.montserratBold(size: 16))
                .foregroundStyle(.white)

            Text("Add your first interval.")
                .font(.montserratMedium(size: 13))
                .foregroundStyle(Color.customGray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }

    private var ruler: some View {
        let ticks = RoutineTimelineRuler.ticks(totalDuration: totalDuration)

        return GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(Array(ticks.enumerated()), id: \.element.id) { index, tick in
                    Text(tick.text)
                        .font(.montserratSemiBold(size: 9))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.28))
                        .fixedSize()
                        // The label indexes the blocks above it, so it is placed at its own
                        // fraction of the strip. The guide moves the label's anchor point onto
                        // that fraction: the first tick hangs off its leading edge and the last
                        // off its trailing one, so neither end runs outside the plot.
                        .alignmentGuide(.leading) { dimensions in
                            dimensions.width * tickAnchor(index: index, count: ticks.count)
                                - proxy.size.width * tick.fraction
                        }
                }
            }
        }
        .frame(height: 12)
        .padding(.top, 6)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.07))
                .frame(height: 1)
        }
        .padding(.top, 8)
        .accessibilityHidden(true)
    }

    // MARK: - Block

    private func blockView(
        interval: RoutineInterval,
        index: Int,
        width: CGFloat,
        widths: [CGFloat]
    ) -> some View {
        let level = interval.resolvedLevel
        let height = plotHeight * RoutineIntervalScale.heightFraction(forLevel: level)
        let isSelected = interval.id == selectedIntervalId
        let isGrabbed = reorderSession?.id == interval.id
        let cornerRadius: CGFloat = isSelected || isGrabbed ? 4 : 3

        return ZStack(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: cornerRadius,
                bottomLeadingRadius: isSelected || isGrabbed ? cornerRadius : 0,
                bottomTrailingRadius: isSelected || isGrabbed ? cornerRadius : 0,
                topTrailingRadius: cornerRadius,
                style: .continuous
            )
            .fill(blockColor(forLevel: level))

            blockLabel(interval: interval, width: width)

            if let movementLabel = movementLabel(for: interval),
               RoutineTimelineLayout.showsMovementLabel(blockWidth: width, blockHeight: height) {
                Text(movementLabel)
                    .font(.montserratBold(size: 8))
                    .foregroundStyle(.black.opacity(0.58))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 6)
            }

            if isSelected, !isGrabbed {
                grip
            }
        }
        .frame(width: width, height: height)
        .overlay {
            if isSelected || isGrabbed {
                // Offset by 1pt into a 3pt gap, so the outline never crosses the neighbour it
                // sits beside - which it does at the width floor, where blocks are adjacent.
                RoundedRectangle(cornerRadius: cornerRadius + 1, style: .continuous)
                    .stroke(.white.opacity(0.85), lineWidth: 1.5)
                    .padding(-1)
            }
        }
        // Flatten first: an unflattened `shadow` reaches every leaf, and the block's own
        // label ends up casting a smudge across the fill behind it.
        .compositingGroup()
        .shadow(
            color: isGrabbed ? .black.opacity(0.88) : (isSelected ? .black.opacity(0.65) : .clear),
            radius: isGrabbed ? 20 : (isSelected ? 11 : 0),
            y: isGrabbed ? 22 : (isSelected ? 10 : 0)
        )
        // The lift is the only vertical move a block ever makes, and it is undone on the drop -
        // height is the level now, so a block resting off the baseline would draw a lie.
        .rotationEffect(.degrees(isGrabbed ? -1.5 : 0), anchor: .bottom)
        .offset(x: horizontalOffset(at: index, widths: widths), y: isGrabbed ? -18 : 0)
        .zIndex(isGrabbed ? 3 : (isSelected ? 2 : 1))
        .contentShape(.rect)
        .onTapGesture {
            withAnimation(RoutineTimelineMotion.selection(reduceMotion: reduceMotion)) {
                onSelect(interval.id)
            }
            HapticsManager.shared.trigger(.selection)
        }
        .highPriorityGesture(blockGesture(interval: interval, index: index, widths: widths))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RoutineIntervalVoiceOver.label(position: index + 1, count: intervals.count))
        .accessibilityValue(RoutineIntervalVoiceOver.value(for: interval))
        .accessibilityHint(RoutineIntervalVoiceOver.levelHint)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onAdjustLevel(interval.id, 1)
            case .decrement:
                onAdjustLevel(interval.id, -1)
            @unknown default:
                break
            }
        }
        .accessibilityAction(named: Text(RoutineIntervalVoiceOver.Action.addTime)) {
            onAdjustDuration(interval.id, 1)
        }
        .accessibilityAction(named: Text(RoutineIntervalVoiceOver.Action.subtractTime)) {
            onAdjustDuration(interval.id, -1)
        }
        .accessibilityAction(named: Text(RoutineIntervalVoiceOver.Action.changeStepType)) {
            onCycleStepType(interval.id)
        }
        .accessibilityAction(named: Text(RoutineIntervalVoiceOver.Action.moveEarlier)) {
            onMove(index, index - 1)
        }
        .accessibilityAction(named: Text(RoutineIntervalVoiceOver.Action.moveLater)) {
            onMove(index, index + 1)
        }
        .accessibilityAction(named: Text(RoutineIntervalVoiceOver.Action.delete)) {
            onDelete(interval.id)
        }
    }

    private func blockLabel(interval: RoutineInterval, width: CGFloat) -> some View {
        VStack(spacing: 1) {
            Text("\(interval.resolvedLevel)")
                .font(.montserratBold(size: 14))
                .tracking(-0.3)
                .foregroundStyle(.black.opacity(0.80))

            if RoutineTimelineLayout.showsDurationClock(blockWidth: width) {
                Text(interval.durationClockLabel)
                    .font(.montserratSemiBold(size: 10))
                    .foregroundStyle(.black.opacity(0.52))
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .padding(.top, 7)
    }

    private var grip: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(isAdjustingDuration ? Color.accent : .white)
            .frame(width: 6, height: 34)
            .shadow(color: .black.opacity(0.7), radius: 4, y: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, 3)
            .allowsHitTesting(false)
    }

    // MARK: - Gestures

    private func blockGesture(
        interval: RoutineInterval,
        index: Int,
        widths: [CGFloat]
    ) -> some Gesture {
        // A short hold with almost no travel is the reorder. Anything that moves first is a
        // level or a time edit, so a deliberate one-level nudge never lifts the block.
        let reorder = LongPressGesture(minimumDuration: 0.35, maximumDistance: 4)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.plotCoordinateSpace)))
            .onChanged { value in
                guard case .second(_, let drag) = value else { return }

                if RoutineTimelineGesture.startsNewSession(
                    sessionId: reorderSession?.id,
                    sessionStartLocation: reorderSession?.startLocation,
                    intervalId: interval.id,
                    startLocation: drag?.startLocation
                ) {
                    beginReorder(interval: interval, index: index, startLocation: drag?.startLocation)
                } else if reorderSession?.startLocation == nil {
                    reorderSession?.startLocation = drag?.startLocation
                }

                guard let drag else { return }
                updateReorder(translationX: drag.translation.width, widths: widths)
            }
            .onEnded { _ in
                endReorder()
            }

        let adjust = DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.plotCoordinateSpace))
            .onChanged { value in
                if RoutineTimelineGesture.startsNewSession(
                    sessionId: adjustSession?.id,
                    sessionStartLocation: adjustSession?.startLocation,
                    intervalId: interval.id,
                    startLocation: value.startLocation
                ) {
                    beginAdjust(interval: interval, index: index, startLocation: value.startLocation)
                }
                updateAdjust(translation: value.translation)
            }
            .onEnded { _ in
                endAdjust()
            }

        return reorder.exclusively(before: adjust)
    }

    private func beginReorder(interval: RoutineInterval, index: Int, startLocation: CGPoint?) {
        adjustSession = nil
        withAnimation(RoutineTimelineMotion.selection(reduceMotion: reduceMotion)) {
            onSelect(interval.id)
            reorderSession = ReorderSession(
                id: interval.id,
                startLocation: startLocation,
                sourceIndex: index,
                destinationIndex: index,
                translationX: 0
            )
        }
        HapticsManager.shared.trigger(.mediumImpact)
        onInteractingChange(true)
    }

    private func updateReorder(translationX: CGFloat, widths: [CGFloat]) {
        guard var session = reorderSession else { return }

        session.translationX = translationX

        let originX = RoutineTimelineLayout.blockOriginX(at: session.sourceIndex, widths: widths)
        let width = widths[safe: session.sourceIndex] ?? 0
        let destination = RoutineTimelineLayout.reorderDestinationIndex(
            draggedIndex: session.sourceIndex,
            draggedCenterX: originX + width / 2 + translationX,
            widths: widths
        )

        if destination != session.destinationIndex {
            session.destinationIndex = destination
            HapticsManager.shared.trigger(.lightImpact)
            withAnimation(RoutineTimelineMotion.reorder(reduceMotion: reduceMotion)) {
                reorderSession = session
            }
        } else {
            reorderSession = session
        }
    }

    private func endReorder() {
        guard let session = reorderSession else { return }

        withAnimation(RoutineTimelineMotion.reorder(reduceMotion: reduceMotion)) {
            onMove(session.sourceIndex, session.destinationIndex)
            reorderSession = nil
        }
        HapticsManager.shared.trigger(.lightImpact)
        onInteractingChange(false)
    }

    private func beginAdjust(interval: RoutineInterval, index: Int, startLocation: CGPoint) {
        reorderSession = nil
        // The step is measured against the routine as it was when the finger landed, so the
        // mapping cannot drift under the drag it is driving.
        adjustSession = AdjustSession(
            id: interval.id,
            startLocation: startLocation,
            axis: nil,
            startLevel: interval.resolvedLevel,
            startDuration: interval.duration,
            lastLevel: interval.resolvedLevel,
            lastDuration: interval.duration,
            pointsPerDurationStep: RoutineTimelineLayout.pointsPerDurationStep(
                contentWidth: plotWidth - RoutineTimelineLayout.blockSpacing * CGFloat(max(intervals.count - 1, 0)),
                totalDuration: totalDuration
            )
        )

        if interval.id != selectedIntervalId {
            withAnimation(RoutineTimelineMotion.selection(reduceMotion: reduceMotion)) {
                onSelect(interval.id)
            }
        }
        onInteractingChange(true)
    }

    private func updateAdjust(translation: CGSize) {
        guard var session = adjustSession else { return }

        if session.axis == nil {
            session.axis = abs(translation.height) > abs(translation.width) ? .vertical : .horizontal
        }

        switch session.axis {
        case .some(.vertical):
            let pointsPerLevel = RoutineTimelineLayout.pointsPerLevel(plotHeight: plotHeight)
            let level = SPMMappingService.clampedLevel(
                session.startLevel + Int((-translation.height / pointsPerLevel).rounded())
            )

            if level != session.lastLevel {
                session.lastLevel = level
                onSetLevel(session.id, level)
                HapticsManager.shared.trigger(.lightImpact)
            }

        case .some(.horizontal):
            let steps = Int((translation.width / session.pointsPerDurationStep).rounded())
            let duration = RoutineIntervalScale.snappedDuration(
                session.startDuration + Double(steps) * RoutineIntervalScale.durationStep
            )

            if duration != session.lastDuration {
                session.lastDuration = duration
                onSetDuration(session.id, duration)
                HapticsManager.shared.trigger(.lightImpact)
            }

        case .none:
            break
        }

        adjustSession = session
    }

    private func endAdjust() {
        guard adjustSession != nil else { return }

        withAnimation(RoutineTimelineMotion.resize(reduceMotion: reduceMotion)) {
            adjustSession = nil
        }
        onInteractingChange(false)
    }

    /// The one path back to rest. A gesture the system cancels - the sheet moving, the app
    /// backgrounding, the editor going away - never delivers `onEnded`, and an interaction
    /// left latched on would keep swipe-to-dismiss disabled for the rest of the sheet.
    private func resetInteraction() {
        withAnimation(RoutineTimelineMotion.resize(reduceMotion: reduceMotion)) {
            adjustSession = nil
            reorderSession = nil
        }
        onInteractingChange(false)
    }

    // MARK: - Derived

    private var totalDuration: TimeInterval {
        intervals.reduce(0) { $0 + $1.duration }
    }

    private var isAdjustingDuration: Bool {
        adjustSession?.axis == .horizontal
    }

    /// While a block is lifted its neighbours part rather than the list resequencing, so
    /// nothing renumbers under the finger.
    private func horizontalOffset(at index: Int, widths: [CGFloat]) -> CGFloat {
        guard let session = reorderSession else { return 0 }

        if index == session.sourceIndex {
            return session.translationX
        }

        let slot = (widths[safe: session.sourceIndex] ?? 0) + RoutineTimelineLayout.blockSpacing

        if session.destinationIndex <= index, index < session.sourceIndex {
            return slot
        }
        if session.sourceIndex < index, index <= session.destinationIndex {
            return -slot
        }
        return 0
    }

    private var resizeAnimation: Animation? {
        // A live drag tracks the finger; everything else springs.
        adjustSession == nil ? RoutineTimelineMotion.resize(reduceMotion: reduceMotion) : nil
    }

    private func blockColor(forLevel level: Int) -> Color {
        RoutineIntervalScale.color(forLevel: level, colorScheme: colorScheme)
    }

    /// The first tick hangs off its leading edge and the last off its trailing one; everything
    /// between is centred on the minute it names.
    private func tickAnchor(index: Int, count: Int) -> Double {
        if index == 0 { return 0 }
        if index == count - 1 { return 1 }
        return 0.5
    }

    private func movementLabel(for interval: RoutineInterval) -> String? {
        let stepType = RoutineStepTypeOption.from(modifiers: interval.modifiers)
        guard stepType != .standard else { return nil }
        return stepType.displayName.uppercased()
    }

    private static let ghostShape: [GhostBar] = [
        GhostBar(width: 16, height: 0.26),
        GhostBar(width: 22, height: 0.42),
        GhostBar(width: 22, height: 0.60),
        GhostBar(width: 16, height: 0.36),
        GhostBar(width: 22, height: 0.50)
    ]

    private struct GhostBar: Hashable {
        let width: Double
        let height: Double
    }

    private struct AdjustSession: Equatable {
        let id: UUID
        let startLocation: CGPoint
        var axis: Axis?
        let startLevel: Int
        let startDuration: TimeInterval
        var lastLevel: Int
        var lastDuration: TimeInterval
        let pointsPerDurationStep: CGFloat
    }

    private struct ReorderSession: Equatable {
        let id: UUID
        var startLocation: CGPoint?
        let sourceIndex: Int
        var destinationIndex: Int
        var translationX: CGFloat
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview("Five intervals") {
    @Previewable @State var selected: UUID?

    let intervals = [
        RoutineInterval(duration: 180, intensityValue: 16, order: 0),
        RoutineInterval(duration: 240, intensityValue: 7, order: 1),
        RoutineInterval(duration: 240, intensityValue: 6, modifiers: .backward, order: 2),
        RoutineInterval(duration: 180, intensityValue: 20, order: 3),
        RoutineInterval(duration: 240, intensityValue: 4, order: 4)
    ]

    RoutineTimelineEditor(
        intervals: intervals,
        selectedIntervalId: selected ?? intervals[0].id,
        onSelect: { selected = $0 },
        onSetLevel: { _, _ in },
        onSetDuration: { _, _ in },
        onAdjustLevel: { _, _ in },
        onAdjustDuration: { _, _ in },
        onCycleStepType: { _ in },
        onDelete: { _ in },
        onMove: { _, _ in },
        onInteractingChange: { _ in }
    )
    .padding(20)
    .background(Color.black)
    .preferredColorScheme(.dark)
}

#Preview("Empty") {
    RoutineTimelineEditor(
        intervals: [],
        selectedIntervalId: nil,
        onSelect: { _ in },
        onSetLevel: { _, _ in },
        onSetDuration: { _, _ in },
        onAdjustLevel: { _, _ in },
        onAdjustDuration: { _, _ in },
        onCycleStepType: { _ in },
        onDelete: { _ in },
        onMove: { _, _ in },
        onInteractingChange: { _ in }
    )
    .padding(20)
    .background(Color.black)
    .preferredColorScheme(.dark)
}
