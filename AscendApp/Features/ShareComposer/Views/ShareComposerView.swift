import SwiftData
import SwiftUI

/// Root of the share composer: pick a background, then compose with draggable
/// stat stickers and export. Replaces the old fixed-card share carousel at every
/// share entry point.
struct ShareComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \BestEffortCacheEntry.sortKey) private var bestEffortCacheEntries: [BestEffortCacheEntry]
    @Query(sort: \Workout.date, order: .reverse) private var allWorkouts: [Workout]

    @State private var viewModel: ShareComposerViewModel
    @State private var walkthrough: ShareComposerWalkthroughCoordinator
    @AccessibilityFocusState private var editRailIsFocused: Bool
    @AccessibilityFocusState private var filterButtonIsFocused: Bool
    @State private var showAddSheet = false
    @State private var showFilterSheet = false
    @State private var showFontSheet = false
    @State private var showStructureSheet = false
    @State private var showRenameClimb = false
    @State private var renameText = ""
    @State private var exportingAction: ExportAction?
    @State private var toast: String?
    @State private var applyingRecap = false
    /// The Recaps tab's templates and their resolved data, built once the
    /// injected stats land.
    @State private var recapPreview: ShareBackgroundPickerView.RecapPreview?
    /// Transient filter name shown briefly after a swipe.
    @State private var filterFlash: String?
    /// While a sticker gesture is active, background pan/zoom is ignored so
    /// multi-touch sticker edits never fall through to the backing photo.
    @State private var activeStickerGestureID: UUID?
    /// Live background pinch/drag deltas (committed to the view model on end).
    @GestureState private var bgZoomLive: CGFloat = 1
    @GestureState private var bgPanLive: CGSize = .zero

    /// Which export is in flight (drives the per-button spinner).
    private enum ExportAction { case story, save, share }
    private var isExporting: Bool { exportingAction != nil }

    private let exporter = ShareComposerExporter()
    private let templateStore = ShareCardTemplateStore()
    private let presets: [ShareComposerPreset]
    private let shareTitle: String
    private let accent = Color(red: 0.706, green: 0.8, blue: 0)
    private static let storyAspectRatio = ShareCardFormat.aspectRatio

    init(
        workout: Workout,
        climb: Climb? = nil,
        liveClimbRank: Int? = nil,
        liveClimbRankTotal: Int? = nil,
        walkthroughStore: ShareComposerWalkthroughStore = ShareComposerWalkthroughStore()
    ) {
        let settings = SettingsManager.shared
        _viewModel = State(initialValue: ShareComposerViewModel(
            workout: workout,
            measurementSystem: settings.measurementSystem,
            stepHeight: settings.stepHeight,
            climb: climb,
            climbName: climb?.name,
            climbRank: liveClimbRank,
            climbRankTotal: liveClimbRankTotal
        ))

        // Only the hero artwork is offered as a background preset; the card and
        // thumbnail are addable as stickers (in the Climb tab), not backgrounds.
        var presets: [ShareComposerPreset] = []
        if let climb {
            presets = [.climbImage(climb, .hero)]
        }
        self.presets = presets

        // Seeded with what is knowable synchronously. Recaps stay off until their templates
        // resolve, so nothing ever promises a tab the picker has not drawn.
        _walkthrough = State(initialValue: ShareComposerWalkthroughCoordinator(
            entry: .picker,
            sourceOptions: ShareComposerSourceOptions(
                hasPresets: !presets.isEmpty,
                hasRecaps: false
            ),
            store: walkthroughStore
        ))

        if let climb {
            self.shareTitle = climb.name
        } else {
            self.shareTitle = workout.name.isEmpty ? "your workout" : workout.name
        }
    }

    /// Everything the templates can name, resolved once for the whole tab.
    ///
    /// Held rather than computed: reading it decodes the bundled payload and
    /// resolves the full stat catalogue, and a computed property would do both on
    /// every evaluation of `body`.
    private func makeRecapPreview() -> ShareBackgroundPickerView.RecapPreview? {
        guard let climb = viewModel.climb else { return nil }

        // The standing requirement is what keeps the Standing card out of the
        // picker when no rank resolved: the other three still read correctly
        // with their rank tabs dropped, that one would be a hollow frame.
        let standing = ResolvedShareStanding(
            rank: viewModel.climbRank,
            totalClimbers: viewModel.climbRankTotal
        )
        var requirements: Set<ShareCardRequirement> = [.climb]
        if standing != nil { requirements.insert(.standing) }

        let templates = templateStore.templates(for: requirements)
        guard !templates.isEmpty else { return nil }

        let context = ShareCardRenderContext.template(
            stats: viewModel.climbStats(),
            bestEfforts: viewModel.bestEffortStats,
            weeklyTotals: viewModel.weeklyTotalStats,
            splits: viewModel.splits(),
            standing: standing
        )
        return .init(templates: templates, context: context, climb: climb)
    }

    /// True only once the Recaps tab has something to show, so nothing offers an empty shelf.
    private var offersRecaps: Bool {
        guard viewModel.climb != nil, let recapPreview else { return false }
        return !recapPreview.templates.isEmpty
    }

    /// The sources this picker can offer right now.
    private var liveSourceOptions: ShareComposerSourceOptions {
        ShareComposerSourceOptions(hasPresets: !presets.isEmpty, hasRecaps: offersRecaps)
    }

    /// The one value behind both the picker's tabs and the sources mark's copy. While that mark is
    /// on screen it is the frozen set the card names; otherwise it tracks what is available.
    private var sourceOptions: ShareComposerSourceOptions {
        walkthrough.presentedSourceOptions ?? liveSourceOptions
    }

    /// Bake the selected template to an image and use it as the background.
    /// The user can then add stickers on top or save as-is.
    private func applyTemplate(_ template: ShareCardTemplate) {
        guard !applyingRecap else { return }
        applyingRecap = true

        Task { @MainActor in
            defer { applyingRecap = false }
            guard let preview = recapPreview, let climb = preview.climb,
                  let image = await exporter.renderTemplate(
                      template,
                      context: preview.context,
                      climb: climb
                  ) else {
                toast = "Could not build recap"
                return
            }
            viewModel.resetForNewBackground(.recap(image))
            walkthrough.backgroundSelected(.recap)
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.background == nil {
                ShareBackgroundPickerView(
                    title: shareTitle,
                    presets: presets,
                    sourceOptions: sourceOptions,
                    recap: recapPreview,
                    onPick: { source in
                        // Re-picking a background starts a clean canvas.
                        viewModel.resetForNewBackground(source)
                        if walkthrough.backgroundSelected(.photoOrPreset) {
                            Task {
                                try? await Task.sleep(for: .seconds(0.35))
                                showAddSheet = true
                            }
                        }
                    },
                    onPickRecap: offersRecaps ? { template in applyTemplate(template) } : nil,
                    onClose: { dismiss() },
                    walkthrough: walkthrough
                )
            } else {
                composer
            }

            if applyingRecap {
                Color.black.opacity(0.62)
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    ProgressView()
                        .tint(accent)
                    Text("Building recap")
                        .font(.montserratSemiBold(size: 14))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(24)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
            }
        }
        .overlayPreferenceValue(ShareComposerCoachMarkAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if !applyingRecap,
                   walkthrough.target != .stats,
                   let target = walkthrough.target,
                   let presentation = walkthrough.presentation {
                    CoachMarkOverlay(
                        presentation: presentation,
                        targetRect: anchors[target].map { proxy[$0] },
                        containerSize: proxy.size,
                        onNext: advanceWalkthrough,
                        onSkip: skipWalkthrough
                    )
                    .transition(.opacity)
                }
            }
            // The canvas runs under the status bar, so the dim has to as well or a lit band is
            // left above it. Scoped here so nothing else in the composer animates with the mark.
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: walkthrough.state)
        }
        .sheet(isPresented: $showAddSheet, onDismiss: walkthrough.statsSheetDismissed) {
            ShareAddStatSheet(
                presets: viewModel.availablePresets(),
                presetPreview: { viewModel.presetPreview(for: $0) },
                climbStats: viewModel.climbStats(),
                bestEffortStats: viewModel.bestEffortStats,
                weeklyTotalStats: viewModel.weeklyTotalStats,
                climb: viewModel.climb,
                imageVariants: viewModel.climbImageStickerVariants,
                walkthrough: walkthrough,
                onPickPreset: { preset in
                    HapticsManager.shared.trigger(.lightImpact)
                    viewModel.addPresetSticker(preset)
                    showAddSheet = false
                },
                onPickStat: { stat in
                    HapticsManager.shared.trigger(.lightImpact)
                    viewModel.addSticker(kind: stat.kind)
                    showAddSheet = false
                },
                onPickInjected: { stat in
                    HapticsManager.shared.trigger(.lightImpact)
                    viewModel.addInjectedSticker(stat)
                    showAddSheet = false
                },
                onPickImage: { variant in
                    HapticsManager.shared.trigger(.lightImpact)
                    viewModel.addClimbImageSticker(variant: variant)
                    showAddSheet = false
                }
            )
            .onAppear {
                walkthrough.statsSheetPresented()
            }
            .presentationDetents([.fraction(0.6), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(hex: "121212"))
        }
        .sheet(isPresented: $showFilterSheet) {
            ShareBackgroundFilterSheet(
                filters: viewModel.availableFilters,
                current: viewModel.backgroundFilter,
                onPick: { filter in
                    HapticsManager.shared.trigger(.selection)
                    viewModel.setFilter(filter)
                    flashFilterName()
                }
            )
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(hex: "121212"))
        }
        .sheet(isPresented: $showFontSheet) {
            if let sticker = selectedSticker, let stat = viewModel.resolve(sticker) {
                ShareFontPickerSheet(
                    sampleStat: stat,
                    current: sticker.font,
                    onPick: { font in
                        HapticsManager.shared.trigger(.lightImpact)
                        viewModel.setFont(font, for: sticker.id)
                    }
                )
                .presentationDetents([.height(290)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(hex: "121212"))
            }
        }
        .sheet(isPresented: $showStructureSheet) {
            if let sticker = selectedSticker {
                ShareStructureSheet(viewModel: viewModel, stickerID: sticker.id)
                    .presentationDetents([.fraction(0.55), .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Color(hex: "121212"))
            }
        }
        .alert("Rename climb", isPresented: $showRenameClimb) {
            TextField("Climb name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { viewModel.setClimbName(renameText) }
        } message: {
            Text("Rename how this climb appears on your share. Stat values can't be changed.")
        }
        .overlay(alignment: .bottom) { toastView }
        .onChange(of: viewModel.selectedID) {
            walkthrough.stickerSelected(selectedSticker)
        }
        .onChange(of: walkthrough.restingFocusTarget) { _, target in
            switch target {
            case .editRail:
                editRailIsFocused = true
            case .filters:
                filterButtonIsFocused = true
            case .sources, .stats, nil:
                break
            }
        }
        .task {
            // Inject the workout's Best Efforts (from the cache) so each can be
            // added as its own sticker — they get their own add-sheet section.
            // The cache can hold the same metric across multiple scopes/contexts,
            // so dedupe by label (the list is significance-sorted; keep the first).
            let snapshot = BestEffortCacheSnapshot(entries: bestEffortCacheEntries, workouts: [viewModel.workout])
            var seenEffortLabels = Set<String>()
            viewModel.setBestEffortStats(snapshot.efforts(for: viewModel.workout).compactMap { effort in
                let label = effort.metric.title.uppercased()
                guard seenEffortLabels.insert(label).inserted else { return nil }
                return ResolvedShareStat(kind: .bestEffort, label: label, value: effort.compactValueText)
            })
            // Inject this-week totals for the Totals tab.
            viewModel.injectWeeklyTotals(from: allWorkouts)
            // Both injections feed the templates, so build the tab after them.
            recapPreview = makeRecapPreview()
            walkthrough.sourceOptionsResolved(liveSourceOptions)
        }
        .task {
            try? await Task.sleep(for: ShareComposerWalkthroughCoordinator.sourceOptionsResolutionLimit)
            guard !Task.isCancelled else { return }
            walkthrough.sourceOptionsResolutionTimedOut()
        }
        .trackOnce(screen: .shareComposer)
    }

    // MARK: - Composer canvas

    private var composer: some View {
        VStack(spacing: 0) {
            canvasRegion
            bottomBar
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .top)
    }

    /// The shareable photo region — everything that gets exported. The action
    /// bar lives *below* this (in `bottomBar`) so controls never overlap the
    /// image, matching the Aura layout.
    private var canvasRegion: some View {
        GeometryReader { geo in
            let canvasSize = Self.fittedStoryCanvasSize(in: geo.size)
            let canvasScale = canvasSize.width / 390

            ZStack {
                // Black base so a shrunk (zoomed-out) background floats on black.
                Color.black

                // Background (live): pinch to zoom (in or out), drag to move it
                // freely once manipulated, or swipe to change the filter at fit.
                // Double-tap resets it to fit.
                if let background = viewModel.background {
                    let panActive = viewModel.backgroundIsManipulated
                    let scale = viewModel.backgroundScale
                        * (viewModel.backgroundSupportsTransform ? bgZoomLive : 1)
                    let offX = viewModel.backgroundOffset.width * canvasSize.width + (panActive ? bgPanLive.width : 0)
                    let offY = viewModel.backgroundOffset.height * canvasSize.height + (panActive ? bgPanLive.height : 0)
                    ShareBackgroundView(
                        source: background,
                        filter: viewModel.backgroundFilter,
                        processedImage: viewModel.processedBackgroundImage
                    )
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .scaleEffect(scale)
                    .offset(x: offX, y: offY)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { viewModel.resetBackgroundTransform() }
                    .onTapGesture { viewModel.deselect() }
                    .gesture(backgroundGesture(canvasSize: canvasSize))
                }

                // Snap guides (drawn at the active snap line: center or edge).
                // They arrive instantly — a guide that fades in reads as lag on a
                // magnetic snap — and fade out as the sticker pulls away.
                if let gx = viewModel.verticalGuideX {
                    Rectangle().fill(accent.opacity(0.85)).frame(width: 1, height: canvasSize.height)
                        .position(x: gx, y: canvasSize.height / 2)
                        .allowsHitTesting(false)
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                }
                if let gy = viewModel.horizontalGuideY {
                    Rectangle().fill(accent.opacity(0.85)).frame(width: canvasSize.width, height: 1)
                        .position(x: canvasSize.width / 2, y: gy)
                        .allowsHitTesting(false)
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                }

                // Stickers
                ForEach(viewModel.stickers) { sticker in
                    let content = viewModel.content(for: sticker)
                    if !content.isEmpty {
                        ShareStickerView(
                            // Bound by id, not by index. An index binding into an
                            // array that shrinks mid-drag traps when the child's
                            // body still holds the stale subscript — which is
                            // exactly the delete-while-dragging path this canvas has.
                            instance: stickerBinding(sticker.id, lastKnown: sticker),
                            content: content,
                            climb: viewModel.climb,
                            canvasSize: canvasSize,
                            canvasScale: canvasScale,
                            isSelected: viewModel.selectedID == sticker.id,
                            isOverTrash: viewModel.isOverTrash && viewModel.draggingID == sticker.id,
                            onSelect: { viewModel.select(sticker.id) },
                            onDragChanged: { center in
                                viewModel.handleDragChanged(id: sticker.id, center: center, canvasSize: canvasSize)
                            },
                            snapCenter: { raw in
                                viewModel.snappedCenter(raw, canvasSize: canvasSize)
                            },
                            onDragEnded: { center in
                                withAnimation(ShareComposerAnimation.placement) {
                                    _ = viewModel.handleDragEnded(
                                        id: sticker.id,
                                        center: center,
                                        canvasSize: canvasSize
                                    )
                                }
                            },
                            onDragCancelled: {
                                viewModel.cancelDragFeedback()
                            },
                            onInteractionChanged: { isActive in
                                if isActive {
                                    activeStickerGestureID = sticker.id
                                } else if activeStickerGestureID == sticker.id {
                                    activeStickerGestureID = nil
                                }
                            }
                        )
                        .transition(ShareComposerAnimation.removal)
                    }
                }

                // Trash zone (visible while dragging)
                if viewModel.draggingID != nil {
                    trashZone(in: canvasSize)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Transient filter name after a swipe.
                if let filterFlash {
                    Text(filterFlash.uppercased())
                        .font(.montserratBold(size: 15))
                        .tracking(2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }

                // Bottom overlay: the + pill (hidden while dragging) above the
                // always-on Ascend wordmark that's burned into every export.
                VStack(spacing: 10) {
                    Spacer()
                    if viewModel.draggingID == nil {
                        addPill.transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                    if viewModel.shouldRenderCanvasWordmark {
                        AscendWordmark(size: 13 * canvasScale, letterColor: .white.opacity(0.92))
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                            .allowsHitTesting(false)
                            // Card content, not chrome: the export renders at the
                            // default text size, so a lockup that grew here would
                            // show the author something the export cannot reproduce.
                            .dynamicTypeSize(.large)
                            .padding(.bottom, 12)
                    }
                }

                // Chrome
                topChrome
                if viewModel.draggingID == nil {
                    editRail.transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            // Everything that appears or disappears around a drag fades on the
            // same curve instead of popping on a frame boundary.
            .animation(ShareComposerAnimation.chrome, value: viewModel.draggingID)
            .animation(ShareComposerAnimation.chrome, value: viewModel.verticalGuideX)
            .animation(ShareComposerAnimation.chrome, value: viewModel.horizontalGuideY)
            .animation(ShareComposerAnimation.placement, value: viewModel.stickers.map(\.id))
            .frame(width: canvasSize.width, height: canvasSize.height)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .clipped()
        }
    }

    private static func fittedStoryCanvasSize(in container: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0 else { return .zero }

        let widthFromHeight = container.height * storyAspectRatio
        if widthFromHeight <= container.width {
            return CGSize(width: widthFromHeight, height: container.height)
        }

        return CGSize(width: container.width, height: container.width / storyAspectRatio)
    }

    private func trashZone(in canvasSize: CGSize) -> some View {
        let rect = viewModel.trashRect(in: canvasSize)
        let hot = viewModel.isOverTrash
        return ZStack {
            Capsule(style: .continuous)
                .fill(.black.opacity(0.5))
                .overlay(Capsule(style: .continuous).stroke(hot ? Color.red : .white.opacity(0.5), lineWidth: 1.5))
            Image(systemName: hot ? "trash.fill" : "trash")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(hot ? Color.red : .white.opacity(0.85))
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .shadow(color: hot ? Color.red.opacity(0.5) : .clear, radius: 20)
    }

    private var topChrome: some View {
        VStack {
            HStack {
                // Back to the background picker (not exit). Exit happens from
                // the picker's chevron-down.
                circleButton(systemName: "chevron.left", accessibilityLabel: "Choose another background") {
                    viewModel.deselect()
                    viewModel.background = nil
                }
                Spacer()
                circleButton(systemName: "camera.filters", accessibilityLabel: "Background filters") {
                    viewModel.deselect()
                    HapticsManager.shared.trigger(.lightImpact)
                    showFilterSheet = true
                }
                .shareComposerCoachMarkTarget(.filters)
                .accessibilityFocused($filterButtonIsFocused)
            }
            .padding(.horizontal, 12)
            .padding(.top, 52)
            Spacer()
        }
    }

    // MARK: - Selected-sticker edit rail

    private var selectedSticker: ShareStickerInstance? {
        guard let id = viewModel.selectedID else { return nil }
        return viewModel.sticker(id)
    }

    /// A sticker binding resolved by id on every access, so a delete mid-gesture
    /// cannot leave a child holding a stale index into a shrunken array.
    ///
    /// `lastKnown` is the value this pass of the `ForEach` rendered. Once the
    /// sticker is gone the outgoing view keeps drawing where it was for the length
    /// of its removal transition, instead of snapping to the defaults of a
    /// substituted instance; writes to a deleted sticker are no-ops.
    private func stickerBinding(_ id: UUID, lastKnown: ShareStickerInstance) -> Binding<ShareStickerInstance> {
        Binding(
            get: { viewModel.sticker(id) ?? lastKnown },
            set: { viewModel.update($0) }
        )
    }

    @ViewBuilder
    private var editRail: some View {
        if let sticker = selectedSticker, !sticker.isImage {
            VStack(spacing: 14) {
                // Structure: arrange multiple metrics (row / grid / column),
                // move their labels, and toggle which show. A curated cluster
                // arrives already arranged, so neither control applies to it -
                // its whole point is that nobody has to lay stats out.
                if sticker.kind.supportsComposite, !sticker.isPreset {
                    railButton(systemName: "square.grid.2x2", accessibilityLabel: "Arrange stats") {
                        HapticsManager.shared.trigger(.lightImpact)
                        showStructureSheet = true
                    }
                }

                // Rename — only when the sticker includes the climb name.
                if sticker.containsClimbName {
                    railButton(systemName: "pencil", accessibilityLabel: "Rename climb") {
                        HapticsManager.shared.trigger(.lightImpact)
                        renameText = viewModel.resolve(sticker)?.value ?? ""
                        showRenameClimb = true
                    }
                }

                // Label position. Applies to every metric on the sticker,
                // however many there are — the control used to advance a value
                // the multi-metric renderer ignored, so tapping it did nothing.
                if !sticker.isStructured, !sticker.isPreset {
                    railButton(systemName: sticker.labelPlacement.symbolName, accessibilityLabel: "Change alignment") {
                        HapticsManager.shared.trigger(.lightImpact)
                        withAnimation(ShareComposerAnimation.content) {
                            viewModel.cycleLabelPlacement(for: sticker.id)
                        }
                    }
                }
                railButton(systemName: "character", accessibilityLabel: "Sticker font") { showFontSheet = true }

                ColorPicker("", selection: colorBinding(sticker.id))
                    .labelsHidden()
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
                    .accessibilityLabel("Sticker color")

                railButton(systemName: textBackgroundIcon(sticker.textBackground), accessibilityLabel: "Sticker panel") {
                    HapticsManager.shared.trigger(.lightImpact)
                    withAnimation(ShareComposerAnimation.content) {
                        viewModel.cycleTextBackground(for: sticker.id)
                    }
                }
            }
            .padding(.trailing, 14)
            .shareComposerCoachMarkTarget(.editRail)
            .accessibilityFocused($editRailIsFocused)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }

    private func railButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(.black.opacity(0.4)).overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1)))
        }
        .frame(width: 44, height: 44)
        .contentShape(.rect)
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func textBackgroundIcon(_ bg: ShareTextBackground) -> String {
        switch bg {
        case .none: return "square.dashed"
        case .dark: return "square.fill"
        case .grey: return "square.lefthalf.filled"
        }
    }

    private func colorBinding(_ id: UUID) -> Binding<Color> {
        Binding(
            get: { viewModel.stickers.first { $0.id == id }?.color.color ?? .white },
            set: { viewModel.setColor(RGBAColor($0), for: id) }
        )
    }

    /// Translucent "add sticker" button floating at the bottom of the photo,
    /// matching the Share button's footprint. Light haptic on tap.
    private var addPill: some View {
        Button {
            HapticsManager.shared.trigger(.lightImpact)
            showAddSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add stats")
    }

    /// Action strip in its own space below the photo — never overlaps the image.
    private var bottomBar: some View {
        HStack(spacing: 12) {
            actionPill(label: "STORY", systemName: "camera", isLoading: exportingAction == .story) {
                Task { await exportToStory() }
            }
            actionPill(label: "SAVE", systemName: "arrow.down.to.line", isLoading: exportingAction == .save) {
                Task { await save() }
            }
            Button { Task { await shareSheet() } } label: {
                Group {
                    if exportingAction == .share {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 20, weight: .semibold))
                    }
                }
                .foregroundStyle(.black)
                .frame(width: 52, height: 52)
                .background(Circle().fill(accent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .disabled(isExporting)
    }

    // MARK: - Background transform + filter swipe

    /// Pinch zooms the background; dragging repositions it when zoomed, or
    /// (at fit-scale) a horizontal swipe cycles the filter.
    private func backgroundGesture(canvasSize: CGSize) -> some Gesture {
        let zoom = MagnifyGesture()
            .updating($bgZoomLive) { value, state, _ in
                guard activeStickerGestureID == nil else {
                    state = 1
                    return
                }
                state = value.magnification
            }
            .onEnded { value in
                guard activeStickerGestureID == nil else { return }
                viewModel.commitBackgroundZoom(value.magnification)
            }

        let pan = DragGesture(minimumDistance: 20)
            .updating($bgPanLive) { value, state, _ in
                guard activeStickerGestureID == nil else {
                    state = .zero
                    return
                }
                state = value.translation
            }
            .onEnded { value in
                guard activeStickerGestureID == nil else { return }
                if viewModel.backgroundIsManipulated {
                    viewModel.commitBackgroundPan(
                        dxFraction: value.translation.width / canvasSize.width,
                        dyFraction: value.translation.height / canvasSize.height
                    )
                } else {
                    handleFilterSwipe(value.translation)
                }
            }

        return zoom.simultaneously(with: pan)
    }

    private func handleFilterSwipe(_ translation: CGSize) {
        // Only horizontal swipes of meaningful length cycle the filter.
        guard abs(translation.width) > abs(translation.height), abs(translation.width) > 45 else { return }
        HapticsManager.shared.trigger(.selection)
        viewModel.cycleFilter(forward: translation.width < 0)
        flashFilterName()
    }

    private func flashFilterName() {
        let name = viewModel.backgroundFilter.displayName
        withAnimation { filterFlash = name }
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation { if filterFlash == name { filterFlash = nil } }
        }
    }

    private func actionPill(label: String, systemName: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: systemName).font(.system(size: 16, weight: .semibold))
                }
                Text(label).font(.montserratBold(size: 14)).tracking(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule(style: .continuous).fill(.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    private func circleButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(.black.opacity(0.32)))
        }
        .frame(width: 44, height: 44)
        .contentShape(.rect)
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Capsule().fill(.black.opacity(0.8)))
                .padding(.bottom, 120)
                .transition(.opacity)
        }
    }

    // MARK: - First-open walkthrough

    private func advanceWalkthrough() {
        walkthrough.advance()
    }

    private func skipWalkthrough() {
        walkthrough.skip()
    }

    // MARK: - Export actions

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { if toast == message { toast = nil } }
        }
    }

    private var isVideoBackground: Bool { viewModel.background?.isVideo ?? false }

    private func finishSave(_ ok: Bool) {
        if ok {
            HapticsManager.shared.trigger(.success)
            showToast("Saved to Photos")
        } else {
            showToast("Allow Photos access to save")
        }
    }

    private func save() async {
        exportingAction = .save
        defer { exportingAction = nil }
        if isVideoBackground {
            guard let url = await exporter.exportVideo(viewModel: viewModel) else {
                showToast("Couldn't export video")
                return
            }
            finishSave(await exporter.saveVideoToPhotos(url))
        } else {
            guard let image = await exporter.renderImage(viewModel: viewModel) else {
                showToast("Couldn't render image")
                return
            }
            finishSave(await exporter.saveToPhotos(image))
        }
    }

    private func shareSheet() async {
        exportingAction = .share
        defer { exportingAction = nil }
        if isVideoBackground {
            guard let url = await exporter.exportVideo(viewModel: viewModel) else { return }
            exporter.presentShareSheet(url: url)
        } else {
            guard let image = await exporter.renderImage(viewModel: viewModel) else { return }
            exporter.presentShareSheet(image: image)
        }
    }

    private func exportToStory() async {
        exportingAction = .story
        defer { exportingAction = nil }
        if isVideoBackground {
            // IG Stories video import isn't wired yet — fall back to the share sheet.
            guard let url = await exporter.exportVideo(viewModel: viewModel) else { return }
            exporter.presentShareSheet(url: url)
        } else {
            guard let image = await exporter.renderImage(viewModel: viewModel) else { return }
            if !exporter.shareToInstagramStory(image) {
                exporter.presentShareSheet(image: image)
            }
        }
    }
}

