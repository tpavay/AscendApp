import SwiftUI
import SwiftData

// Wrapper to hold selected folder for new routine creation
struct NewRoutineFolderSelection: Identifiable {
    let id = UUID()
    let folderId: UUID?
}

struct RoutinesView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared
    @State private var viewModel = RoutineListViewModel()

    @State private var selectedRoutine: Routine?
    @State private var routineToEdit: Routine?
    @State private var activeRoutine: Routine?
    @State private var showingCreateFolderDialog = false
    @State private var showingFolderSelection = false
    @State private var showingExploreRoutines = false
    @State private var showingReorderFolders = false
    @State private var newRoutineFolderSelection: NewRoutineFolderSelection?
    @State private var expandedFolderIds: Set<String> = []

    // Folder options state
    @State private var selectedFolderForOptions: RoutineFolder?
    @State private var folderToRename: RoutineFolder?

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Action Buttons
                RoutineActionButtons(
                    onCreateRoutine: {
                        showingFolderSelection = true
                    },
                    onExploreRoutines: {
                        showingExploreRoutines = true
                    }
                )

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
                Button(action: { showingCreateFolderDialog = true }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 16, weight: .medium))
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
                    Task {
                        try await Task.sleep(for: .milliseconds(300))
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
        .sheet(item: $newRoutineFolderSelection) { selection in
            RoutineEditorView(
                folderId: selection.folderId,
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
        .sheet(isPresented: $showingFolderSelection) {
            FolderSelectionSheet(
                folders: viewModel.folders,
                myRoutinesOrder: viewModel.myRoutinesOrder
            ) { folderId in
                showingFolderSelection = false
                Task {
                    try await Task.sleep(for: .milliseconds(300))
                    newRoutineFolderSelection = NewRoutineFolderSelection(folderId: folderId)
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingExploreRoutines) {
            ExploreRoutinesView(
                routines: viewModel.builtInRoutines,
                onRoutineSelected: { routine in
                    showingExploreRoutines = false
                    Task {
                        try await Task.sleep(for: .milliseconds(300))
                        selectedRoutine = routine
                    }
                },
                onCopyRoutine: { routine in
                    viewModel.copyBuiltInRoutine(routine)
                    HapticsManager.shared.trigger(.success)
                }
            )
        }
        .sheet(isPresented: $showingCreateFolderDialog) {
            CreateFolderDialog(isPresented: $showingCreateFolderDialog) { folderName in
                viewModel.createFolder(name: folderName)
                HapticsManager.shared.trigger(.success)
            }
            .presentationDetents([.height(220)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingReorderFolders) {
            ReorderFoldersSheet(
                folders: $viewModel.folders,
                hasUnfiledRoutines: !viewModel.userRoutines.filter { $0.folderId == nil }.isEmpty,
                myRoutinesOrder: Binding(
                    get: { viewModel.myRoutinesOrder },
                    set: { viewModel.myRoutinesOrder = $0 }
                )
            ) { reorderedFolders, myRoutinesPosition in
                viewModel.saveFolderOrder(reorderedFolders, myRoutinesPosition: myRoutinesPosition)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedFolderForOptions) { folder in
            FolderOptionsSheet(
                folderName: folder.name,
                onReorderFolders: {
                    selectedFolderForOptions = nil
                    Task {
                        try await Task.sleep(for: .milliseconds(300))
                        showingReorderFolders = true
                    }
                },
                onRenameFolder: {
                    let folderToRename = folder
                    selectedFolderForOptions = nil
                    Task {
                        try await Task.sleep(for: .milliseconds(300))
                        self.folderToRename = folderToRename
                    }
                },
                onAddNewRoutine: {
                    let folderId = folder.id
                    selectedFolderForOptions = nil
                    Task {
                        try await Task.sleep(for: .milliseconds(300))
                        newRoutineFolderSelection = NewRoutineFolderSelection(folderId: folderId)
                    }
                },
                onDeleteFolder: {
                    viewModel.deleteFolder(folder)
                    selectedFolderForOptions = nil
                    HapticsManager.shared.trigger(.mediumImpact)
                }
            )
            .presentationDetents([.height(340)])
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $folderToRename) { folder in
            RenameFolderDialog(
                isPresented: Binding(
                    get: { folderToRename != nil },
                    set: { if !$0 { folderToRename = nil } }
                ),
                currentName: folder.name
            ) { newName in
                viewModel.renameFolder(folder, newName: newName)
                folderToRename = nil
                HapticsManager.shared.trigger(.success)
            }
            .presentationDetents([.height(220)])
            .presentationDragIndicator(.visible)
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
            // Content
            if viewModel.isLoading {
                loadingState
            } else if viewModel.filteredUserRoutines.isEmpty && viewModel.folders.isEmpty {
                if viewModel.searchText.isEmpty {
                    EmptyRoutinesView(onCreateRoutine: { showingFolderSelection = true })
                } else {
                    noSearchResultsView
                }
            } else {
                VStack(spacing: 16) {
                    ForEach(viewModel.routinesByFolder) { group in
                        folderSection(group: group)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func folderSection(group: RoutineFolderGroup) -> some View {
        let filteredRoutines = filterRoutines(group.routines)
        let isExpanded = expandedFolderIds.contains(group.id)
        let displayName = group.isUnfiled ? "My Routines" : group.name

        // Don't show empty unfiled section
        if !filteredRoutines.isEmpty || !group.isUnfiled {
            VStack(alignment: .leading, spacing: 12) {
                // Folder header - show for all sections including unfiled
                HStack {
                    Button(action: { toggleFolderExpanded(group.id) }) {
                        HStack(spacing: 8) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)

                            Text(displayName)
                                .font(.montserratSemiBold(size: 20))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                            Text("(\(filteredRoutines.count))")
                                .font(.montserratRegular(size: 16))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in
                                HapticsManager.shared.trigger(.mediumImpact)
                                showingReorderFolders = true
                            }
                    )

                    // Three-dot menu button (only for user folders, not "My Routines")
                    if let folder = group.folder {
                        Button {
                            selectedFolderForOptions = folder
                            HapticsManager.shared.trigger(.lightImpact)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Routines in this folder (collapsible)
                if isExpanded {
                    if filteredRoutines.isEmpty {
                        Text("No routines in this folder")
                            .font(.montserratRegular(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray)
                            .padding(.vertical, 8)
                    } else {
                        ReorderableRoutineList(
                            initialRoutines: filteredRoutines,
                            onRoutineTapped: { routine in
                                selectedRoutine = routine
                            },
                            onReorder: { reorderedRoutines in
                                viewModel.saveRoutineOrder(reorderedRoutines)
                            }
                        )
                    }
                }
            }
        }
    }

    private func toggleFolderExpanded(_ folderId: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedFolderIds.contains(folderId) {
                expandedFolderIds.remove(folderId)
            } else {
                expandedFolderIds.insert(folderId)
            }
        }
        HapticsManager.shared.trigger(.lightImpact)
    }

    private func filterRoutines(_ routines: [Routine]) -> [Routine] {
        if viewModel.searchText.isEmpty {
            return routines
        }
        return routines.filter {
            $0.name.localizedCaseInsensitiveContains(viewModel.searchText)
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
