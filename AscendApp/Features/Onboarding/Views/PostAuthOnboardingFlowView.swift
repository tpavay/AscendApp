import SwiftUI

struct PostAuthOnboardingFlowView: View {
    let stage: PostAuthOnboardingStage
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        Group {
            switch stage {
            case .displayName:
                PostAuthOnboardingDisplayNameScreen(
                    stage: .displayName,
                    onContinue: onContinue
                )
            }
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct PostAuthOnboardingDisplayNameScreen: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @FocusState private var isNameFocused: Bool

    let stage: PostAuthOnboardingStage
    let onContinue: () -> Void

    @State private var displayName = ""
    @State private var isSaving = false
    @State private var validationMessage: String?

    private let plannedQuestionCount = 5

    var body: some View {
        OnboardingQuestionScaffold(
            progressIndex: stage.progressIndex,
            progressCount: plannedQuestionCount,
            backgroundImageName: "OnboardingQuestionsBackground",
            eyebrow: "FIRST THINGS FIRST",
            headline: "What Should\nWe Call You?",
            subtitle: nil,
            primaryTitle: isSaving ? "Saving..." : "Continue",
            isPrimaryDisabled: isContinueDisabled,
            isPrimaryLoading: isSaving,
            isBackEnabled: true,
            onBack: handleBack,
            onContinue: saveDisplayName
        ) {
            VStack(alignment: .leading, spacing: 12) {
                nameField

                if let message = displayMessage {
                    Text(message)
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(.red.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .onAppear {
                if displayName.isEmpty {
                    displayName = authVM.displayName
                }
                isNameFocused = true
            }
            .onChange(of: displayName) { _, newValue in
                validationMessage = nil
                normalizeDisplayName(newValue)
            }
        }
        .keyboardDoneToolbar {
            isNameFocused = false
        }
    }

    private var nameField: some View {
        HStack(spacing: 14) {
            Image(systemName: "person")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white.opacity(0.56))
                .frame(width: 26)

            TextField(
                "",
                text: $displayName,
                prompt: Text("Enter Your Name")
                    .foregroundStyle(.white.opacity(0.54))
            )
            .font(.montserratRegular(size: 16))
            .foregroundStyle(.white)
            .tint(OnboardingValuePalette.lime)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.continue)
            .focused($isNameFocused)
            .onSubmit {
                saveDisplayName()
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(fieldBorderColor, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isContinueDisabled: Bool {
        isSaving || trimmedDisplayName.isEmpty
    }

    private var fieldBorderColor: Color {
        displayMessage == nil ? .white.opacity(0.28) : .red.opacity(0.72)
    }

    private var displayMessage: String? {
        validationMessage ?? authVM.errorMessage
    }

    private func normalizeDisplayName(_ value: String) {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        let normalized = String(singleLine.prefix(80))
        if normalized != value {
            displayName = normalized
        }
    }

    private func saveDisplayName() {
        guard !isSaving else { return }

        let name = trimmedDisplayName
        guard !name.isEmpty else {
            validationMessage = "Enter a name to continue."
            return
        }

        Task { @MainActor in
            isSaving = true
            let didSave = await authVM.updateDisplayName(name)
            isSaving = false

            if didSave {
                onContinue()
            }
        }
    }

    private func handleBack() {
        authVM.signOut()
    }
}

#Preview("Post-Auth Onboarding") {
    PostAuthOnboardingFlowView(
        stage: .displayName,
        onBack: {},
        onContinue: {}
    )
    .environment(AuthenticationViewModel())
}