/// Geometry the add sheet previews a curated cluster at.
///
/// Every tile reduces the same fixed design box, so the groups are shown at one
/// scale relative to each other rather than each filling its tile. Named here
/// rather than buried in the sheet because a cluster that outgrows the box is
/// clipped in the picker alone, which is what the evidence suite measures.
enum ShareAddStatSheetLayout {
    /// Sized to the widest cluster (Splits, 324) and the tallest (HR Hero, 286)
    /// with a little headroom. `everyClusterFitsTheAddSheetsPreviewBox` fails if
    /// a new cluster outgrows it.
    static let presetPreviewBox = CGSize(width: 340, height: 300)
    static let presetPreviewScale: CGFloat = 0.4
}

/// Bottom sheet for adding stickers. A Climb | Totals toggle (Aura-style)
/// switches between this-climb content (artwork + stats + Best Efforts) and
/// this-week totals.
private struct ShareAddStatSheet: View {
    let presets: [ShareStatClusterPreset]
    let presetPreview: (ShareStatClusterPreset) -> ShareStickerContent
    let climbStats: [ResolvedShareStat]
    let bestEffortStats: [ResolvedShareStat]
    let weeklyTotalStats: [ResolvedShareStat]
    let climb: Climb?
    let imageVariants: [ClimbImageVariant]
    let walkthrough: ShareComposerWalkthroughCoordinator
    let onPickPreset: (ShareStatClusterPreset) -> Void
    let onPickStat: (ResolvedShareStat) -> Void
    let onPickInjected: (ResolvedShareStat) -> Void
    let onPickImage: (ClimbImageVariant) -> Void

