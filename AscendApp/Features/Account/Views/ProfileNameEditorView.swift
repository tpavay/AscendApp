import SwiftUI

struct ProfileNameEditorView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss

    let field: ProfileNameField

    @State private var firstName: String
    @State private var lastName: String
    @State private var isSaving = false
    @FocusState private var isFocused: Bool

    init(field: ProfileNameField, firstName: String, lastName: String) {
        self.field = field
        _firstName = State(initialValue: firstName)
        _lastName = State(initialValue: lastName)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ProfileSection(title: "Profile") {
                    ProfileCardSurface {
                        TextField(field.rawValue, text: editedName)
                            .font(.montserratRegular(size: 16))
                            .foregroundStyle(.white)
                            .tint(.accent)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($isFocused)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 56)
                            .onSubmit(save)
                            .accessibilityLabel(field.rawValue)
                    }
                }

                Button(action: save) {
                    Group {
                        if isSaving {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text("Save")
                                .font(.montserratBold(size: 14))
                        }
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background(Capsule().fill(Color.accent))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.45)

                if let errorMessage = authVM.errorMessage {
                    Text(errorMessage)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .themedBackground()
        .navigationTitle(field.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .keyboardDoneToolbar {
            isFocused = false
        }
        .onAppear {
            isFocused = true
        }
    }

    private var editedName: Binding<String> {
        switch field {
        case .firstName:
            $firstName
        case .lastName:
            $lastName
        }
    }

    private var canSave: Bool {
        let composedName = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return !isSaving && !composedName.isEmpty && composedName.count <= 80
    }

    private func save() {
        guard canSave else { return }
        isFocused = false

        Task { @MainActor in
            isSaving = true
            let didSave = await authVM.updateProfileName(
                firstName: firstName,
                lastName: lastName
            )
            isSaving = false
            if didSave {
                dismiss()
            }
        }
    }
}
