import SwiftUI

struct FolderOptionsSheet: View {
    let folderName: String
    let onReorderFolders: () -> Void
    let onRenameFolder: () -> Void
    let onAddNewRoutine: () -> Void
    let onDeleteFolder: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2.5)
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)

            // Folder name header
            Text(folderName)
                .font(.montserratSemiBold(size: 18))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .padding(.bottom, 20)

            // Options list
            VStack(spacing: 0) {
                // Reorder Folders
                FolderOptionRow(
                    icon: "arrow.up.arrow.down",
                    title: "Reorder Folders",
                    isDestructive: false
                ) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onReorderFolders()
                    }
                }

                Divider()
                    .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))

                // Rename Folder
                FolderOptionRow(
                    icon: "pencil",
                    title: "Rename Folder",
                    isDestructive: false
                ) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onRenameFolder()
                    }
                }

                Divider()
                    .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))

                // Add New Routine
                FolderOptionRow(
                    icon: "plus",
                    title: "Add New Routine",
                    isDestructive: false
                ) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onAddNewRoutine()
                    }
                }

                Divider()
                    .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))

                // Delete Folder
                FolderOptionRow(
                    icon: "trash",
                    title: "Delete Folder",
                    isDestructive: true
                ) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onDeleteFolder()
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(effectiveColorScheme == .dark ? .white.opacity(0.05) : .gray.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(effectiveColorScheme == .dark ? Color.jet : Color.white)
    }
}

// MARK: - Folder Option Row

private struct FolderOptionRow: View {
    let icon: String
    let title: String
    let isDestructive: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var iconColor: Color {
        if isDestructive {
            return .red.opacity(0.8)
        }
        return effectiveColorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7)
    }

    private var textColor: Color {
        if isDestructive {
            return .red.opacity(0.8)
        }
        return effectiveColorScheme == .dark ? .white : .black
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 24)

                Text(title)
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(textColor)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    FolderOptionsSheet(
        folderName: "Hyrox",
        onReorderFolders: {},
        onRenameFolder: {},
        onAddNewRoutine: {},
        onDeleteFolder: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    FolderOptionsSheet(
        folderName: "Hybrid: Lift + Run",
        onReorderFolders: {},
        onRenameFolder: {},
        onAddNewRoutine: {},
        onDeleteFolder: {}
    )
}
