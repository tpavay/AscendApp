import SwiftUI

/// The draggable sheet over the globe.
///
/// Owns the drag and the settle between detents; the caller owns which detent is
/// resting through `detent` and hears each settle through `setDetent`. `dragDetents`
/// is the set a drag can come to rest on: Browse never drags down to `compact`
/// (a pin tap puts it there), Home's sheet does.
struct ClimbBrowseDrawer<Content: View>: View {
    @Binding var detent: BrowseSheetDetent

    let containerHeight: CGFloat
    let topCoverageInset: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    let dragDetents: [BrowseSheetDetent]
    let accessibilityLabel: String
    let accessibilityHint: String
    let setDetent: (BrowseSheetDetent) -> Void
    let content: Content

    @State private var currentOffset: CGFloat?
    @State private var dragStartOffset: CGFloat?

    init(
        detent: Binding<BrowseSheetDetent>,
        containerHeight: CGFloat,
        topCoverageInset: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat,
        dragDetents: [BrowseSheetDetent] = [.medium, .expanded],
        accessibilityLabel: String = "Browse climbs drawer",
        accessibilityHint: String = "Drag to expand or collapse browse controls",
        setDetent: @escaping (BrowseSheetDetent) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self._detent = detent
        self.containerHeight = containerHeight
        self.topCoverageInset = topCoverageInset
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.dragDetents = dragDetents.sorted()
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.setDetent = setDetent
        self.content = content()
    }

    var body: some View {
        draggableSurface
            .frame(maxWidth: .infinity)
            .frame(height: expandedHeight, alignment: .top)
            .background(drawerBackground)
            .overlay(alignment: .top) {
                drawerShape
                    .stroke(.white.opacity(0.09), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .offset(y: activeOffset)
            .onAppear {
                currentOffset = restingOffset
            }
            .onChange(of: restingOffset) { _, newOffset in
                guard dragStartOffset == nil else { return }
                withAnimation(sheetSpring) {
                    currentOffset = newOffset
                }
            }
            .ignoresSafeArea(.container, edges: [.top, .bottom])
    }

    @ViewBuilder
    private var draggableSurface: some View {
        if detent == .expanded {
            drawerSurface
        } else {
            drawerSurface
                .gesture(drawerDragGesture)
        }
    }

    private var drawerSurface: some View {
        VStack(spacing: 0) {
            drawerGrabber
                .padding(.top, detent == .expanded ? expandedTopPadding : 0)
            content
        }
    }

    private var expandedTopPadding: CGFloat {
        max(8, topInset - 24)
    }

    @ViewBuilder
    private var drawerGrabber: some View {
        let handle = VStack(spacing: 0) {
            Capsule(style: .continuous)
                .fill(.white.opacity(0.34))
                .frame(width: 44, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if detent == .compact {
                setDetent(.medium)
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)

        if detent == .expanded {
            handle.gesture(drawerDragGesture)
        } else {
            handle
        }
    }

    private var drawerBackground: some View {
        drawerShape
            .fill(Color.black.opacity(0.9))
            .background(
                drawerShape
                    .fill(Color.night.opacity(0.8))
            )
    }

    private var drawerShape: UnevenRoundedRectangle {
        let topCornerRadius: CGFloat = detent == .expanded ? 0 : 24

        return UnevenRoundedRectangle(
            topLeadingRadius: topCornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: topCornerRadius,
            style: .continuous
        )
    }

    private var expandedHeight: CGFloat {
        BrowseSheetDetent.expanded.height(
            containerHeight: containerHeight,
            topCoverageInset: topCoverageInset,
            topInset: topInset,
            bottomInset: bottomInset
        )
    }

    private var activeOffset: CGFloat {
        return currentOffset ?? restingOffset
    }

    private var restingOffset: CGFloat {
        detent.offset(
            containerHeight: containerHeight,
            topCoverageInset: topCoverageInset,
            topInset: topInset,
            bottomInset: bottomInset
        )
    }

    private var sheetSpring: Animation {
        .interactiveSpring(response: 0.34, dampingFraction: 0.88)
    }

    private var drawerDragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if dragStartOffset == nil {
                    dragStartOffset = activeOffset
                }

                let baseOffset = dragStartOffset ?? restingOffset
                let nextOffset = BrowseSheetDetent.clampedOffset(
                    baseOffset + value.translation.height,
                    containerHeight: containerHeight,
                    topCoverageInset: topCoverageInset,
                    topInset: topInset,
                    bottomInset: bottomInset
                )

                var transaction = Transaction()
                transaction.disablesAnimations = true
                transaction.animation = nil

                withTransaction(transaction) {
                    currentOffset = nextOffset
                }
            }
            .onEnded { value in
                settle(after: value)
            }
    }

    private func settle(after value: DragGesture.Value) {
        let velocity = value.predictedEndTranslation.height - value.translation.height
        let velocityThreshold: CGFloat = 300
        let releaseOffset = currentOffset ?? restingOffset
        let predictedOffset = BrowseSheetDetent.clampedOffset(
            (dragStartOffset ?? restingOffset) + value.predictedEndTranslation.height,
            containerHeight: containerHeight,
            topCoverageInset: topCoverageInset,
            topInset: topInset,
            bottomInset: bottomInset
        )
        let targetDetent: BrowseSheetDetent

        if velocity < -velocityThreshold ||
            value.predictedEndTranslation.height < -80 ||
            value.translation.height < -48 {
            targetDetent = detent.nextUp(in: dragDetents)
        } else if velocity > velocityThreshold ||
            value.predictedEndTranslation.height > 80 ||
            value.translation.height > 48 {
            targetDetent = detent.nextDown(in: dragDetents)
        } else {
            targetDetent = BrowseSheetDetent.nearest(
                to: predictedOffset == restingOffset ? releaseOffset : predictedOffset,
                among: dragDetents,
                containerHeight: containerHeight,
                topCoverageInset: topCoverageInset,
                topInset: topInset,
                bottomInset: bottomInset
            )
        }

        if targetDetent != detent {
            HapticsManager.shared.trigger(.selection)
        }

        dragStartOffset = nil

        withAnimation(sheetSpring) {
            currentOffset = targetDetent.offset(
                containerHeight: containerHeight,
                topCoverageInset: topCoverageInset,
                topInset: topInset,
                bottomInset: bottomInset
            )
        }

        setDetent(targetDetent)
    }
}
