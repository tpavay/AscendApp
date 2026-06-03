import SwiftData
import SwiftUI

/// Root of the share composer: pick a background, then compose with draggable
/// stat stickers and export. Replaces the old fixed-card share carousel at every
/// share entry point.
struct ShareComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BestEffortCacheEntry.sortKey) private var bestEffortCacheEntries: [BestEffortCacheEntry]

    @State private var viewModel: ShareComposerViewModel
    @State private var showAddSheet = false
    @State private var showFontSheet = false
    @State private var isExporting = false
    @State private var toast: String?

    private let exporter = ShareComposerExporter()
    private let presets: [ShareComposerPreset]
    private let shareTitle: String
    private let accent = Color(red: 0.706, green: 0.8, blue: 0)

    init(
        workout: Workout,
        climb: Climb? = nil,
        liveClimbRank: Int? = nil,
        liveClimbRankTotal: Int? = nil
    ) {
        let settings = SettingsManager.shared
        _viewModel = State(initialValue: ShareComposerViewModel(
            workout: workout,
            measurementSystem: settings.measurementSystem,
            stepHeight: settings.stepHeight,
            climbName: climb?.name,
            climbRank: liveClimbRank,
            climbRankTotal: liveClimbRankTotal
        ))

        var presets: [ShareComposerPreset] = []
        if let climb {
            presets = [
                .climbImage(climb, .hero),
                .climbImage(climb, .card),
                .climbImage(climb, .thumb)
            ]
        }
        self.presets = presets

        if let climb {
            self.shareTitle = climb.name
        } else {
            self.shareTitle = workout.name.isEmpty ? "your workout" : workout.name
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.background == nil {
                ShareBackgroundPickerView(
                    title: shareTitle,
                    presets: presets,
                    onPick: { source in
                        viewModel.background = source
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showAddSheet = true
                        }
                    },
                    onClose: { dismiss() }
                )
            } else {
                composer
            }
        }
        .sheet(isPresented: $showAddSheet) {
            ShareAddStatSheet(
                stats: viewModel.availableStats(),
                onPick: { stat in
                    HapticsManager.shared.trigger(.lightImpact)
                    viewModel.addSticker(kind: stat.kind)
                    showAddSheet = false
                }
            )
            .presentationDetents([.fraction(0.6), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(hex: "121212"))
        }
        .sheet(isPresented: $showFontSheet) {
            if let index = selectedIndex, let stat = viewModel.resolve(viewModel.stickers[index].kind) {
                ShareFontPickerSheet(
                    sampleStat: stat,
                    current: viewModel.stickers[index].font,
                    onPick: { font in
                        HapticsManager.shared.trigger(.lightImpact)
                        viewModel.stickers[index].font = font
                    }
                )
                .presentationDetents([.height(290)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(hex: "121212"))
            }
        }
        .overlay(alignment: .bottom) { toastView }
        .task {
            // Inject the workout's headline Best Effort (from the cache) so it
            // can be added as a sticker.
            let snapshot = BestEffortCacheSnapshot(entries: bestEffortCacheEntries, workouts: [viewModel.workout])
            if let effort = snapshot.primaryEffort(for: viewModel.workout) {
                viewModel.primaryBestEffortStat = ResolvedShareStat(
                    kind: .bestEffort,
                    label: effort.metric.title.uppercased(),
                    value: effort.compactValueText
                )
            }
        }
    }

    // MARK: - Composer canvas

    private var composer: some View {
        GeometryReader { geo in
            let canvasSize = geo.size
            let canvasScale = canvasSize.width / 390

            ZStack {
                // Background (live)
                if let background = viewModel.background {
                    ShareBackgroundView(source: background)
                        .frame(width: canvasSize.width, height: canvasSize.height)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.deselect() }
                }

                // Snap guides (drawn at the active snap line: center or edge)
                if let gx = viewModel.verticalGuideX {
                    Rectangle().fill(accent.opacity(0.85)).frame(width: 1, height: canvasSize.height)
                        .position(x: gx, y: canvasSize.height / 2)
                        .allowsHitTesting(false)
                }
                if let gy = viewModel.horizontalGuideY {
                    Rectangle().fill(accent.opacity(0.85)).frame(width: canvasSize.width, height: 1)
                        .position(x: canvasSize.width / 2, y: gy)
                        .allowsHitTesting(false)
                }

                // Stickers
                ForEach(Array(viewModel.stickers.enumerated()), id: \.element.id) { index, sticker in
                    if let stat = viewModel.resolve(sticker.kind) {
                        ShareStickerView(
                            instance: $viewModel.stickers[index],
                            stat: stat,
                            canvasSize: canvasSize,
                            canvasScale: canvasScale,
                            isSelected: viewModel.selectedID == sticker.id,
                            onSelect: { viewModel.select(sticker.id) },
                            onDragChanged: { center in
                                viewModel.handleDragChanged(id: sticker.id, center: center, canvasSize: canvasSize)
                            },
                            snapCenter: { raw in
                                viewModel.snappedCenter(raw, canvasSize: canvasSize)
                            },
                            onDragEnded: { center in
                                viewModel.handleDragEnded(id: sticker.id, center: center, canvasSize: canvasSize)
                            }
                        )
                    }
                }

                // Trash zone (visible while dragging)
                if viewModel.draggingID != nil {
                    trashZone(in: canvasSize)
                }

                // Chrome
                topChrome
                if viewModel.draggingID == nil {
                    editRail
                    bottomBar
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
        }
        .ignoresSafeArea()
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
                circleButton(systemName: "xmark") { dismiss() }
                Spacer()
                circleButton(systemName: "photo") { viewModel.background = nil }
            }
            .padding(.horizontal, 12)
            .padding(.top, 52)
            Spacer()
        }
    }

    // MARK: - Selected-sticker edit rail

    private var selectedIndex: Int? {
        guard let id = viewModel.selectedID else { return nil }
        return viewModel.stickers.firstIndex { $0.id == id }
    }

    @ViewBuilder
    private var editRail: some View {
        if let index = selectedIndex {
            VStack(spacing: 14) {
                railButton(systemName: "textformat.size") {
                    HapticsManager.shared.trigger(.lightImpact)
                    viewModel.stickers[index].style = viewModel.stickers[index].style.next()
                }
                railButton(systemName: "character") { showFontSheet = true }

                ColorPicker("", selection: colorBinding(index))
                    .labelsHidden()
                    .frame(width: 36, height: 36)

                railButton(systemName: textBackgroundIcon(viewModel.stickers[index].textBackground)) {
                    HapticsManager.shared.trigger(.lightImpact)
                    viewModel.stickers[index].textBackground = viewModel.stickers[index].textBackground.next()
                }
            }
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }

    private func railButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(.black.opacity(0.4)).overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }

    private func textBackgroundIcon(_ bg: ShareTextBackground) -> String {
        switch bg {
        case .none: return "square.dashed"
        case .dark: return "square.fill"
        case .grey: return "square.lefthalf.filled"
        }
    }

    private func colorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: { viewModel.stickers[index].color.color },
            set: { viewModel.stickers[index].color = RGBAColor($0) }
        )
    }

    private var bottomBar: some View {
        VStack {
            Spacer()

            // Add sticker pill
            Button { showAddSheet = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(.black.opacity(0.4)).overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1)))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)

            // Action bar
            HStack(spacing: 12) {
                actionPill(label: "STORY", systemName: "camera") { Task { await exportToStory() } }
                actionPill(label: "SAVE", systemName: "arrow.down.to.line") { Task { await save() } }
                Button { Task { await shareSheet() } } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(accent))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
            .opacity(isExporting ? 0.5 : 1)
            .disabled(isExporting)
        }
    }

    private func actionPill(label: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemName).font(.system(size: 16, weight: .semibold))
                Text(label).font(.montserratBold(size: 14)).tracking(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule(style: .continuous).fill(.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    private func circleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(.black.opacity(0.32)))
        }
        .buttonStyle(.plain)
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

    // MARK: - Export actions

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { if toast == message { toast = nil } }
        }
    }

    private func save() async {
        isExporting = true
        defer { isExporting = false }
        guard let image = await exporter.renderImage(viewModel: viewModel) else {
            showToast("Couldn't render image")
            return
        }
        let ok = await exporter.saveToPhotos(image)
        showToast(ok ? "Saved to Photos" : "Allow Photos access to save")
    }

    private func shareSheet() async {
        isExporting = true
        defer { isExporting = false }
        guard let image = await exporter.renderImage(viewModel: viewModel) else { return }
        exporter.presentShareSheet(image: image)
    }

    private func exportToStory() async {
        isExporting = true
        defer { isExporting = false }
        guard let image = await exporter.renderImage(viewModel: viewModel) else { return }
        if !exporter.shareToInstagramStory(image) {
            exporter.presentShareSheet(image: image)
        }
    }
}

/// Bottom sheet listing the stats available to add as stickers.
private struct ShareAddStatSheet: View {
    let stats: [ResolvedShareStat]
    let onPick: (ResolvedShareStat) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add to your share")
                .font(.montserratBold(size: 18))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(stats, id: \.kind) { stat in
                        Button { onPick(stat) } label: {
                            VStack(spacing: 6) {
                                Text(stat.value)
                                    .font(.montserratBold(size: 26))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Text(stat.label)
                                    .font(.montserratSemiBold(size: 10))
                                    .tracking(1.5)
                                    .foregroundStyle(Color(red: 0.706, green: 0.8, blue: 0))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 88)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.white.opacity(0.05))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
