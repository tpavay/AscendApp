import SwiftUI

/// The routine builder's hero surface. The timeline is the routine: every block carries its
/// own level and duration, and five gestures author it - tap to select, drag up for the
/// level, drag sideways for the time, long-press to reorder, and + below to add.
///
/// Past the point where the intervals stop fitting, the whole routine moves to an overview
/// above and the strip below becomes a working window onto it. Fit to width is unchanged; it
/// applies to the window instead of to the routine, so the interval count can never be what
/// puts a block under a fingertip.
struct RoutineTimelineEditor: View {
    let intervals: [RoutineInterval]
    let selectedIntervalId: UUID?
    var plotHeight: CGFloat = 210
    /// The editor owns the threshold, and the screen around it needs to know when it is crossed
    /// so the coach mark can fire the first time.
    var onWindowEngagedChange: (Bool) -> Void = { _ in }

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
    /// Where the climber has put the window, once they have moved it. Until then the window is
    /// derived from the selection, so the strip opens on the right intervals in the pass that
    /// first draws it rather than being corrected a frame later.
    @State private var scrubbedWindowStart: Int?
    /// Non-zero while a lifted block is held past an end of the window, which is the only travel
    /// left once the finger has run out of screen.
    @State private var edgeAdvanceDirection = 0

    // SwiftUI resets gesture state when a gesture ends *or* is cancelled, and a cancelled
    // gesture is the one that never calls `onEnded`. Watching this flag fall is the only
    // report of a cancellation the editor gets.
    @GestureState private var isGestureActive = false

    private static let plotCoordinateSpace = "routine-timeline-plot"

