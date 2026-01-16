import SwiftUI

struct RenameFolderDialog: View {
    @Binding var isPresented: Bool
    let currentName: String
    var onRename: (String) -> Void

    @State private var folderName: String = ""

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @FocusState private var isTextFieldFocused: Bool

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Rename Folder")
                .font(.montserratBold(size: 20))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            TextField("Folder name", text: $folderName)
                .font(.montserratMedium(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(effectiveColorScheme == .dark ? .white.opacity(0.05) : .gray.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                        )
                )
                .focused($isTextFieldFocused)

            HStack(spacing: 12) {
                Button {
                    isPresented = false
                    folderName = ""
                } label: {
                    Text("Cancel")
                        .font(.montserratMedium(size: 14))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))
                        )
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                }
                .buttonStyle(.plain)

                Button {
                    onRename(folderName.trimmingCharacters(in: .whitespaces))
                    isPresented = false
                    folderName = ""
                } label: {
                    Text("Save")
                        .font(.montserratMedium(size: 14))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.accent)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(folderName.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(folderName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? Color.jet : Color.white)
        )
        .onAppear {
            folderName = currentName
            isTextFieldFocused = true
        }
    }
}

#Preview {
    RenameFolderDialog(
        isPresented: .constant(true),
        currentName: "Hyrox",
        onRename: { _ in }
    )
    .padding(20)
    .preferredColorScheme(.dark)
}
