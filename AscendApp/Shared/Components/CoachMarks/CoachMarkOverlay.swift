import SwiftUI

/// One shared spotlight and card renderer for contextual walkthroughs.
struct CoachMarkOverlay: View {
    let presentation: CoachMarkPresentation
    let targetRect: CGRect?
    let containerSize: CGSize
    let onNext: () -> Void
    let onSkip: () -> Void

    @AccessibilityFocusState private var headingIsFocused: Bool

    private let visualMargin: CGFloat = 20

    private var spotlightRect: CGRect? {
        guard let targetRect else { return nil }
        let expanded = targetRect.insetBy(dx: -4, dy: -4)
        let visibleBounds = CGRect(origin: .zero, size: containerSize).insetBy(dx: 1, dy: 1)
        let clamped = expanded.intersection(visibleBounds)
        return clamped.isNull || clamped.isEmpty ? nil : clamped
    }

    private var placesCardBelowTarget: Bool {
        availableHeightBelowTarget >= availableHeightAboveTarget
    }

    private var availableHeightAboveTarget: CGFloat {
        guard let spotlightRect else { return 0 }
        return max(0, spotlightRect.minY - 24 - visualMargin)
    }

    private var availableHeightBelowTarget: CGFloat {
        guard let spotlightRect else { return max(0, containerSize.height - visualMargin * 2) }
        return max(0, containerSize.height - visualMargin - spotlightRect.maxY - 24)
    }

    private var cardRegion: CGRect {
        let width = max(0, containerSize.width - visualMargin * 2)
        guard let spotlightRect else {
            return CGRect(
                x: visualMargin,
                y: visualMargin,
                width: width,
                height: max(0, containerSize.height - visualMargin * 2)
            )
        }

        if placesCardBelowTarget {
            let minY = spotlightRect.maxY + 24
            return CGRect(
                x: visualMargin,
                y: minY,
                width: width,
                height: max(0, containerSize.height - visualMargin - minY)
            )
        }

        return CGRect(
            x: visualMargin,
            y: visualMargin,
            width: width,
            height: availableHeightAboveTarget
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            dimmedBackdrop

            if let spotlightRect, presentation.drawsSpotlightRing {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.accent, lineWidth: 2)
                    .frame(width: spotlightRect.width, height: spotlightRect.height)
                    .offset(x: spotlightRect.minX, y: spotlightRect.minY)
                    .allowsHitTesting(false)
            }

            // Pinned to the edge of the region that touches the spotlight, so the card sits
            // beside the control it names instead of drifting to the middle of the free space.
            card
                .frame(
                    width: cardRegion.width,
                    height: cardRegion.height,
                    alignment: placesCardBelowTarget ? .top : .bottom
                )
                .offset(x: cardRegion.minX, y: cardRegion.minY)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, escape)
        .task(id: presentation.title) {
            headingIsFocused = true
        }
    }

    private var dimmedBackdrop: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.66))

            if let spotlightRect {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .frame(width: spotlightRect.width, height: spotlightRect.height)
                    .offset(x: spotlightRect.minX, y: spotlightRect.minY)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
        .contentShape(.rect)
        .onTapGesture(perform: onNext)
        .accessibilityHidden(true)
    }

    /// Sized against `cardRegion`, which is only meaningful when `containerSize` is the definite
    /// geometry a presenting screen measured with `GeometryReader`. Both shipped hosts pass one.
    /// Flattened standalone through `ImageRenderer` there is no such proposal, so the card
    /// stretches and drops its heading - an artifact of the renderer, not of the screen. Evidence
    /// for this card is therefore hosted in a real window; do not reshape the layout below to
    /// make a standalone PNG look right.
    private var card: some View {
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 0) {
                copy
                actions
            }
            .padding(18)

            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    copy
                }
                .scrollBounceBehavior(.basedOnSize)
                actions
            }
            .padding(18)
            .frame(maxHeight: cardRegion.height)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.09, green: 0.09, blue: 0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Coach mark card")
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(presentation.title)
                .font(.montserratBold(size: 17))
                .foregroundStyle(.white)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("Coach mark heading")
                .accessibilityFocused($headingIsFocused)

            Text(presentation.message)
                .font(.montserratMedium(size: 13.5))
                .foregroundStyle(.white.opacity(0.55))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                progressDots
                    .frame(maxWidth: .infinity, alignment: .leading)
                actionButtons
            }

            VStack(alignment: .leading, spacing: 4) {
                progressDots
                actionButtons
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<presentation.stepCount, id: \.self) { step in
                Circle()
                    .fill(step == presentation.stepIndex ? Color.accent : .white.opacity(0.22))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            if presentation.showsSkip {
                Button(action: onSkip) {
                    Text("Skip")
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                    .buttonStyle(.plain)
            }

            Button(action: onNext) {
                Text(presentation.primaryActionTitle)
                    .font(.montserratBold(size: 14))
                    .foregroundStyle(Color.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
                .buttonStyle(.plain)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func escape() {
        if presentation.showsSkip {
            onSkip()
        } else {
            onNext()
        }
    }
}

#Preview("Walkthrough") {
    ZStack {
        Color.black
        CoachMarkOverlay(
            presentation: CoachMarkPresentation(
                title: "Drag a block.",
                message: "Up and down for the level. Left and right for the time.",
                stepCount: 3,
                stepIndex: 0,
                primaryActionTitle: "Next",
                showsSkip: true
            ),
            targetRect: CGRect(x: 20, y: 240, width: 362, height: 212),
            containerSize: CGSize(width: 402, height: 874),
            onNext: {},
            onSkip: {}
        )
    }
    .frame(width: 402, height: 874)
    .preferredColorScheme(.dark)
}
