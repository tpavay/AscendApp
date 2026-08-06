import SwiftUI

struct ProfileNameEditorView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss

    let field: ProfileNameField

    @State private var firstName: String
    @State private var lastName: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: ProfileNameField?

    // A climber who signed up before the split fields existed has neither on
    // record. Editing one alone would compose a half board name, so the missing
    // counterpart is collected here rather than left for a second visit that
    // the both-required rule would block anyway.
    private let requiresCounterpart: Bool

    init(field: ProfileNameField, firstName: String, lastName: String) {
        self.field = field
        _firstName = State(initialValue: firstName)
        _lastName = State(initialValue: lastName)
        let counterpart = field == .firstName ? lastName : firstName
        requiresCounterpart = counterpart
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ProfileSection(title: "Profile") {
                    ProfileCardSurface {
                        VStack(spacing: 0) {
                            nameField(for: field)

                            if requiresCounterpart {
                                ProfileCardDivider(leadingInset: 20)
                                nameField(for: field.counterpart)
                            }
                        }
                    }
                }

                if requiresCounterpart {
                    Text("Your board name is your first and last name together. Enter both.")
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
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

                if let errorMessage {
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
            focusedField = nil
        }
        .onAppear {
            focusedField = field
        }
    }

    private func nameField(for field: ProfileNameField) -> some View {
        TextField(field.rawValue, text: binding(for: field))
            .font(.montserratRegular(size: 16))
            .foregroundStyle(.white)
            .tint(.accent)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($focusedField, equals: field)
            .padding(.horizontal, 20)
            .frame(minHeight: 56)
            .onSubmit(save)
            .accessibilityLabel(field.rawValue)
    }

    private func binding(for field: ProfileNameField) -> Binding<String> {
        switch field {
        case .firstName:
            $firstName
        case .lastName:
            $lastName
        }
    }

    private var canSave: Bool {
        !isSaving && DisplayNamePolicy.composesAllowedBoardName(
            firstName: firstName,
            lastName: lastName
        )
    }

    private func save() {
        guard canSave else { return }
        focusedField = nil

        Task { @MainActor in
            isSaving = true
            errorMessage = await authVM.scopedProfileUpdate(
                fallback: "Failed to update name"
            ) {
                await authVM.updateProfileName(
                    firstName: firstName,
                    lastName: lastName
                )
            }
            isSaving = false
            if errorMessage == nil {
                dismiss()
            }
        }
    }
}
