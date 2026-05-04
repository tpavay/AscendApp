import SwiftUI

struct ClimbBrowseView: View {
    @Bindable var viewModel: GlobeViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var selectedDetailClimb: Climb?
    @State private var showingHelpSheet = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            GlobeView(
                viewModel: viewModel,
                onSelectClimb: { climb in
                    viewModel.selectPreview(climb, modelContext: modelContext)
                }
            )
            .ignoresSafeArea()

            globeEdgeOverlays

            if viewModel.visibleClimbs.isEmpty {
                catalogStateOverlay
            }

            VStack(spacing: 0) {
                topChrome
                Spacer()
                previewCardArea
            }
        }
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationDestination(item: $selectedDetailClimb) { climb in
            ClimbDetailView(climb: climb, showsBrowseBackButton: true)
        }
        .sheet(isPresented: $showingHelpSheet) {
            ClimbBrowseHelpSheet()
                .appSheetStyle(.fraction(0.8))
        }
        .task {
            viewModel.loadIfNeeded(modelContext: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbStateDidChange)) { _ in
            viewModel.refresh(modelContext: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbCatalogDidChange)) { _ in
            viewModel.reloadCatalog(modelContext: modelContext)
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
                    Color.black.opacity(0.96),
                    Color.black.opacity(0.74),
                    Color.black.opacity(0.28),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 250)

            Spacer()

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.56), Color.black.opacity(0.96)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Header & Search

    private var topChrome: some View {
        VStack(alignment: .leading, spacing: 18) {
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

            VStack(alignment: .leading, spacing: 12) {
                Text("Live Climbs")
                    .font(.montserratBold(size: 32))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .shadow(color: .black.opacity(0.72), radius: 12, x: 0, y: 3)

                HStack(spacing: 10) {
                    searchField

                    if viewModel.isRefreshingCatalog {
                        ProgressView()
                            .tint(.white.opacity(0.88))
                            .scaleEffect(0.85)
                    }
                }

                if !viewModel.searchSuggestions.isEmpty {
                    suggestionsList
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .safeAreaPadding(.top)
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

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.66))

            TextField("Search climbs", text: $viewModel.searchQuery)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.clearSearchAndResetCamera()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.48))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(isSearchFocused ? 0.72 : 0.54))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(isSearchFocused ? 0.22 : 0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.34), radius: 14, x: 0, y: 5)
        .disabled(viewModel.visibleClimbs.isEmpty)
    }

    // MARK: - Suggestions

    private var suggestionsList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(viewModel.searchSuggestions) { climb in
                    Button {
                        viewModel.selectSuggestion(climb, modelContext: modelContext)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(climb.name)
                                    .font(.montserratSemiBold(size: 15))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text("\(climb.city), \(climb.country)")
                                    .font(.montserratRegular(size: 13))
                                    .foregroundStyle(.white.opacity(0.64))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Text(climb.referenceStepCount.formatted())
                                .font(.montserratSemiBold(size: 13))
                                .foregroundStyle(climb.tier.color)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .frame(maxHeight: 212)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.4))
        )
        .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
    }

    // MARK: - Preview Card

    private var previewCardArea: some View {
        Group {
            if let previewSummary = viewModel.previewSummary {
                ClimbPreviewCardView(
                    summary: previewSummary,
                    onSelect: {
                        selectedDetailClimb = previewSummary.climb
                    },
                    onClose: {
                        viewModel.dismissPreview()
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
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

                Text("Loading climbs…")
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
