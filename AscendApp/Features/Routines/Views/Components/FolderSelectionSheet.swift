import SwiftUI

struct FolderSelectionSheet: View {
    let folders: [RoutineFolder]
    var onFolderSelected: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Default "My Routines" option (nil folderId)
                    FolderSelectionRow(
                        name: "My Routines",
                        icon: "folder",
                        isDefault: true
                    ) {
                        onFolderSelected(nil)
                        dismiss()
                    }

                    // User-created folders
                    ForEach(folders) { folder in
                        FolderSelectionRow(
                            name: folder.name,
                            icon: "folder.fill",
                            colorHex: folder.colorHex,
                            isDefault: false
                        ) {
                            onFolderSelected(folder.id)
                            dismiss()
                        }
                    }
                }
                .padding(20)
            }
            .background(effectiveColorScheme == .dark ? Color.jet : Color.white)
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
    var colorHex: String? = nil
    let isDefault: Bool
    var onTap: () -> Void

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
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(iconColor)

                Text(name)
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

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
        onFolderSelected: { _ in }
    )
    .preferredColorScheme(.dark)
}
