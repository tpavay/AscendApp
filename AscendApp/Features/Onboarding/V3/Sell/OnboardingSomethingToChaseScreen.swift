import SwiftUI

/// 04 Always something to chase next: the month's gear, popping in and bobbing, each piece labelled
/// with what it takes, over the reasons to keep climbing. The gear is read from the hosted unlock
/// catalogue, so it is whatever event is on (or the last one that finished), never a season written
/// into the build.
struct OnboardingSomethingToChaseScreen: View {
    let coordinator: OnboardingV3Coordinator
    /// Tests hand in a catalogue and a day; the screen reads the real catalogue and today.
    let selection: SellGearSelection?

    init(coordinator: OnboardingV3Coordinator, catalog: UnlockCatalog? = nil, today: Date = .now) {
        self.coordinator = coordinator
        let catalog = catalog ?? HostedUnlockCatalogRepository().loadInitialCatalog()
        selection = SellGearSelection(catalog: catalog, today: today)
    }

    var body: some View {
        SellScreenFrame(
            step: .somethingToChase,
            headline: OnboardingHeadline(
                SellScreenCopy.SomethingToChase.headlineLead,
                accentLines: SellScreenCopy.SomethingToChase.headlineAccent,
                accent: .orange
            ),
            message: SellScreenCopy.SomethingToChase.body,
            textDelay: 0.9,
            artMinimumHeight: 250,
            onContinue: coordinator.advance,
            art: {
                if let selection {
                    gear(selection)
                }
            },
            extras: { chips }
        )
        .background(alignment: .top) {
            SellGlow(color: Color(red: 240 / 255, green: 140 / 255, blue: 40 / 255), opacity: 0.24)
                .frame(height: 480)
                .padding(.top, 60)
                .allowsHitTesting(false)
        }
        .trackOnce(screen: .onboardingSomethingToChase)
    }

    // MARK: - Gear

    /// Where each piece sits in the art area, as fractions of it: the centrepiece in the middle and
    /// the others pinned to three corners, each kept wholly inside the area so no label is cut.
    private static let slots: [Slot] = [
        Slot(x: 0.56, anchor: .middle(0.47), size: 0.44, tilt: -4, delay: 0.15),
        Slot(x: 0.2, anchor: .top, size: 0.29, tilt: 6, delay: 0.35),
        Slot(x: 0.8, anchor: .top, size: 0.30, tilt: -8, delay: 0.5),
        Slot(x: 0.2, anchor: .bottom, size: 0.28, tilt: -6, delay: 0.65)
    ]

    private struct Slot {
        enum Anchor {
            case top
            case bottom
            /// The piece's centre, as a fraction of the area's height.
            case middle(Double)
        }

        let x: Double
        let anchor: Anchor
        let size: Double
        let tilt: Double
        let delay: Double
    }

    /// A piece's picture plus its tag, which is up to two lines of 10 to 16 pt type.
    private static func pieceHeight(size: CGFloat) -> CGFloat { size + 6 + 40 }

    private func gear(_ selection: SellGearSelection) -> some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height * 0.9)
            ZStack {
                ForEach(Array(selection.pieces.enumerated()), id: \.element.id) { index, piece in
                    let slot = Self.slots[min(index, Self.slots.count - 1)]
                    let size = side * slot.size
                    let height = Self.pieceHeight(size: size)
                    let halfWidth = max(size, 110) / 2
                    let x = min(max(proxy.size.width * slot.x, halfWidth + 4), proxy.size.width - halfWidth - 4)
                    let y: CGFloat = switch slot.anchor {
                    case .top: height / 2
                    case .bottom: proxy.size.height - height / 2
                    case .middle(let fraction): proxy.size.height * fraction
                    }

                    SellGearPieceView(
                        piece: piece,
                        size: size,
                        tilt: slot.tilt,
                        bobDelay: Double(index) * 0.4,
                        isCenterpiece: index == 0
                    )
                    .onboardingEntrance(style: .pop, delay: slot.delay, duration: 0.55)
                    .position(x: x, y: y)
                }
            }
        }
    }

    // MARK: - Chips

    private var chips: some View {
        ShareChipFlowLayout(spacing: 6) {
            ForEach(SellScreenCopy.SomethingToChase.chips, id: \.self) { title in
                SellChaseChip(
                    title: title,
                    isHighlighted: title == SellScreenCopy.SomethingToChase.highlightedChip
                )
            }
        }
        .padding(.top, 2)
    }
}

private struct SellChaseChip: View {
    let title: String
    let isHighlighted: Bool

    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 12

    /// A chip grows with the text but stops at 32 pt, where the smallest phone still holds
    /// "Achievements" on one line.
    private var effectiveSize: CGFloat { min(size, 32) }

    var body: some View {
        Text(title)
            .font(.custom("Montserrat-ExtraBold", fixedSize: effectiveSize))
            .foregroundStyle(isHighlighted ? OnboardingV3Palette.orange : Color.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isHighlighted ? Color(hex: "2A1806") : OnboardingV3Palette.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isHighlighted ? Color(hex: "5A3A14") : OnboardingV3Palette.chipBorder, lineWidth: 1)
            )
    }
}

/// One piece of gear: its picture, bobbing 10 pt over 3.6 s, and what it takes beneath it. Reduce
/// Motion stops the bob.
private struct SellGearPieceView: View {
    let piece: SellGearSelection.Piece
    let size: CGFloat
    let tilt: Double
    let bobDelay: Double
    let isCenterpiece: Bool

    @OnboardingReduceMotion private var reduceMotion
    @ScaledMetric(relativeTo: .caption2) private var tagSize: CGFloat = 10
    @State private var isUp = false

    /// A tag is a caption on a picture: it grows with the text size but stops at 16 pt, where a
    /// 110 pt column would otherwise break "GOLDEN TURKEY" mid-word.
    private var effectiveTagSize: CGFloat { min(isCenterpiece ? tagSize + 1 : tagSize, 16) }

    var body: some View {
        VStack(spacing: 6) {
            Image(piece.item.shape.thumbnailName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.7), radius: 24, y: 18)
                .rotationEffect(.degrees(tilt))
                .offset(y: isUp ? -SellMotion.gearBobDistance(reduceMotion: reduceMotion) : 0)
                .accessibilityHidden(true)

            Text(isCenterpiece ? "\(piece.name.uppercased()) · \(piece.requirement)" : piece.requirement)
                .font(.custom("Montserrat-ExtraBold", fixedSize: effectiveTagSize))
                .tracking(effectiveTagSize * 0.12)
                .foregroundStyle(isCenterpiece ? OnboardingV3Palette.orange : Color(hex: "9A9A9A"))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: max(size, 110))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(piece.name), \(piece.spokenRequirement)")
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(bobDelay))
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { isUp = true }
        }
    }
}