    @State private var tab: Tab = .primary
    @AccessibilityFocusState private var statsTabsAreFocused: Bool
    enum Tab { case primary, totals }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private let lime = Color(red: 0.706, green: 0.8, blue: 0)

    /// Left tab is "Climb" when sharing a climb, otherwise "Workout".
    private var primaryLabel: String { climb == nil ? "Workout" : "Climb" }

    var body: some View {
        VStack(spacing: 0) {
            tabPill
                .accessibilityFocused($statsTabsAreFocused)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 16)

            ScrollView {
                if tab == .primary {
                    primaryContent
                } else {
                    totalsContent
                }
            }
            .shareComposerCoachMarkTarget(.stats)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: walkthrough.restingFocusTarget) { _, target in
            guard target == .stats else { return }
            statsTabsAreFocused = true
        }
        .overlayPreferenceValue(ShareComposerCoachMarkAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if walkthrough.target == .stats,
                   let presentation = walkthrough.presentation {
                    CoachMarkOverlay(
                        presentation: presentation,
                        targetRect: anchors[.stats]
                            .map { proxy[$0] }
                            .flatMap {
                                ShareComposerCoachMarkGeometry.statsSpotlightRect(
                                    for: $0,
                                    in: proxy.size
                                )
                            },
                        containerSize: proxy.size,
                        onNext: walkthrough.advance,
                        onSkip: walkthrough.skip
                    )
                }
            }
        }
    }

    // MARK: - Tabs

    private var tabPill: some View {
        HStack(spacing: 0) {
            tabButton(primaryLabel, tab: .primary)
            tabButton("Totals", tab: .totals)
        }
        .padding(4)
        .background(.white.opacity(0.06), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    private func tabButton(_ label: String, tab destination: Tab) -> some View {
        Button {
            guard tab != destination else { return }
            HapticsManager.shared.trigger(.lightImpact)
            tab = destination
        } label: {
            Text(label)
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(tab == destination ? .white : .white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background {
                    if tab == destination {
                        Capsule(style: .continuous).fill(.white.opacity(0.12))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Climb / Workout tab

    private var primaryContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !presets.isEmpty {
                section("GROUPS") { presetGrid }
            }

            if let climb, !imageVariants.isEmpty {
                section("CLIMB") {
                    HStack(spacing: 12) {
                        ForEach(imageVariants, id: \.self) { variant in
                            Button { onPickImage(variant) } label: {
                                ShareClimbImageVisual(climb: climb, variant: variant)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            if !climbStats.isEmpty {
                section("STATS") { statGrid(climbStats, onTap: onPickStat) }
            }

            if !bestEffortStats.isEmpty {
                section("BEST EFFORTS") { statGrid(bestEffortStats, onTap: onPickInjected) }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }

    // MARK: - Totals tab

    private var totalsContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            if weeklyTotalStats.isEmpty {
                Text("No climbs yet this week.\nClimb to fill your totals.")
                    .font(.montserratMedium(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.customGray)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 44)
            } else {
                section("THIS WEEK") { statGrid(weeklyTotalStats, onTap: onPickInjected) }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }

    // MARK: - Curated clusters

    /// Each tile draws the real cluster through the real interpreter, scaled
    /// down inside a fixed design box - so every group is previewed at the same
    /// reduction and the tile shows exactly what the canvas will place.
    private var presetGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(presets) { preset in
                Button { onPickPreset(preset) } label: { presetTile(preset) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func presetTile(_ preset: ShareStatClusterPreset) -> some View {
        let content = presetPreview(preset)
        let box = ShareAddStatSheetLayout.presetPreviewBox
        let scale = ShareAddStatSheetLayout.presetPreviewScale
        return VStack(spacing: 8) {
            ShareCardRenderer(node: content.node, context: content.context, artwork: .none)
                .fixedSize()
                .frame(width: box.width, height: box.height)
                .scaleEffect(scale)
                .frame(width: box.width * scale, height: box.height * scale)
                .clipped()

            Text(preset.title.uppercased())
                .font(.montserratSemiBold(size: 10))
                .tracking(1.2)
                .foregroundStyle(lime)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        )
    }

    // MARK: - Reusable bits

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title)
            content()
        }
    }

    private func statGrid(_ stats: [ResolvedShareStat], onTap: @escaping (ResolvedShareStat) -> Void) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(stats, id: \.label) { stat in
                Button { onTap(stat) } label: { statTile(stat) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func statTile(_ stat: ResolvedShareStat) -> some View {
        VStack(spacing: 6) {
            Text(stat.value)
                .font(.montserratBold(size: 24))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(stat.label)
                .font(.montserratSemiBold(size: 10))
                .tracking(1.2)
                .foregroundStyle(lime)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 88)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        )
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.montserratSemiBold(size: 11))
            .tracking(2)
            .foregroundStyle(lime)
    }
}

/// Detented background filter picker. This gives filters an explicit path after
/// the background has been moved or scaled and canvas drags are reserved for pan.
private struct ShareBackgroundFilterSheet: View {
    let filters: [ShareBackgroundFilter]
    let current: ShareBackgroundFilter
    let onPick: (ShareBackgroundFilter) -> Void

    private let lime = Color(red: 0.706, green: 0.8, blue: 0)
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text("Background Filter")
                .font(.montserratBold(size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 20)
                .padding(.bottom, 16)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(filters) { filter in
                    filterButton(filter)
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func filterButton(_ filter: ShareBackgroundFilter) -> some View {
        let isOn = filter == current

        return Button {
            onPick(filter)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: filterIcon(filter))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isOn ? .black : .white)

                Text(filter.displayName.uppercased())
                    .font(.montserratSemiBold(size: 9))
                    .tracking(1)
                    .foregroundStyle(isOn ? .black.opacity(0.72) : Color.customGray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isOn ? lime : .white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isOn ? lime : .white.opacity(0.08), lineWidth: isOn ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func filterIcon(_ filter: ShareBackgroundFilter) -> String {
        switch filter {
        case .original: return "circle"
        case .mono: return "circle.lefthalf.filled"
        case .noir: return "moon.fill"
        case .vivid: return "sun.max.fill"
        case .fade: return "cloud.fill"
        case .warm: return "thermometer.sun.fill"
        case .cool: return "snowflake"
        case .zoomBlur: return "camera.metering.matrix"
        case .motionBlur: return "wind"
        case .fisheye: return "circle.grid.cross"
        }
    }
}

/// Detented font carousel — each chip previews the selected stat's value in that
/// face (the "Stats Font" picker).
private struct ShareFontPickerSheet: View {
    let sampleStat: ResolvedShareStat
    let current: ShareStickerFont
    let onPick: (ShareStickerFont) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text("Stats Font")
                .font(.montserratBold(size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 20)
                .padding(.bottom, 16)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ShareStickerFont.allCases) { font in
                    Button { onPick(font) } label: {
                        VStack(spacing: 4) {
                            Text(sampleStat.value)
                                .font(font.swiftUIFont(size: 22))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Text(font.displayName)
                                .font(.montserratSemiBold(size: 9))
                                .tracking(1)
                                .foregroundStyle(Color.customGray)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 70)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(current == font ? Color(red: 0.706, green: 0.8, blue: 0) : .white.opacity(0.08),
                                                lineWidth: current == font ? 2 : 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Sheet to arrange a stat sticker's metrics: pick a layout (row / 2×2 grid /
/// column), place their labels, and select/deselect which metrics appear. Stat
/// *values* aren't editable here — only the arrangement and which metrics show
/// (they're the truth). Reads/writes the live view model so the canvas updates
/// as you toggle.
private struct ShareStructureSheet: View {
    let viewModel: ShareComposerViewModel
    let stickerID: UUID

    private let lime = Color(red: 0.706, green: 0.8, blue: 0)
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var sticker: ShareStickerInstance? {
        viewModel.sticker(stickerID)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Arrange stats")
                .font(.montserratBold(size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 20)
                .padding(.bottom, 16)

            if let sticker {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        layoutSection(current: sticker.layout)
                        labelSection(current: sticker.labelPlacement)
                        metricSection(sticker: sticker)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Layout

    private func layoutSection(current: ShareStatLayout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header("LAYOUT")
            HStack(spacing: 12) {
                layoutButton(.row, icon: "rectangle.split.3x1", current: current)
                layoutButton(.grid, icon: "square.grid.2x2", current: current)
                layoutButton(.column, icon: "rectangle.split.1x2", current: current)
            }
        }
    }

    private func layoutButton(_ layout: ShareStatLayout, icon: String, current: ShareStatLayout) -> some View {
        let isOn = layout == current
        return Button {
            HapticsManager.shared.trigger(.lightImpact)
            withAnimation(ShareComposerAnimation.content) {
                viewModel.setLayout(layout, for: stickerID)
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isOn ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isOn ? lime : .white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Label position

    /// Independent of LAYOUT above it, and that is the point: choosing where a
    /// label sits is not a consequence of how the metrics are arranged, so
    /// changing the arrangement leaves this alone.
    private func labelSection(current: ShareCardLabelPlacement) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header("LABEL")
            HStack(spacing: 10) {
                ForEach(ShareCardLabelPlacement.allCases) { placement in
                    labelButton(placement, current: current)
                }
            }
        }
    }

    private func labelButton(_ placement: ShareCardLabelPlacement, current: ShareCardLabelPlacement) -> some View {
        let isOn = placement == current
        return Button {
            HapticsManager.shared.trigger(.lightImpact)
            withAnimation(ShareComposerAnimation.content) {
                viewModel.setLabelPlacement(placement, for: stickerID)
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: placement.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                Text(placement.displayName.uppercased())
                    .font(.montserratSemiBold(size: 8))
                    .tracking(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isOn ? .black : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isOn ? lime : .white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Metrics

    private func metricSection(sticker: ShareStickerInstance) -> some View {
        let palette = viewModel.paletteRefs(for: sticker)
        let selected = Set(sticker.statRefs)
        return VStack(alignment: .leading, spacing: 10) {
            header("METRICS")
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(palette, id: \.self) { ref in
                    let stat = viewModel.resolved(ref)
                    metricChip(
                        label: stat?.label ?? "",
                        value: stat?.value ?? "",
                        isOn: selected.contains(ref)
                    ) {
                        HapticsManager.shared.trigger(.lightImpact)
                        withAnimation(ShareComposerAnimation.content) {
                            viewModel.toggleStat(ref, for: stickerID)
                        }
                    }
                }
            }
        }
    }

    private func metricChip(label: String, value: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isOn ? lime : .white.opacity(0.4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.montserratBold(size: 16))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(label)
                        .font(.montserratSemiBold(size: 9))
                        .tracking(1)
                        .foregroundStyle(Color.customGray)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 60)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isOn ? lime.opacity(0.6) : .white.opacity(0.08), lineWidth: isOn ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.montserratSemiBold(size: 11))
            .tracking(2)
            .foregroundStyle(lime)
    }
}
