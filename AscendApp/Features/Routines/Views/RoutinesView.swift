import SwiftUI
import SwiftData

struct RoutinesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared
    @State private var viewModel = RoutineListViewModel()

    @State private var selectedRoutine: Routine?
    @State private var routineToEdit: Routine?
    @State private var activeRoutine: Routine?
    @State private var showingCreateRoutine = false
    @State private var isShowingSearch = false
    @FocusState private var isSearchFocused: Bool

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var isSearching: Bool {
        !viewModel.searchText.isEmpty
    }

    private var hasSearchResults: Bool {
        !viewModel.filteredMyRoutines.isEmpty || !viewModel.filteredBuiltInRoutines.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if isShowingSearch {
                    searchField
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if viewModel.isLoading {
                    loadingState
                } else if !viewModel.searchText.isEmpty && !hasSearchResults {
                    noSearchResultsView
                } else {
                    myRoutinesSection
                    gettingStartedSection
                    popularSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
        .animation(.easeInOut(duration: 0.2), value: isShowingSearch)
        .keyboardDoneToolbar {
            isSearchFocused = false
        }
        .sheet(item: $selectedRoutine, onDismiss: {
            viewModel.loadRoutines()
        }) { routine in
            RoutineDetailView(
                routine: routine,
                onStart: {
                    selectedRoutine = nil
                    Task {
                        try await Task.sleep(for: .milliseconds(300))
                        activeRoutine = routine
                    }
                },
                onEdit: {
                    routineToEdit = routine
                    selectedRoutine = nil
                },
                onDelete: {
                    viewModel.deleteRoutine(routine)
                    HapticsManager.shared.trigger(.mediumImpact)
                }
            )
            .appSheetStyle(.large)
        }
        .sheet(isPresented: $showingCreateRoutine) {
            RoutineEditorView(
                onSave: { _ in
                    viewModel.loadRoutines()
                }
            )
            .appSheetStyle(.large)
        }
        .sheet(item: $routineToEdit) { routine in
            RoutineEditorView(
                routine: routine,
                onSave: { updatedRoutine in
                    viewModel.refreshRoutine(updatedRoutine.id)
                    viewModel.loadRoutines()
                }
            )
            .appSheetStyle(.large)
        }
        .fullScreenCover(item: $activeRoutine) { routine in
            ActiveRoutineView(routine: routine)
        }
        .onAppear {
            viewModel.configure(modelContext: modelContext)
            viewModel.loadRoutines()
        }
        .onReceive(NotificationCenter.default.publisher(for: .routineTemplatesDidChange)) { _ in
            viewModel.loadRoutines()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                OnboardingBackButton {
                    dismiss()
                }

                Spacer()

                HStack(spacing: 18) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isShowingSearch.toggle()
                            if !isShowingSearch {
                                viewModel.searchText = ""
                                isSearchFocused = false
                            }
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingCreateRoutine = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Routines")
                .font(.montserratBold(size: 32))
                .foregroundStyle(.white)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.customGray)

            TextField("Search routines...", text: $viewModel.searchText)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.done)
                .focused($isSearchFocused)
                .onSubmit {
                    isSearchFocused = false
                }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.jetLighter.opacity(0.62))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSearchFocused ? Color.accent : .white.opacity(0.08), lineWidth: 1)
                )
        )
        .onAppear {
            isSearchFocused = true
        }
    }

    private var myRoutinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("MY ROUTINES")

            if viewModel.hasMyRoutines {
                if isSearching {
                    VStack(spacing: 10) {
                        ForEach(viewModel.filteredMyRoutines) { routine in
                            RoutineListCard(
                                routine: routine,
                                isSaved: routine.source == .copiedFromBuiltin,
                                showsBookmark: routine.source == .copiedFromBuiltin,
                                showsChevron: true,
                                onBookmarkTap: routine.source == .copiedFromBuiltin ? {
                                    viewModel.toggleSavedRoutine(routine)
                                    HapticsManager.shared.trigger(.lightImpact)
                                } : nil,
                                onTap: {
                                    selectedRoutine = routine
                                }
                            )
                        }
                    }
                } else {
                    RoutineHorizontalRail(routines: viewModel.filteredMyRoutines) { routine in
                        RoutineThumbnailCard(
                            routine: routine,
                            width: 208,
                            height: 118,
                            chartHeight: 40,
                            widthMode: .proportionalToDuration,
                            showsLevelRange: true,
                            isSaved: routine.source == .copiedFromBuiltin,
                            showsBookmark: routine.source == .copiedFromBuiltin,
                            onBookmarkTap: routine.source == .copiedFromBuiltin ? {
                                viewModel.toggleSavedRoutine(routine)
                                HapticsManager.shared.trigger(.lightImpact)
                            } : nil,
                            onTap: {
                                selectedRoutine = routine
                            }
                        )
                    }
                }
            } else {
                RoutineGhostCard()
            }
        }
    }

    @ViewBuilder
    private var gettingStartedSection: some View {
        let routines = viewModel.filteredBuiltInRoutines(in: .gettingStarted)
        if !isSearching && !routines.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel(BuiltInRoutineBrowseSection.gettingStarted.title)

                RoutineHorizontalRail(routines: routines) { routine in
                    RoutineThumbnailCard(
                        routine: routine,
                        width: 208,
                        height: 118,
                        chartHeight: 40,
                        widthMode: .proportionalToDuration,
                        showsLevelRange: true,
                        isSaved: viewModel.isRoutineSaved(routine),
                        showsBookmark: true,
                        onBookmarkTap: {
                            viewModel.toggleSavedRoutine(routine)
                            HapticsManager.shared.trigger(.lightImpact)
                        },
                        onTap: {
                            selectedRoutine = routine
                        }
                    )
                }
            }
        }
    }

    private var popularSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(isSearching ? "BUILT-IN" : "POPULAR")

            if isSearching {
                VStack(spacing: 10) {
                    ForEach(viewModel.filteredBuiltInRoutines) { routine in
                        RoutineListCard(
                            routine: routine,
                            isSaved: viewModel.isRoutineSaved(routine),
                            showsBookmark: true,
                            showsChevron: true,
                            onBookmarkTap: {
                                viewModel.toggleSavedRoutine(routine)
                            },
                            onTap: {
                                selectedRoutine = routine
                            }
                        )
                    }
                }
            } else {
                RoutineHorizontalRail(routines: viewModel.filteredFeaturedBuiltInRoutines) { routine in
                    RoutineThumbnailCard(
                        routine: routine,
                        width: 208,
                        height: 118,
                        chartHeight: 40,
                        widthMode: .proportionalToDuration,
                        showsLevelRange: true,
                        isSaved: viewModel.isRoutineSaved(routine),
                        showsBookmark: true,
                        onBookmarkTap: {
                            viewModel.toggleSavedRoutine(routine)
                        },
                        onTap: {
                            selectedRoutine = routine
                        }
                    )
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.montserratSemiBold(size: 12))
            .tracking(0.8)
            .foregroundStyle(Color.customGray)
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(.white.opacity(0.7))

            Text("Loading routines...")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(Color.customGray)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var noSearchResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.3))

            Text("No routines found")
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(.white)

            Text("Try a different search term.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(Color.customGray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

#Preview {
    NavigationStack {
        RoutinesView()
    }
    .preferredColorScheme(.dark)
}
