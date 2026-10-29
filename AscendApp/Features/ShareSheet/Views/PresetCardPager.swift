import SwiftUI

/// The Presets card carousel, built to the captain's swipe handoff: the row of cards follows the
/// finger one for one, its neighbours slide in with it, and a release springs on from wherever the
/// finger let go. Depth, the page marks and the caption all follow the drag, not just the release.
/// A chosen photograph is framed instead: pinch to scale, drag to reposition, and the layouts
/// page from the marks or a tap on a neighbour.
struct PresetCardPager: View {
    let model: PresetsViewModel

    /// The finger's horizontal travel in the gesture now in flight; zero when none is.
    @State private var drag: CGFloat
    @GestureState private var isDragging = false
    @State private var liveScale: CGFloat = 1
    @State private var liveOffset: CGSize = .zero

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let side = PresetCardView.designSize
    private let lime = Color(shareHex: PresetAccent.lime.hex)

    /// `heldAt` seeds a drag that is already in progress, so a test can photograph the row held
    /// halfway between two cards the way the handoff's frames show it.
    init(model: PresetsViewModel, heldAt drag: CGFloat = 0) {
        self.model = model
        _drag = State(initialValue: drag)
    }

    private var framesPhoto: Bool { model.background == .photo }

    /// The spring a release or a tap settles with: soft with a hair of overshoot, or a plain
    /// ease-out when Reduce Motion is on.
    private var settle: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.86)
    }

    var body: some View {
        let index = model.layoutIndex
        let layouts = model.layouts
        let offset = PresetPagerGeometry.trackedOffset(translation: drag, index: index, count: layouts.count)
        VStack(spacing: 0) {
            track(index: index, layouts: layouts, offset: offset)
            marks(index: index, layouts: layouts, offset: offset)
                .padding(.top, 14)
        }
    }

    // MARK: - Cards

    private func track(index: Int, layouts: [PresetLayout], offset: CGFloat) -> some View {
        let artwork = framedArtwork
        return ZStack {
            ForEach(PresetPagerGeometry.window(index: index, count: layouts.count), id: \.self) { page in
                let signed = PresetPagerGeometry.signedDistance(page: page, index: index, offset: offset)
                let depth = PresetPagerGeometry.depth(signedDistance: signed)
                PresetCardCanvas(
                    model: model.cardModel(for: layouts[page]),
                    artwork: artwork,
                    size: side,
                    contentOffset: reduceMotion ? 0 : -PresetPagerGeometry.parallax * signed
                )
                // Masked here and not inside the card: the exporter renders the same canvas through
                // `ImageRenderer`, which cannot draw the marker's UIKit view.
                .sentryMasked()
                .scaleEffect(depth.scale)
                .opacity(depth.opacity)
                .shadow(color: .black.opacity(0.6 * depth.shadow), radius: 25, x: 0, y: 18)
                .offset(x: signed * PresetPagerGeometry.step)
                .onTapGesture {
                    guard page != index else { return }
                    withAnimation(settle) { model.swipe(by: page - index) }
                    HapticsManager.shared.trigger(.lightImpact)
                }
            }
        }
        .frame(height: side)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(framingGesture, including: framesPhoto ? .all : .none)
        .gesture(pageGesture(index: index, count: layouts.count), including: framesPhoto ? .none : .all)
        .onChange(of: isDragging) { _, dragging in
            // A system gesture can cancel a drag without ending it; the row must not stay offset.
            guard !dragging, drag != 0 else { return }
            withAnimation(settle) { drag = 0 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.currentLayout.title) preset on \(model.background.title) background")
        .accessibilityValue("\(index + 1) of \(layouts.count)")
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? 1 : -1
            guard layouts.indices.contains(index + delta) else { return }
            withAnimation(settle) { model.swipe(by: delta) }
            HapticsManager.shared.trigger(.lightImpact)
        }
    }

    private func pageGesture(index: Int, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                // No animation while the finger is down: the row sits exactly where it is held.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { drag = value.translation.width }
            }
            .onEnded { value in
                let target = PresetPagerGeometry.destination(
                    index: index,
                    count: count,
                    translation: value.translation.width,
                    velocity: value.velocity.width
                )
                // The page and the drag reset change in one transaction, so the spring starts from
                // the release point instead of snapping back first.
                withAnimation(settle) {
                    if target != index { model.swipe(by: target - index) }
                    drag = 0
                }
                if target != index { HapticsManager.shared.trigger(.lightImpact) }
            }
    }

    // MARK: - Page marks and caption

    private func marks(index: Int, layouts: [PresetLayout], offset: CGFloat) -> some View {
        let position = PresetPagerGeometry.position(index: index, offset: offset)
        let active = PresetPagerGeometry.activePage(position: position, count: layouts.count)
        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Array(layouts.enumerated()), id: \.element) { page, layout in
                    let width = PresetPagerGeometry.markWidth(page: page, position: position)
                    Capsule()
                        .fill(page == active ? lime : Color(shareHex: 0x3A3A3A))
                        .frame(width: width, height: PresetPagerGeometry.dotWidth)
                        .onTapGesture {
                            withAnimation(settle) { model.select(layout: layout) }
                        }
                        .accessibilityLabel("\(layout.title) layout")
                }
            }
            // Every caption is in the stack and only the active one shows, so a page change
            // cross-fades with a small vertical slide instead of swapping text.
            ZStack {
                ForEach(Array(layouts.enumerated()), id: \.element) { page, _ in
                    Text(model.caption(at: page))
                        .opacity(page == active ? 1 : 0)
                        .offset(y: page == active ? 0 : (page < active ? -6 : 6))
                }
            }
            .font(.montserratSemiBold(size: 12))
            .foregroundStyle(Color(shareHex: 0x8A8A8A))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: active)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Photo framing

    private var framingGesture: some Gesture {
        MagnifyGesture()
            .onChanged { liveScale = $0.magnification }
            .onEnded { value in
                model.frame(scale: model.artwork.photoScale * value.magnification, offset: model.artwork.photoOffset)
                liveScale = 1
            }
            .simultaneously(with:
                DragGesture()
                    .onChanged { liveOffset = CGSize(width: $0.translation.width / side, height: $0.translation.height / side) }
                    .onEnded { value in
                        let base = model.artwork.photoOffset
                        model.frame(
                            scale: model.artwork.photoScale,
                            offset: CGSize(width: base.width + value.translation.width / side, height: base.height + value.translation.height / side)
                        )
                        liveOffset = .zero
                    }
            )
    }

    /// The artwork with the in-flight pinch and drag applied, so framing follows the fingers.
    private var framedArtwork: PresetCardArtwork {
        var artwork = model.artwork
        artwork.frame(
            scale: artwork.photoScale * liveScale,
            offset: CGSize(
                width: artwork.photoOffset.width + liveOffset.width,
                height: artwork.photoOffset.height + liveOffset.height
            )
        )
        return artwork
    }
}
