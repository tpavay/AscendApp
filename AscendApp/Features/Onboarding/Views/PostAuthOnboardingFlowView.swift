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
    @FocusState private var isNameFieldFocused: Bool

    let stage: PostAuthOnboardingStage
    let onContinue: () -> Void

    @State private var displayName = ""
    @State private var isSaving = false
    @State private var validationMessage: String?

    var body: some View {
        PostAuthOnboardingScaffold(
            stage: stage,
            eyebrow: "FIRST THINGS FIRST",
            headline: "What should\nwe call you?",
            subtitle: nil,
            primaryTitle: isSaving ? "Saving..." : "Continue",
            isPrimaryDisabled: isContinueDisabled,
            isPrimaryLoading: isSaving,
            allowsBackFromFirst: true,
            onBack: handleBack,
            onContinue: saveDisplayName
        ) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Mauricio", text: $displayName)
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(.white)
                    .tint(OnboardingValuePalette.lime)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .focused($isNameFieldFocused)
                    .onSubmit(saveDisplayName)
                    .padding(.horizontal, 18)
                    .frame(height: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(fieldBorderColor, lineWidth: 1)
                    )

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
                isNameFieldFocused = true
            }
            .onChange(of: displayName) { _, newValue in
                validationMessage = nil
                normalizeDisplayName(newValue)
            }
        }
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isContinueDisabled: Bool {
        isSaving || trimmedDisplayName.isEmpty
    }

    private var fieldBorderColor: Color {
        displayMessage == nil ? OnboardingValuePalette.lime.opacity(0.72) : .red.opacity(0.72)
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

private struct PostAuthOnboardingScaffold<Content: View>: View {
    let stage: PostAuthOnboardingStage
    var eyebrow: String? = nil
    let headline: String
    let subtitle: String?
    let primaryTitle: String
    var isPrimaryDisabled = false
    var isPrimaryLoading = false
    var allowsBackFromFirst = false
    let onBack: () -> Void
    let onContinue: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                OnboardingValueAmbientBackground(style: .tracking)

                VStack(alignment: .leading, spacing: 0) {
                    topBar(topInset: geometry.safeAreaInsets.top)

                    Spacer(minLength: 34)

                    VStack(alignment: .leading, spacing: 12) {
                        if let eyebrow {
                            Text(eyebrow)
                                .font(.montserratBold(size: 12))
                                .foregroundStyle(OnboardingValuePalette.lime)
                                .kerning(0.6)
                        }

                        Text(headline)
                            .font(.montserratBold(size: geometry.size.width < 370 ? 33 : 37))
                            .foregroundStyle(.white)
                            .lineSpacing(1)
                            .fixedSize(horizontal: false, vertical: true)

                        if let subtitle {
                            Text(subtitle)
                                .font(.montserratMedium(size: 16))
                                .foregroundStyle(Color(red: 168 / 255, green: 168 / 255, blue: 168 / 255))
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    content()
                        .padding(.top, 34)

                    Spacer(minLength: 28)

                    Button(action: onContinue) {
                        HStack(spacing: 10) {
                            if isPrimaryLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black.opacity(0.82)))
                                    .scaleEffect(0.85)
                            }

                            Text(primaryTitle)
                        }
                    }
                    .buttonStyle(
                        OnboardingPrimaryCTAButtonStyle(
                            height: geometry.size.height < 700 ? 56 : 58,
                            tint: .accent,
                            shadowOpacity: 0.24
                        )
                    )
                    .disabled(isPrimaryDisabled)
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 18)
                }
                .padding(.horizontal, min(max(geometry.size.width * 0.075, 26), 34))
            }
        }
        .background(Color.black)
    }

    private func topBar(topInset: CGFloat) -> some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(canGoBack ? .white.opacity(0.9) : .clear)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)
            .accessibilityLabel("Back")

            Spacer()

            OnboardingValueProgressIndicator(
                activeIndex: stage.progressIndex,
                totalCount: PostAuthOnboardingStage.allCases.count
            )

            Spacer()

            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.top, topInset + 8)
    }

    private var canGoBack: Bool {
        allowsBackFromFirst || stage != .first
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
