import SwiftUI

struct ProfileGenderEditorView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss

    @State private var selectedGender: ProfileGender
    @State private var isSaving = false

    init(gender: ProfileGender?) {
        _selectedGender = State(initialValue: gender ?? .preferNotToSay)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ProfileSection(title: "Personal Information") {
                    ProfileCardSurface {
                        VStack(spacing: 0) {
                            ForEach(Array(ProfileGender.allCases.enumerated()), id: \.element.id) { index, gender in
                                Button {
                                    selectedGender = gender
                                } label: {
                                    HStack(spacing: 16) {
                                        Text(gender.displayName)
                                            .font(.montserratMedium)
                                            .foregroundStyle(.white)

                                        Spacer(minLength: 12)

                                        if selectedGender == gender {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundStyle(.accent)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .frame(minHeight: 56)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(gender.displayName)
                                .accessibilityAddTraits(selectedGender == gender ? .isSelected : [])

                                if index < ProfileGender.allCases.count - 1 {
                                    ProfileCardDivider()
                                }
                            }
                        }
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
                .disabled(isSaving)
                .opacity(isSaving ? 0.7 : 1)

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
        .navigationTitle("Gender")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }

    private func save() {
        guard !isSaving else { return }

        Task { @MainActor in
            isSaving = true
            let didSave = await authVM.updateOnboardingGender(selectedGender)
            isSaving = false
            if didSave {
                dismiss()
            }
        }
    }
}