    var body: some View {
        VStack(spacing: 0) {
            if intervals.isEmpty {
                ghostPlot
                emptyState
            } else {
                if isWindowEngaged {
                    overview
                        .padding(.bottom, 12)
                }

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
        // Keyed on the count, not on engagement: the overview arriving because a climber added
        // an interval is a change they made, and the first measurement of the strip is not.
        .animation(RoutineTimelineMotion.resize(reduceMotion: reduceMotion), value: intervals.count)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(RoutineIntervalVoiceOver.timelineLabel)
        .onChange(of: isGestureActive) { _, isActive in
            guard !isActive else { return }
            resetInteraction()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            resetInteraction()
        }
        .onChange(of: isWindowEngaged, initial: true) { _, isEngaged in
            onWindowEngagedChange(isEngaged)
        }
        .onChange(of: selectedIntervalId) { _, id in
            followSelection(id)
        }
        .onChange(of: intervals.count) { _, _ in
            guard scrubbedWindowStart != nil else { return }
            scrubbedWindowStart = visibleRange.lowerBound
        }
        .task(id: edgeAdvanceDirection) {
            await walkWindowWhileHeldAtTheEdge(direction: edgeAdvanceDirection)
        }
        .onDisappear {
            resetInteraction()
        }
    }

    // MARK: - Overview

    /// The whole routine, so choosing what to edit never means losing sight of what you built.
    private var overview: some View {
        RoutineTimelineOverview(
            intervals: intervals,
            visibleRange: visibleRange,
            onScrub: scrubWindow(toLeadingFraction:),
            onStep: stepWindow(by:),
            onScrubbingChange: onInteractingChange
        )
        .routineCoachMarkTarget(.overview)
    }

    // MARK: - Plot

    private var plot: some View {
        GeometryReader { proxy in
            // Widths are solved in the same layout pass they are drawn in, from the same width
            // the range was solved with, so the strip never renders a slice it has not sized.
            let range = RoutineTimelineWindow.visibleRange(
                startIndex: windowStart(availableWidth: proxy.size.width),
                intervalCount: intervals.count,
                availableWidth: proxy.size.width
            )
            let visible = intervals[range]
            let widths = RoutineTimelineLayout.blockWidths(
                durations: visible.map(\.duration),
                availableWidth: proxy.size.width
            )

            HStack(alignment: .bottom, spacing: RoutineTimelineLayout.blockSpacing) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { localIndex, interval in
                    blockView(
                        interval: interval,
                        index: range.lowerBound + localIndex,
                        localIndex: localIndex,
                        width: widths[safe: localIndex] ?? 0,
                        widths: widths,
                        range: range
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        // Measured during layout rather than on appear, so the strip knows how much it holds
        // in the pass that draws it - the overview is decided by this, and a renderer that
        // never runs a lifecycle would otherwise draw a long routine as if it fitted.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { plotWidth = $0 }
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

    /// The ruler describes the strip above it, which is the window once there is one - so a
    /// window that opens six minutes into the routine is labelled from six.
    private var ruler: some View {
        GeometryReader { proxy in
            // Solved from the width that draws it, like the plot above - the two describe the
            // same strip, so they must never be one pass apart about which slice that is.
            let range = RoutineTimelineWindow.visibleRange(
                startIndex: windowStart(availableWidth: proxy.size.width),
                intervalCount: intervals.count,
                availableWidth: proxy.size.width
            )
            let ticks = RoutineTimelineRuler.ticks(
                startTime: elapsedTime(before: range.lowerBound),
                endTime: elapsedTime(before: range.upperBound)
            )

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
        localIndex: Int,
        width: CGFloat,
        widths: [CGFloat],
        range: Range<Int>
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
        .offset(x: horizontalOffset(localIndex: localIndex, widths: widths, range: range), y: isGrabbed ? -18 : 0)
        // The block draws at its own height, but it owns its whole column: the empty plot above
        // a level-1 block is 42pt of nothing, and a finger that lands there means that block.
        .frame(width: width, height: plotHeight, alignment: .bottom)
        .zIndex(isGrabbed ? 3 : (isSelected ? 2 : 1))
        .contentShape(.rect)
        .onTapGesture {
            withAnimation(RoutineTimelineMotion.selection(reduceMotion: reduceMotion)) {
                onSelect(interval.id)
            }
            HapticsManager.shared.trigger(.selection)
        }
        .highPriorityGesture(
            blockGesture(interval: interval, index: index, localIndex: localIndex, widths: widths, range: range)
        )
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
        localIndex: Int,
        widths: [CGFloat],
        range: Range<Int>
    ) -> some Gesture {
        // A short hold with almost no travel is the reorder. Anything that moves first is a
        // level or a time edit, so a deliberate one-level nudge never lifts the block.
        let reorder = LongPressGesture(minimumDuration: 0.35, maximumDistance: 4)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.plotCoordinateSpace)))
            .onChanged { value in
                guard case .second(_, let drag) = value else { return }

                if RoutineTimelineGesture.startsNewSession(
                    sessionId: reorderSession?.id,
                    intervalId: interval.id
                ) {
                    beginReorder(interval: interval, index: index)
                }

                // The long press lifts the block before any drag exists; the finger's grip on
                // it is only knowable once one does.
                guard let drag else { return }
                updateReorder(
                    startLocationX: drag.startLocation.x,
                    locationX: drag.location.x,
                    widths: widths,
                    range: range
                )
            }
            .onEnded { _ in
                endReorder()
            }

        let adjust = DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.plotCoordinateSpace))
            .onChanged { value in
                if RoutineTimelineGesture.startsNewSession(
                    sessionId: adjustSession?.id,
                    intervalId: interval.id
                ) {
                    beginAdjust(interval: interval, range: range)
                }
                updateAdjust(translation: value.translation)
            }
            .onEnded { _ in
                endAdjust()
            }

        return reorder
            .exclusively(before: adjust)
            .updating($isGestureActive) { _, isActive, _ in isActive = true }
    }

    private func beginReorder(interval: RoutineInterval, index: Int) {
        adjustSession = nil

        withAnimation(RoutineTimelineMotion.selection(reduceMotion: reduceMotion)) {
            onSelect(interval.id)
            reorderSession = ReorderSession(
                id: interval.id,
                sourceIndex: index,
                destinationIndex: index
            )
        }
        HapticsManager.shared.trigger(.mediumImpact)
        onInteractingChange(true)
    }

    private func updateReorder(
        startLocationX: CGFloat,
        locationX: CGFloat,
        widths: [CGFloat],
        range: Range<Int>
    ) {
        guard var session = reorderSession else { return }

        session.locationX = locationX

        let localSource = session.sourceIndex - range.lowerBound
        let width = widths[safe: localSource] ?? 0

        // The finger holds the block at the point it grabbed it, so the block stays welded to
        // it however the strip resequences underneath - including when the window walks along.
        let grabOffset = session.grabOffset ?? min(
            max(startLocationX - RoutineTimelineLayout.blockOriginX(at: localSource, widths: widths), 0),
            width
        )
        session.grabOffset = grabOffset

        let centerX = locationX - grabOffset + width / 2
        let destination = range.lowerBound + RoutineTimelineLayout.reorderDestinationIndex(
            draggedIndex: localSource,
            draggedCenterX: centerX,
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

        edgeAdvanceDirection = RoutineTimelineWindow.edgeAdvance(
            draggedCenterX: centerX,
            widths: widths,
            range: range,
            intervalCount: intervals.count
        )
    }

    private func endReorder() {
        guard let session = reorderSession else { return }

        edgeAdvanceDirection = 0
        withAnimation(RoutineTimelineMotion.reorder(reduceMotion: reduceMotion)) {
            onMove(session.sourceIndex, session.destinationIndex)
            reorderSession = nil
        }
        HapticsManager.shared.trigger(.lightImpact)
        onInteractingChange(false)
    }

    /// A block held past the end of the window carries it along, one interval per beat. Without
    /// this a long routine could only ever be reordered inside one window's neighbourhood, and
    /// the finger has no screen left to travel across.
    @MainActor
    private func walkWindowWhileHeldAtTheEdge(direction: Int) async {
        guard direction != 0 else { return }

        while !Task.isCancelled {
            try? await Task.sleep(for: RoutineTimelineWindow.edgeAdvanceInterval)
            guard !Task.isCancelled, reorderSession != nil else { return }
            advanceWindowUnderDrag(direction: direction)
        }
    }

    @MainActor
    private func advanceWindowUnderDrag(direction: Int) {
        guard var session = reorderSession else { return }

        let range = visibleRange
        let target = direction > 0 ? range.upperBound : range.lowerBound - 1
        guard intervals.indices.contains(target) else {
            edgeAdvanceDirection = 0
            return
        }

        withAnimation(RoutineTimelineMotion.reorder(reduceMotion: reduceMotion)) {
            // The pending drop lands, plus one step past the edge, and the window follows the
            // block it is carrying - so the block stays in the same slot under the finger.
            onMove(session.sourceIndex, target)
            session.sourceIndex = target
            session.destinationIndex = target
            reorderSession = session
            scrubbedWindowStart = RoutineTimelineWindow.start(
                bringingIntoView: target,
                from: range.lowerBound,
                intervalCount: intervals.count,
                availableWidth: plotWidth
            )
        }
        HapticsManager.shared.trigger(.lightImpact)
    }

    private func beginAdjust(interval: RoutineInterval, range: Range<Int>) {
        reorderSession = nil
        // The step is measured against the strip as it was when the finger landed, so the
        // mapping cannot drift under the drag it is driving. The strip is the window, so a long
        // routine's blocks stay as responsive as a short one's.
        let visibleDurations = intervals[range].map(\.duration)
        adjustSession = AdjustSession(
            id: interval.id,
            axis: nil,
            startLevel: interval.resolvedLevel,
            startDuration: interval.duration,
            lastLevel: interval.resolvedLevel,
            lastDuration: interval.duration,
            pointsPerDurationStep: RoutineTimelineLayout.pointsPerDurationStep(
                contentWidth: plotWidth - RoutineTimelineLayout.blockSpacing * CGFloat(max(range.count - 1, 0)),
                totalDuration: visibleDurations.reduce(0, +)
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
        edgeAdvanceDirection = 0
        withAnimation(RoutineTimelineMotion.resize(reduceMotion: reduceMotion)) {
            adjustSession = nil
            reorderSession = nil
        }
        onInteractingChange(false)
    }

    // MARK: - Window

    private var isWindowEngaged: Bool {
        RoutineTimelineWindow.isEngaged(intervalCount: intervals.count, availableWidth: plotWidth)
    }

    /// Where the window opens: wherever the climber last dragged it to, or - before they have -
    /// wherever the selected block is.
    private func windowStart(availableWidth: CGFloat) -> Int {
        if let scrubbedWindowStart { return scrubbedWindowStart }

        return RoutineTimelineWindow.start(
            bringingIntoView: selectedIndex ?? 0,
            from: 0,
            intervalCount: intervals.count,
            availableWidth: availableWidth
        )
    }

    private var visibleRange: Range<Int> {
        RoutineTimelineWindow.visibleRange(
            startIndex: windowStart(availableWidth: plotWidth),
            intervalCount: intervals.count,
            availableWidth: plotWidth
        )
    }

    private var selectedIndex: Int? {
        guard let selectedIntervalId else { return nil }
        return intervals.firstIndex { $0.id == selectedIntervalId }
    }

    /// Where an interval starts on the routine's clock.
    private func elapsedTime(before index: Int) -> TimeInterval {
        intervals[..<min(max(index, 0), intervals.count)].reduce(0) { $0 + $1.duration }
    }

    /// Dragging the overview is the only way to move the window by hand.
    private func scrubWindow(toLeadingFraction fraction: Double) {
        let start = RoutineTimelineWindow.start(
            forLeadingFraction: fraction,
            durations: intervals.map(\.duration),
            availableWidth: plotWidth
        )
        guard start != visibleRange.lowerBound else { return }

        scrubbedWindowStart = start
        HapticsManager.shared.trigger(.selection)
    }

    private func stepWindow(by offset: Int) {
        let start = RoutineTimelineWindow.visibleRange(
            startIndex: visibleRange.lowerBound + offset,
            intervalCount: intervals.count,
            availableWidth: plotWidth
        ).lowerBound
        guard start != visibleRange.lowerBound else { return }

        withAnimation(RoutineTimelineMotion.resize(reduceMotion: reduceMotion)) {
            scrubbedWindowStart = start
        }
    }

    /// A block that has just been added, or the neighbour a delete left selected, has to be on
    /// screen: a new block lands Standard at level 1 and exists to be dragged.
    private func followSelection(_ id: UUID?) {
        guard reorderSession == nil else { return }
        guard let id, let index = intervals.firstIndex(where: { $0.id == id }) else { return }

        let current = visibleRange.lowerBound
        let start = RoutineTimelineWindow.start(
            bringingIntoView: index,
            from: current,
            intervalCount: intervals.count,
            availableWidth: plotWidth
        )
        guard start != current else { return }

        withAnimation(RoutineTimelineMotion.resize(reduceMotion: reduceMotion)) {
            scrubbedWindowStart = start
        }
    }

    // MARK: - Derived

    private var isAdjustingDuration: Bool {
        adjustSession?.axis == .horizontal
    }

    /// While a block is lifted its neighbours part rather than the list resequencing, so
    /// nothing renumbers under the finger. The lifted block itself is drawn where the finger
    /// is holding it, which is why the window can move out from under it without it moving.
    private func horizontalOffset(localIndex: Int, widths: [CGFloat], range: Range<Int>) -> CGFloat {
        guard let session = reorderSession else { return 0 }

        let localSource = session.sourceIndex - range.lowerBound
        let localDestination = session.destinationIndex - range.lowerBound

        if localIndex == localSource {
            guard let grabOffset = session.grabOffset else { return 0 }
            let origin = RoutineTimelineLayout.blockOriginX(at: localIndex, widths: widths)
            return session.locationX - grabOffset - origin
        }

        let slot = (widths[safe: localSource] ?? 0) + RoutineTimelineLayout.blockSpacing

        if localDestination <= localIndex, localIndex < localSource {
            return slot
        }
        if localSource < localIndex, localIndex <= localDestination {
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
        var axis: Axis?
        let startLevel: Int
        let startDuration: TimeInterval
        var lastLevel: Int
        var lastDuration: TimeInterval
        let pointsPerDurationStep: CGFloat
    }

    private struct ReorderSession: Equatable {
        let id: UUID
        /// Both are indices into the whole routine, not into the window.
        var sourceIndex: Int
        var destinationIndex: Int
        /// The finger in plot coordinates, and where inside the block it landed. Both stay
        /// unknown between the lift and the first drag, and the block simply rests in place.
        var locationX: CGFloat = 0
        var grabOffset: CGFloat?
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

#Preview("HIIT Sprint - twelve intervals") {
    @Previewable @State var selected: UUID?

    // The shipped, featured template: 1:00 warm-up, ten 0:30 bursts, 1:00 down.
    let levels = [6, 22, 8, 22, 8, 18, 8, 22, 8, 18, 8, 6]
    let intervals = levels.enumerated().map { index, level in
        RoutineInterval(
            duration: index == 0 || index == levels.count - 1 ? 60 : 30,
            intensityValue: level,
            order: index
        )
    }

    RoutineTimelineEditor(
        intervals: intervals,
        selectedIntervalId: selected ?? intervals.first?.id,
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
