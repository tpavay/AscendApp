import SwiftUI
import SwiftData

// MARK: - Reorderable Folder Item

enum ReorderableFolderItem: Identifiable, Equatable {
    case myRoutines
    case userFolder(RoutineFolder)

    var id: String {
        switch self {
        case .myRoutines:
            return "my-routines"
        case .userFolder(let folder):
            return folder.id.uuidString
        }
    }

    var name: String {
        switch self {
        case .myRoutines:
            return "My Routines"
        case .userFolder(let folder):
            return folder.name
        }
    }

    var colorHex: String? {
        switch self {
        case .myRoutines:
            return nil
        case .userFolder(let folder):
            return folder.colorHex
        }
    }

    static func == (lhs: ReorderableFolderItem, rhs: ReorderableFolderItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct ReorderFoldersSheet: View {
    @Binding var folders: [RoutineFolder]
    let hasUnfiledRoutines: Bool
    @Binding var myRoutinesOrder: Int
    var onReorder: ([RoutineFolder], Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var reorderableItems: [ReorderableFolderItem] = []

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private func buildReorderableItems() {
        var items: [ReorderableFolderItem] = []
        let sortedFolders = folders.sorted { $0.order < $1.order }

        // If we have unfiled routines, insert "My Routines" at the correct position
        if hasUnfiledRoutines {
            // Add all folders first
            for folder in sortedFolders {
                items.append(.userFolder(folder))
            }
            // Insert My Routines at the stored position
            let insertIndex = min(max(0, myRoutinesOrder), items.count)
            items.insert(.myRoutines, at: insertIndex)
        } else {
            // No unfiled routines, just show folders
            for folder in sortedFolders {
                items.append(.userFolder(folder))
            }
        }

        reorderableItems = items
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(reorderableItems) { item in
                    ReorderFolderRow(
                        name: item.name,
                        iconName: "folder.fill",
                        colorHex: item.colorHex,
                        isDefault: false
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                }
                .onMove { indexSet, destination in
                    reorderableItems.move(fromOffsets: indexSet, toOffset: destination)
                    HapticsManager.shared.trigger(.lightImpact)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Folders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveReorderedItems()
                        dismiss()
                    }
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(.accent)
                }
            }
        }
        .onAppear {
            buildReorderableItems()
        }
    }

    private func saveReorderedItems() {
        var reorderedFolders: [RoutineFolder] = []
        var newMyRoutinesOrder = 0
        var folderIndex = 0

        for (index, item) in reorderableItems.enumerated() {
            switch item {
            case .myRoutines:
                newMyRoutinesOrder = index
            case .userFolder(let folder):
                folder.order = folderIndex
                reorderedFolders.append(folder)
                folderIndex += 1
            }
        }

        onReorder(reorderedFolders, newMyRoutinesOrder)
    }
}

// MARK: - Reorder Folder Row

private struct ReorderFolderRow: View {
    let name: String
    let iconName: String
    let colorHex: String?
    let isDefault: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.accent)

            Text(name)
                .font(.montserratMedium(size: 16))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.05) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

#Preview {
    ReorderFoldersSheet(
        folders: .constant([]),
        hasUnfiledRoutines: true,
        myRoutinesOrder: .constant(0),
        onReorder: { _, _ in }
    )
    .preferredColorScheme(.dark)
}
