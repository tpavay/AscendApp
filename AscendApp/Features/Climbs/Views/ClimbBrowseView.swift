import SwiftUI

struct ClimbBrowseView: View {
    @Bindable var viewModel: GlobeViewModel

    @Environment(\.modelContext) private var modelContext
    @State private var selectedDetailClimb: Climb?

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
                headerAndSearch
                Spacer()
                previewCardArea
            }
        }
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .navigationDestination(item: $selectedDetailClimb) { climb in
            ClimbDetailView(climb: climb, showsBrowseBackButton: true)
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
    }

    // MARK: - Edge Overlays

    private var globeEdgeOverlays: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.night.opacity(0.85), Color.night.opacity(0.4), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)

            Spacer()

            LinearGradient(
                colors: [.clear, Color.night.opacity(0.6), Color.night.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 160)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Header & Search

    private var headerAndSearch: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Climb Anything")
                .font(.montserratBold(size: 28))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 2)

            searchField

            if viewModel.isRefreshingCatalog {
                ProgressView()
                    .tint(.white.opacity(0.9))
                    .scaleEffect(0.85)
            }

            if !viewModel.searchSuggestions.isEmpty {
                suggestionsList
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

            TextField("Search climbs", text: $viewModel.searchQuery)
                .font(.montserratMedium(size: 15))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)

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
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
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
