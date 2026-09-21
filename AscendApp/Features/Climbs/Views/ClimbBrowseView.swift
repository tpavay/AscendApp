import SwiftUI

/// The globe with the browse sheet, pushed from a Climb Detail reached outside Home.
///
/// Home is the globe itself (`HomeView`); this screen exists for the tabs that reach a
/// Climb Detail without passing through Home and still need to browse from it. It
/// composes the same globe, drawer, sections and search as Home does.
struct ClimbBrowseView: View {
    @Bindable var viewModel: GlobeViewModel
    let analyticsEntryPoint: LiveClimbAnalyticsEvent.EntryPoint

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.tabBarOverlayHeight) private var tabBarOverlayHeight
    @State private var selectedDetailClimb: Climb?
    @State private var selectedDetailEntryPoint: LiveClimbAnalyticsEvent.EntryPoint = .unknown
    @State private var showingHelpSheet = false
    @State private var browseSheetDetent: BrowseSheetDetent = .medium
    @State private var selectedStepTier: ClimbTier?
    @State private var isSearchMode = false
    @State private var searchFocusTask: Task<Void, Never>?
    @State private var didTrackBrowseOpened = false
    @FocusState private var isSearchFocused: Bool

    init(
        viewModel: GlobeViewModel,
        analyticsEntryPoint: LiveClimbAnalyticsEvent.EntryPoint = .unknown
    ) {
        self.viewModel = viewModel
        self.analyticsEntryPoint = analyticsEntryPoint
    }

    var body: some View {
        GeometryReader { safeAreaGeometry in
            let safeAreaInsets = safeAreaGeometry.safeAreaInsets
            // The tab bar is not in the safe area the tab content sees, so the sheet
            // measures its resting heights from the bar's top, not the home indicator.
            let bottomInset = safeAreaInsets.bottom + tabBarOverlayHeight

            GeometryReader { geometry in
                let topCoverageInset = max(0, geometry.frame(in: .global).minY)
                let sheetVisibleHeight = browseSheetDetent.height(
                    containerHeight: geometry.size.height,
                    topCoverageInset: topCoverageInset,
                    topInset: safeAreaInsets.top,
                    bottomInset: bottomInset
                )

                ZStack {
                    GlobeView(
                        viewModel: viewModel,
                        onSelectClimb: { climb in
                            selectGlobePin(climb)
                        }
                    )
                    .ignoresSafeArea()
                    .offset(y: globeVerticalOffset(sheetHeight: sheetVisibleHeight))

                    GlobeEdgeOverlays()

                    if viewModel.visibleClimbs.isEmpty {
                        ClimbCatalogStateOverlay(loadErrorMessage: viewModel.loadErrorMessage)
                    }

                    topChrome(topInset: safeAreaInsets.top)

                    previewCardArea(sheetHeight: sheetVisibleHeight)
                        .zIndex(2)

                    if !isSearchMode {
                        browseDrawer(
                            containerHeight: geometry.size.height,
                            topCoverageInset: topCoverageInset,
                            topInset: safeAreaInsets.top,
                            bottomInset: bottomInset
                        )
                        .zIndex(3)
                    }

                    if isSearchMode {
                        searchOverlay(
                            topInset: safeAreaInsets.top,
                            bottomInset: bottomInset
                        )
                        .zIndex(4)
                        .transition(.opacity)
                    }
                }
                .ignoresSafeArea()
                .ignoresSafeArea(.keyboard)
            }
        }
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationDestination(item: $selectedDetailClimb) { climb in
            ClimbDetailView(
                climb: climb,
                showsBrowseBackButton: true,
                analyticsEntryPoint: selectedDetailEntryPoint
            )
        }
        .sheet(isPresented: $showingHelpSheet) {
            ClimbBrowseHelpSheet()
                .appSheetStyle(.fraction(0.8))
        }
        .task {
            viewModel.loadIfNeeded(modelContext: modelContext)
            trackBrowseOpenedIfNeeded()
        }
        .task(id: viewModel.previewSummary?.climb.id) {
            await viewModel.refreshPreviewCompletedClimberCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbStateDidChange)) { _ in
            viewModel.refresh(modelContext: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbCatalogDidChange)) { _ in
            viewModel.reloadCatalog(modelContext: modelContext)
        }
        .onDisappear {
            searchFocusTask?.cancel()
        }
        .trackOnce(screen: .climbBrowse)
    }

    private func globeVerticalOffset(sheetHeight: CGFloat) -> CGFloat {
        switch browseSheetDetent {
        case .compact:
            return 0
        case .medium, .expanded:
            return -min(max(sheetHeight * 0.25, 64), 96)
        }
    }

    // MARK: - Header

    private func topChrome(topInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    GlobeControlButton(
                        systemName: "chevron.left",
                        accessibilityLabel: "Back"
                    ) {
                        dismiss()
                    }

                    if !viewModel.mapScene.legendTiers.isEmpty {
                        ClimbStepRangeLegendView(tiers: viewModel.mapScene.legendTiers)
                    }
                }

                Spacer(minLength: 0)

                helpButton
            }
            .padding(.horizontal, 20)
            .padding(.top, topInset + 10)

            Spacer()
        }
    }

    private var helpButton: some View {
        GlobeControlButton(
            systemName: "questionmark",
            accessibilityLabel: "How Live Climbs work"
        ) {
            TelemetryManager.shared.track(LiveClimbAnalyticsEvent.browseHelpOpened)
            showingHelpSheet = true
        }
        .accessibilityHint("Open help for climb tiers, map icons, and progress rules")
    }

    // MARK: - Browse Drawer

    private func browseDrawer(
        containerHeight: CGFloat,
        topCoverageInset: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> some View {
        ClimbBrowseDrawer(
            detent: $browseSheetDetent,
            containerHeight: containerHeight,
            topCoverageInset: topCoverageInset,
            topInset: topInset,
            bottomInset: bottomInset,
            setDetent: { detent in
                setBrowseSheetDetent(detent)
            }
        ) {
            browseModeContent(bottomInset: bottomInset)
        }
    }

    private func browseModeContent(bottomInset: CGFloat) -> some View {
        VStack(spacing: 14) {
            ClimbSearchLauncher(viewModel: viewModel) {
                enterSearchMode()
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    browseSections
                }
                .padding(.bottom, bottomInset + 22)
            }
            .scrollDisabled(browseSheetDetent != .expanded)
        }
        .padding(.horizontal, 16)
    }

    private var browseSections: some View {
        ClimbBrowseSectionsView(
            viewModel: viewModel,
            selectedStepTier: $selectedStepTier,
            onOpenClimb: { climb, source in
                openClimbFromDrawer(climb, source: source)
            },
            onExpand: {
                setBrowseSheetDetent(.expanded)
            }
        )
    }

    private func searchOverlay(topInset: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                ClimbSearchField(viewModel: viewModel, isFocused: $isSearchFocused)

                Button("Cancel") {
                    exitSearchMode(clearQuery: true)
                }
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(.accent)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.top, topInset + 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    if isSearching {
                        ClimbSearchResultsView(viewModel: viewModel) { climb in
                            openClimbFromDrawer(climb, source: .browseSearch)
                        }
                    } else {
                        browseSections
                    }
                }
                .padding(.bottom, bottomInset + 22)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - Preview Card

    private func previewCardArea(sheetHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer()

            if let previewSummary = viewModel.previewSummary {
                ClimbPreviewCardView(
                    summary: previewSummary,
                    completedClimberCount: viewModel.previewCompletedClimberCount,
                    onSelect: {
                        openPreviewClimb(previewSummary.climb)
                    },
                    onClose: {
                        viewModel.dismissPreview()
                        setBrowseSheetDetent(.medium)
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, sheetHeight + 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: viewModel.previewSummary?.climb.id)
    }

    // MARK: - Actions

    private func selectGlobePin(_ climb: Climb) {
        exitSearchMode(clearQuery: true, targetDetent: .compact)
        isSearchFocused = false
        viewModel.clearSearch()
        viewModel.selectPreview(climb, modelContext: modelContext)
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.browsePreviewShown(climb: climb)
        )
        setBrowseSheetDetent(.compact)
    }

    private func openClimbFromDrawer(
        _ climb: Climb,
        source: LiveClimbAnalyticsEvent.EntryPoint
    ) {
        guard climb.isAvailable else { return }

        exitSearchMode(clearQuery: false, targetDetent: .medium)
        viewModel.previewSummary = nil
        viewModel.userDidInteract()
        selectedDetailEntryPoint = source
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.browseClimbOpened(
                climb: climb,
                entryPoint: source
            )
        )
        selectedDetailClimb = climb
    }

    private func openPreviewClimb(_ climb: Climb) {
        guard climb.isAvailable else { return }

        exitSearchMode(clearQuery: false, targetDetent: .medium)
        viewModel.userDidInteract()
        selectedDetailEntryPoint = .browsePreview
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.browseClimbOpened(
                climb: climb,
                entryPoint: .browsePreview
            )
        )
        selectedDetailClimb = climb
    }

    private func trackBrowseOpenedIfNeeded() {
        guard !didTrackBrowseOpened else { return }
        didTrackBrowseOpened = true
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.browseOpened(
                entryPoint: analyticsEntryPoint,
                totalClimbs: viewModel.climbCount
            )
        )
    }

    private func setBrowseSheetDetent(
        _ detent: BrowseSheetDetent,
        dismissKeyboard: Bool = true
    ) {
        if dismissKeyboard, detent != .expanded {
            isSearchFocused = false
        }
        if detent != .compact {
            viewModel.previewSummary = nil
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            browseSheetDetent = detent
        }
        viewModel.userDidInteract()
    }

    private func enterSearchMode() {
        searchFocusTask?.cancel()

        if viewModel.previewSummary != nil {
            viewModel.dismissPreview()
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
            isSearchMode = true
        }
        viewModel.userDidInteract()

        searchFocusTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled, isSearchMode else { return }
            isSearchFocused = true
        }
    }

    private func exitSearchMode(
        clearQuery: Bool,
        targetDetent: BrowseSheetDetent = .medium
    ) {
        searchFocusTask?.cancel()
        searchFocusTask = nil
        isSearchFocused = false

        if clearQuery {
            viewModel.clearSearch()
        }

        guard isSearchMode else { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
            isSearchMode = false
            browseSheetDetent = targetDetent
        }
        viewModel.userDidInteract()
    }

    private var isSearching: Bool {
        !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Previews

#Preview("Default") {
    NavigationStack {
        ClimbBrowseView(viewModel: {
            let vm = GlobeViewModel()
            vm.visibleClimbs = [.preview]
            return vm
        }())
    }
    .preferredColorScheme(.dark)
}

#Preview("With Preview Card") {
    NavigationStack {
        ClimbBrowseView(viewModel: {
            let vm = GlobeViewModel()
            vm.visibleClimbs = [.preview]
            vm.previewSummary = ClimbPreviewSummary(climb: .preview, isCompleted: false)
            return vm
        }())
    }
    .preferredColorScheme(.dark)
}

#Preview("With Search") {
    NavigationStack {
        ClimbBrowseView(viewModel: {
            let vm = GlobeViewModel()
            vm.visibleClimbs = [.preview]
            vm.searchQuery = "Empire"
            return vm
        }())
    }
    .preferredColorScheme(.dark)
}
