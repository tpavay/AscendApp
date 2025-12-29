import SwiftUI
import SwiftData

struct RoutinesView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared
    @State private var viewModel = RoutineListViewModel()

    @State private var showingEditor = false
    @State private var selectedRoutine: Routine?
    @State private var routineToEdit: Routine?
    @State private var activeRoutine: Routine?

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Built-in Templates Section
                if !viewModel.filteredBuiltInRoutines.isEmpty {
                    BuiltInRoutineSection(
                        routines: viewModel.filteredBuiltInRoutines,
                        onRoutineSelected: { routine in
                            selectedRoutine = routine
                        },
                        onCopyRoutine: { routine in
                            viewModel.copyBuiltInRoutine(routine)
                            HapticsManager.shared.trigger(.success)
                        }
                    )
                }

                // My Routines Section
                myRoutinesSection
            }
            .padding(20)
        }
        .background(effectiveColorScheme == .dark ? Color.jet : Color.white)
        .navigationTitle("Routines")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showingEditor = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.accent)
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search routines")
        .sheet(item: $selectedRoutine) { routine in
            RoutineDetailView(
                routine: routine,
                onStart: {
                    selectedRoutine = nil
                    // Small delay to let sheet dismiss before presenting fullScreenCover
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        activeRoutine = routine
                    }
                },
                onEdit: {
                    routineToEdit = routine
                    selectedRoutine = nil
                },
                onCopy: {
                    viewModel.copyBuiltInRoutine(routine)
                    HapticsManager.shared.trigger(.success)
                },
                onDelete: {
                    viewModel.deleteRoutine(routine)
                    HapticsManager.shared.trigger(.mediumImpact)
                }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingEditor) {
            RoutineEditorView(
                onSave: { routine in
                    viewModel.loadRoutines()
                }
            )
        }
        .sheet(item: $routineToEdit) { routine in
            RoutineEditorView(
                routine: routine,
                onSave: { updatedRoutine in
                    viewModel.refreshRoutine(updatedRoutine.id)
                }
            )
        }
        .fullScreenCover(item: $activeRoutine) { routine in
            ActiveRoutineView(routine: routine)
        }
        .onAppear {
            viewModel.configure(modelContext: modelContext)
            viewModel.loadRoutines()
        }
    }

    // MARK: - My Routines Section

    private var myRoutinesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Text("My Routines")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()

                if viewModel.userRoutineCount > 0 {
                    Text("\(viewModel.userRoutineCount) routine\(viewModel.userRoutineCount == 1 ? "" : "s")")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                }
            }

            // Content
            if viewModel.isLoading {
                loadingState
            } else if viewModel.filteredUserRoutines.isEmpty {
                if viewModel.searchText.isEmpty {
                    EmptyRoutinesView(onCreateRoutine: { showingEditor = true })
                } else {
                    noSearchResultsView
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.filteredUserRoutines) { routine in
                        RoutineCard(routine: routine) {
                            selectedRoutine = routine
                        }
                    }
                }
            }
        }
    }

    private var loadingState: some View {
        HStack {
            ProgressView()
                .tint(effectiveColorScheme == .dark ? .white : .gray)
            Text("Loading routines...")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    private var noSearchResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.4))

            Text("No routines found")
                .font(.montserratMedium(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)

            Text("Try a different search term")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray.opacity(0.7))
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        RoutinesView()
    }
}

#Preview("Dark Mode") {
    NavigationStack {
        RoutinesView()
    }
    .preferredColorScheme(.dark)
}
