import SwiftUI

struct RoutineBuilderCoachMarkAnchorKey: PreferenceKey {
    static let defaultValue: [RoutineBuilderCoachMark: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [RoutineBuilderCoachMark: Anchor<CGRect>],
        nextValue: () -> [RoutineBuilderCoachMark: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

extension View {
    /// Marks this view as the thing a coach mark spotlights.
    func routineCoachMarkTarget(_ mark: RoutineBuilderCoachMark) -> some View {
        anchorPreference(key: RoutineBuilderCoachMarkAnchorKey.self, value: .bounds) { anchor in
            [mark: anchor]
        }
    }
}

/// One spotlight and one card. The dim is punched out over the target so the control being
/// described stays legible underneath.
struct RoutineBuilderCoachMarkOverlay: View {
    let mark: RoutineBuilderCoachMark
    let targetRect: CGRect?
    let containerSize: CGSize
    let onNext: () -> Void
    let onSkip: () -> Void

    private var spotlightRect: CGRect? {
        targetRect?.insetBy(dx: -4, dy: -4)
    }

    private var placesCardBelowTarget: Bool {
        guard let spotlightRect, containerSize.height > 0 else { return true }
        return spotlightRect.maxY < containerSize.height * 0.55
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            dimmedBackdrop

            if let spotlightRect {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.accent, lineWidth: 2)
                    .frame(width: spotlightRect.width, height: spotlightRect.height)
                    .offset(x: spotlightRect.minX, y: spotlightRect.minY)
                    .allowsHitTesting(false)
            }

            card
                .padding(.horizontal, 20)
                .padding(.top, placesCardBelowTarget ? (spotlightRect?.maxY ?? 0) + 24 : 0)
                .padding(
                    .bottom,
                    placesCardBelowTarget ? 0 : containerSize.height - (spotlightRect?.minY ?? 0) + 24
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: placesCardBelowTarget ? .top : .bottom
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
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
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(mark.title)
                .font(.montserratBold(size: 17))
                .foregroundStyle(.white)
                .padding(.bottom, 6)

            Text(mark.message)
                .font(.montserratMedium(size: 13.5))
                .foregroundStyle(.white.opacity(0.55))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    ForEach(RoutineBuilderCoachMark.allCases) { step in
                        Circle()
                            .fill(step == mark ? Color.accent : .white.opacity(0.22))
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)

                Button("Skip", action: onSkip)
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(.white.opacity(0.35))
                    .buttonStyle(.plain)

                Button(mark.isLast ? "Done" : "Next", action: onNext)
                    .font(.montserratBold(size: 14))
                    .foregroundStyle(Color.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.09, green: 0.09, blue: 0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
    }
}

#Preview {
    ZStack {
        Color.black
        RoutineBuilderCoachMarkOverlay(
            mark: .timeline,
            targetRect: CGRect(x: 20, y: 240, width: 362, height: 212),
            containerSize: CGSize(width: 402, height: 874),
            onNext: {},
            onSkip: {}
        )
    }
    .frame(width: 402, height: 874)
    .preferredColorScheme(.dark)
}
