import SwiftUI
import SwiftData

struct ReorderFoldersSheet: View {
    @Binding var folders: [RoutineFolder]
    let hasUnfiledRoutines: Bool
    var onReorder: ([RoutineFolder]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            List {
                // My Routines section (always first, not moveable)
                if hasUnfiledRoutines {
                    ReorderFolderRow(
                        name: "My Routines",
                        iconName: "folder",
                        colorHex: nil,
                        isDefault: true
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                    .moveDisabled(true)
                }

                // User-created folders (can be reordered)
                ForEach(folders) { folder in
                    ReorderFolderRow(
                        name: folder.name,
                        iconName: "folder.fill",
                        colorHex: folder.colorHex,
                        isDefault: false
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                }
                .onMove { indexSet, destination in
                    folders.move(fromOffsets: indexSet, toOffset: destination)
                    HapticsManager.shared.trigger(.lightImpact)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(effectiveColorScheme == .dark ? Color.jet : Color.white)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Folders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onReorder(folders)
                        dismiss()
                    }
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(.accent)
                }
            }
        }
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

    private var iconColor: Color {
        if let hex = colorHex {
            return Color(hex: hex)
        }
        return .accent
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(iconColor)

            Text(name)
                .font(.montserratMedium(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            Spacer()

            if isDefault {
                Text("Always First")
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray)
            }
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
        onReorder: { _ in }
    )
    .preferredColorScheme(.dark)
}
