import SwiftUI

struct ClimbBrowseView: View {
    @Bindable var viewModel: GlobeViewModel
    let analyticsEntryPoint: LiveClimbAnalyticsEvent.EntryPoint

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var selectedDetailClimb: Climb?
    @State private var selectedDetailEntryPoint: LiveClimbAnalyticsEvent.EntryPoint = .unknown
    @State private var showingHelpSheet = false
    @State private var browseSheetDetent: BrowseSheetDetent = .medium
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
        GeometryReader { geometry in
            let sheetVisibleHeight = browseSheetDetent.height(
                containerHeight: geometry.size.height,
                topInset: geometry.safeAreaInsets.top,
                bottomInset: geometry.safeAreaInsets.bottom
            )

            ZStack {
                GlobeView(
                    viewModel: viewModel,
                    onSelectClimb: { climb in
                        selectGlobePin(climb)
                    }
                )
                .ignoresSafeArea()

                globeEdgeOverlays

                if viewModel.visibleClimbs.isEmpty {
                    catalogStateOverlay
                }

                topChrome

                previewCardArea(sheetHeight: sheetVisibleHeight)
                    .zIndex(2)

                browseDrawer(in: geometry)
                    .zIndex(3)
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
        .onReceive(NotificationCenter.default.publisher(for: .climbStateDidChange)) { _ in
            viewModel.refresh(modelContext: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbCatalogDidChange)) { _ in
            viewModel.reloadCatalog(modelContext: modelContext)
        }
        .onChange(of: isSearchFocused) { _, isFocused in
            guard isFocused else { return }
            if viewModel.previewSummary != nil {
                viewModel.dismissPreview()
            }
            setBrowseSheetDetent(.expanded, dismissKeyboard: false)
        }
        .onChange(of: viewModel.searchQuery) { _, query in
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if viewModel.previewSummary != nil {
                viewModel.dismissPreview()
            }
            setBrowseSheetDetent(.expanded, dismissKeyboard: false)
        }
        .keyboardDoneToolbar {
            isSearchFocused = false
        }
    }

    // MARK: - Edge Overlays

    private var globeEdgeOverlays: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.94),
                    Color.black.opacity(0.58),
                    Color.black.opacity(0.16),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 188)

            Spacer()

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.42), Color.black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 176)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Header

    private var topChrome: some View {
        VStack(spacing: 0) {
            HStack {
                globeControlButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "Back"
                ) {
                    dismiss()
                }

                Spacer(minLength: 0)

                helpButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .safeAreaPadding(.top)

            Spacer()
        }
    }

    private var helpButton: some View {
        globeControlButton(
            systemName: "questionmark",
            accessibilityLabel: "How Live Climbs work"
        ) {
            showingHelpSheet = true
        }
        .accessibilityHint("Open help for climb tiers, map icons, and progress rules")
    }

    private func globeControlButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.46))
                )
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.36), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Browse Drawer

    private func browseDrawer(in geometry: GeometryProxy) -> some View {
        ClimbBrowseDrawer(
            detent: $browseSheetDetent,
            containerHeight: geometry.size.height,
            topInset: geometry.safeAreaInsets.top,
            bottomInset: geometry.safeAreaInsets.bottom,
            setDetent: { detent in
                setBrowseSheetDetent(detent)
            }
        ) {
            drawerContent(bottomInset: geometry.safeAreaInsets.bottom)
        }
    }

    private func drawerContent(bottomInset: CGFloat) -> some View {
        VStack(spacing: 14) {
            searchField

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    if isSearching {
                        searchResultsContent
                    } else {
                        browseSectionsContent
                    }
                }
                .padding(.bottom, bottomInset + 22)
            }
            .scrollDisabled(browseSheetDetent != .expanded)
        }
        .padding(.horizontal, 16)
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))

            TextField("Search climbs", text: $viewModel.searchQuery)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)
                .onSubmit(openFirstSearchResult)

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.48))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            } else if viewModel.isRefreshingCatalog {
                ProgressView()
                    .tint(.white.opacity(0.76))
                    .scaleEffect(0.78)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isSearchFocused ? 0.1 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(isSearchFocused ? 0.2 : 0.1), lineWidth: 1)
        )
        .disabled(viewModel.visibleClimbs.isEmpty)
    }

    // MARK: - Search Results

    private var searchResultsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Results")

            if viewModel.searchSuggestions.isEmpty {
                noSearchResultsView
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.searchSuggestions) { climb in
                        climbResultRow(for: climb, source: .browseSearch)
                    }
                }
            }
        }
    }

    private var noSearchResultsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No climbs found")
                .font(.montserratSemiBold(size: 15))
                .foregroundStyle(.white.opacity(0.86))

            Text("Try a landmark, city, country, or category.")
                .font(.montserratRegular(size: 13))
                .foregroundStyle(.white.opacity(0.54))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }

    // MARK: - Browse Sections

    private var browseSectionsContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            horizontalClimbSection(title: "Popular", climbs: popularClimbs, showsSeeAll: true)
            horizontalClimbSection(title: "Easiest", climbs: easiestClimbs)
            horizontalClimbSection(title: "Hardest", climbs: hardestClimbs)

            if !completedClimbs.isEmpty {
                horizontalClimbSection(title: "Completed", climbs: completedClimbs)
            }

            allClimbsSection
        }
    }

    private func horizontalClimbSection(
        title: String,
        climbs: [Climb],
        showsSeeAll: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(title)

                Spacer(minLength: 0)

                if showsSeeAll {
                    Button {
                        setBrowseSheetDetent(.expanded)
                    } label: {
                        Text("See all")
                            .font(.montserratBold(size: 11))
                            .foregroundStyle(.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(climbs) { climb in
                        climbBrowseCard(for: climb, source: .browseSection)
                    }
                }
                .padding(.trailing, 2)
            }
        }
    }

    private var allClimbsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("All Climbs")

            VStack(spacing: 8) {
                ForEach(allClimbs) { climb in
                    climbResultRow(for: climb, source: .browseAll)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.montserratBold(size: 10))
            .tracking(1.4)
            .foregroundStyle(.white.opacity(0.56))
            .lineLimit(1)
    }

    private func climbBrowseCard(
        for climb: Climb,
        source: LiveClimbAnalyticsEvent.EntryPoint
    ) -> some View {
        Button {
            openClimbFromDrawer(climb, source: source)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    ClimbArtworkView(climb: climb, variant: .thumb)
                        .frame(height: 76)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 8,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 8,
                                style: .continuous
                            )
                        )

                    if viewModel.isCompleted(climb) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.accent))
                            .padding(6)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(climb.name)
                        .font(.montserratBold(size: 11.5))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text("\(climb.referenceStepCount.formatted()) steps")
                        .font(.montserratMedium(size: 10.5))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.bottom, 9)
            }
            .frame(width: 124, height: 150, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(climb.tier.color.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(climb.name), \(climb.displayLocation)")
        .accessibilityHint("Open climb detail")
    }

    private func climbResultRow(
        for climb: Climb,
        source: LiveClimbAnalyticsEvent.EntryPoint
    ) -> some View {
        Button {
            openClimbFromDrawer(climb, source: source)
        } label: {
            HStack(spacing: 12) {
                ClimbArtworkView(climb: climb, variant: .thumb)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(climb.name)
                            .font(.montserratSemiBold(size: 14))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.86)

                        if viewModel.isCompleted(climb) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.accent)
                        }
                    }

                    Text(climb.displayLocation)
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(climb.referenceStepCount.formatted())
                        .font(.montserratBold(size: 13))
                        .foregroundStyle(climb.tier.color)

                    Text("steps")
                        .font(.montserratMedium(size: 9))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(climb.name), \(climb.displayLocation)")
        .accessibilityHint("Open climb detail")
    }

    // MARK: - Preview Card

    private func previewCardArea(sheetHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer()

            if let previewSummary = viewModel.previewSummary {
                ClimbPreviewCardView(
                    summary: previewSummary,
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

    // MARK: - Loading & Error States

    private var catalogStateOverlay: some View {
        VStack(spacing: 12) {
            if let loadErrorMessage = viewModel.loadErrorMessage {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Text("Climbs Unavailable")
                    .font(.montserratSemiBold(size: 18))
                    .foregroundStyle(.white)

                Text(loadErrorMessage)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.05)

                Text("Loading climbs...")
                    .font(.montserratSemiBold(size: 17))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.52))
        )
        .padding(.horizontal, 24)
    }

    // MARK: - Actions

    private func selectGlobePin(_ climb: Climb) {
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
        isSearchFocused = false
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
        isSearchFocused = false
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

    private func openFirstSearchResult() {
        guard let firstResult = viewModel.searchSuggestions.first else { return }
        openClimbFromDrawer(firstResult, source: .browseSearch)
    }

    private func trackBrowseOpenedIfNeeded() {
        guard !didTrackBrowseOpened else { return }
        didTrackBrowseOpened = true
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.browseOpened(
                entryPoint: analyticsEntryPoint,
                totalClimbs: viewModel.visibleClimbs.count
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


    // MARK: - Section Data

    private var isSearching: Bool {
        !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var popularClimbs: [Climb] {
        let featured = viewModel.firstFeaturedClimb.map { [$0] } ?? []
        let tiered = viewModel.visibleClimbs.sorted { lhs, rhs in
            if lhs.tier == rhs.tier {
                return lhs.referenceStepCount < rhs.referenceStepCount
            }
            return lhs.tier > rhs.tier
        }
        return Array(uniqueClimbs(featured + tiered).prefix(10))
    }

    private var easiestClimbs: [Climb] {
        Array(
            viewModel.visibleClimbs
                .sorted { lhs, rhs in
                    if lhs.referenceStepCount == rhs.referenceStepCount {
                        return lhs.name < rhs.name
                    }
                    return lhs.referenceStepCount < rhs.referenceStepCount
                }
                .prefix(10)
        )
    }

    private var hardestClimbs: [Climb] {
        Array(
            viewModel.visibleClimbs
                .sorted { lhs, rhs in
                    if lhs.referenceStepCount == rhs.referenceStepCount {
                        return lhs.name < rhs.name
                    }
                    return lhs.referenceStepCount > rhs.referenceStepCount
                }
                .prefix(10)
        )
    }

    private var completedClimbs: [Climb] {
        Array(
            viewModel.visibleClimbs
                .filter { viewModel.isCompleted($0) }
                .sorted { lhs, rhs in
                    if lhs.tier == rhs.tier {
                        return lhs.name < rhs.name
                    }
                    return lhs.tier > rhs.tier
                }
                .prefix(10)
        )
    }

    private var allClimbs: [Climb] {
        viewModel.visibleClimbs.sorted { lhs, rhs in
            if lhs.referenceStepCount == rhs.referenceStepCount {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return lhs.referenceStepCount < rhs.referenceStepCount
        }
    }

    private func uniqueClimbs(_ climbs: [Climb]) -> [Climb] {
        var seenIds = Set<String>()
        return climbs.filter { climb in
            seenIds.insert(climb.id).inserted
        }
    }
}

private struct ClimbBrowseDrawer<Content: View>: View {
    @Binding var detent: BrowseSheetDetent

    let containerHeight: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    let setDetent: (BrowseSheetDetent) -> Void
    let content: Content

    @State private var currentOffset: CGFloat?
    @State private var dragStartOffset: CGFloat?

    init(
        detent: Binding<BrowseSheetDetent>,
        containerHeight: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat,
        setDetent: @escaping (BrowseSheetDetent) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self._detent = detent
        self.containerHeight = containerHeight
        self.topInset = topInset
        self.bottomInset = bottomInset
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
            .ignoresSafeArea(.container, edges: .bottom)
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
            content
        }
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
        .accessibilityLabel("Browse climbs drawer")
        .accessibilityHint("Drag to expand or collapse browse controls")

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
        UnevenRoundedRectangle(
            topLeadingRadius: 24,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 24,
            style: .continuous
        )
    }

    private var expandedHeight: CGFloat {
        BrowseSheetDetent.expanded.height(
            containerHeight: containerHeight,
            topInset: topInset,
            bottomInset: bottomInset
        )
    }

    private var activeOffset: CGFloat {
        currentOffset ?? restingOffset
    }

    private var restingOffset: CGFloat {
        detent.offset(
            containerHeight: containerHeight,
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
        let targetDetent: BrowseSheetDetent

        if abs(velocity) > velocityThreshold {
            targetDetent = velocity < 0 ? detent.nextUp : detent.nextDown
        } else {
            targetDetent = BrowseSheetDetent.nearest(
                to: releaseOffset,
                containerHeight: containerHeight,
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
                topInset: topInset,
                bottomInset: bottomInset
            )
        }

        setDetent(targetDetent)
    }
}

private enum BrowseSheetDetent: Int, CaseIterable {
    case compact
    case medium
    case expanded

    func height(
        containerHeight: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> CGFloat {
        let maxHeight = max(320, containerHeight - topInset - 76)

        switch self {
        case .compact:
            return min(maxHeight, 86 + bottomInset)
        case .medium:
            return min(maxHeight, max(286 + bottomInset, containerHeight * 0.36))
        case .expanded:
            return maxHeight
        }
    }

    func offset(
        containerHeight: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> CGFloat {
        BrowseSheetDetent.expanded.height(
            containerHeight: containerHeight,
            topInset: topInset,
            bottomInset: bottomInset
        ) - height(
            containerHeight: containerHeight,
            topInset: topInset,
            bottomInset: bottomInset
        )
    }

    static func clampedOffset(
        _ offset: CGFloat,
        containerHeight: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> CGFloat {
        min(
            max(
                offset,
                BrowseSheetDetent.expanded.offset(
                    containerHeight: containerHeight,
                    topInset: topInset,
                    bottomInset: bottomInset
                )
            ),
            BrowseSheetDetent.compact.offset(
                containerHeight: containerHeight,
                topInset: topInset,
                bottomInset: bottomInset
            )
        )
    }

    static func nearest(
        to offset: CGFloat,
        containerHeight: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> BrowseSheetDetent {
        allCases.min { lhs, rhs in
            abs(
                lhs.offset(
                    containerHeight: containerHeight,
                    topInset: topInset,
                    bottomInset: bottomInset
                ) - offset
            )
            < abs(
                rhs.offset(
                    containerHeight: containerHeight,
                    topInset: topInset,
                    bottomInset: bottomInset
                ) - offset
            )
        } ?? .medium
    }

    var nextUp: BrowseSheetDetent {
        switch self {
        case .compact:
            return .medium
        case .medium, .expanded:
            return .expanded
        }
    }

    var nextDown: BrowseSheetDetent {
        switch self {
        case .compact, .medium:
            return .compact
        case .expanded:
            return .medium
        }
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
            vm.previewSummary = ClimbPreviewSummary(climb: .preview, isCompleted: false, isActive: false)
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
