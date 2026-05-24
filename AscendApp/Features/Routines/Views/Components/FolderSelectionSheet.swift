import SwiftUI

// MARK: - Selectable Folder Item

private enum SelectableFolderItem: Identifiable {
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

    var folderId: UUID? {
        switch self {
        case .myRoutines:
            return nil
        case .userFolder(let folder):
            return folder.id
        }
    }

    var isDefault: Bool {
        switch self {
        case .myRoutines:
            return true
        case .userFolder:
            return false
        }
    }
}

struct FolderSelectionSheet: View {
    let folders: [RoutineFolder]
    let myRoutinesOrder: Int
    var onFolderSelected: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    /// Build ordered list of folder items respecting myRoutinesOrder position
    private var orderedFolderItems: [SelectableFolderItem] {
        var items: [SelectableFolderItem] = []
        let sortedFolders = folders.sorted { $0.order < $1.order }

        // Insert items respecting myRoutinesOrder position
        var folderIndex = 0
        for position in 0...(sortedFolders.count) {
            // Check if My Routines should be inserted at this position
            if position == myRoutinesOrder {
                items.append(.myRoutines)
            }

            // Add the next folder if available
            if folderIndex < sortedFolders.count {
                items.append(.userFolder(sortedFolders[folderIndex]))
                folderIndex += 1
            }
        }

        // If My Routines wasn't inserted (position beyond array), append at end
        if !items.contains(where: { if case .myRoutines = $0 { return true } else { return false } }) {
            items.append(.myRoutines)
        }

        return items
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(orderedFolderItems) { item in
                        FolderSelectionRow(
                            name: item.name,
                            icon: "folder.fill",
                            isDefault: item.isDefault
                        ) {
                            onFolderSelected(item.folderId)
                            dismiss()
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.black)
            .navigationTitle("Choose Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.accent)
                }
            }
        }
    }
}

// MARK: - Folder Selection Row

struct FolderSelectionRow: View {
    let name: String
    let icon: String
    let isDefault: Bool
    var onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.accent)

                Text(name)
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(.white)

                Spacer()

                if isDefault {
                    Text("Default")
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5))
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
        .buttonStyle(.plain)
    }
}

#Preview {
    FolderSelectionSheet(
        folders: [],
        myRoutinesOrder: 0,
        onFolderSelected: { _ in }
    )
    .preferredColorScheme(.dark)
}
