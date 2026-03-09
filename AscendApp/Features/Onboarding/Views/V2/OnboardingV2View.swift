import AuthenticationServices
import SwiftUI

private enum AuthEntryContext {
    case onboardingSetup
    case returningSignIn
}

struct OnboardingV2View: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.colorScheme) private var systemColorScheme

    @State private var themeManager = ThemeManager.shared
    @State private var onboardingState = OnboardingStateManager.shared
    @State private var settingsManager = SettingsManager.shared
    @State private var healthKitService = HealthKitService.shared
    @State private var notificationPermissionManager = NotificationPermissionManager.shared
    @State private var locationPermissionManager = LocationPermissionManager.shared

    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @State private var authEntryContext: AuthEntryContext = .onboardingSetup

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    var body: some View {
        @Bindable var onboardingState = onboardingState

        VStack(spacing: 0) {
            if onboardingState.canGoBack {
                OnboardingTopBar {
                    handleBackAction()
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }

            if onboardingState.currentStep != .welcome && onboardingState.currentStep != .auth {
                OnboardingStepProgressView(currentStep: onboardingState.currentStep)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }

            Group {
                switch onboardingState.currentStep {
                case .welcome:
                    WelcomeOnboardingStepView()
                case .healthKit:
                    HealthKitOnboardingStepView(
                        isHealthDataAvailable: healthKitService.isHealthDataAvailable,
                        isConnected: onboardingState.draft.healthKitOptIn,
                        onToggle: handleHealthKitToggle,
                        onUnavailableTap: handleHealthKitUnavailableTap
                    )
                case .measurementSystem:
                    MeasurementSystemOnboardingStepView(selection: $onboardingState.draft.measurementSystem)
                case .fitnessLevel:
                    FitnessLevelOnboardingStepSelectionView(selection: $onboardingState.draft.fitnessLevel)
                case .personalDetails:
                    PersonalDetailsOnboardingStepView(
                        dateOfBirth: $onboardingState.draft.dateOfBirth,
                        gender: $onboardingState.draft.gender
                    )
                case .bodyMetrics:
                    BodyMetricsOnboardingStepView(
                        measurementSystem: onboardingState.draft.measurementSystem,
                        heightValue: displayedHeightBinding,
                        bodyWeightValue: displayedBodyWeightBinding
                    )
                case .location:
                    LocationOnboardingStepView(
                        isEnabled: !onboardingState.draft.locationSummary.isEmpty,
                        summary: onboardingState.draft.locationSummary,
                        onToggle: handleLocationToggle
                    )
                case .notifications:
                    NotificationsOnboardingStepView(
                        isEnabled: onboardingState.draft.notificationOptIn,
                        onToggle: handleNotificationsToggle
                    )
                case .auth:
                    AuthOnboardingStepView(
                        presentation: authEntryContext == .returningSignIn ? .welcomeBack : .onboardingSetup,
                        authState: authVM.authenticationState,
                        isSaving: isSaving,
                        errorMessage: authVM.errorMessage,
                        onSignInWithApple: {
                            Task {
                                await authVM.signInWithApple()
                            }
                        },
                        onSignInWithGoogle: {
                            Task {
                                await authVM.signInWithGoogle()
                            }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            OnboardingNavigationControls(
                showPrimaryButton: shouldShowPrimaryButton,
                isPrimaryEnabled: isPrimaryEnabled,
                isPrimaryLoading: isSaving,
                primaryButtonTitle: onboardingState.currentStep == .auth ? "Finish Setup" : onboardingState.currentStep.primaryButtonTitle,
                onPrimary: {
                    Task {
                        await handlePrimaryAction()
                    }
                }
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 32)

            if onboardingState.currentStep == .welcome {
                Button {
                    openReturningSignIn()
                } label: {
                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .font(.montserratRegular(size: 16))
                            .foregroundStyle(.secondary)

                        Text("Sign in")
                            .font(.montserratSemiBold(size: 16))
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.bottom, 20)
            }
        }
        .themedBackground()
        .onChange(of: onboardingState.draft.measurementSystem) { _, newValue in
            if settingsManager.measurementSystem != newValue {
                settingsManager.setMeasurementSystem(newValue)
            }
        }
        .onChange(of: onboardingState.draft.fitnessLevel) { _, newValue in
            if settingsManager.fitnessLevel != newValue {
                settingsManager.setFitnessLevel(newValue)
            }
        }
        .onChange(of: authVM.authenticationState) { _, newValue in
            guard onboardingState.currentStep == .auth else {
                return
            }

            if newValue == .authenticated {
                Task {
                    await completeOnboardingIfPossible()
                }
            }
        }
        .onChange(of: onboardingState.currentStep) { _, newValue in
            if newValue != .auth {
                authEntryContext = .onboardingSetup
            }
        }
        .alert("Onboarding Error", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "Please try again.")
        }
    }

    private var shouldShowPrimaryButton: Bool {
        if onboardingState.currentStep == .auth {
            return authVM.authenticationState == .authenticated
        }

        return true
    }

    private var isPrimaryEnabled: Bool {
        if onboardingState.currentStep == .auth {
            return authVM.authenticationState == .authenticated && !isSaving
        }

        return !isSaving
    }

    private func handlePrimaryAction() async {
        switch onboardingState.currentStep {
        case .auth:
            await completeOnboardingIfPossible()
        default:
            if onboardingState.currentStep == .notifications {
                authEntryContext = .onboardingSetup
            }
            onboardingState.goToNextStep()
        }
    }

    private func openReturningSignIn() {
        authEntryContext = .returningSignIn
        onboardingState.updateDraft {
            $0.currentStep = .auth
        }
    }

    private func handleBackAction() {
        if onboardingState.currentStep == .auth, authEntryContext == .returningSignIn {
            authEntryContext = .onboardingSetup
            onboardingState.updateDraft {
                $0.currentStep = .welcome
            }
            return
        }

        onboardingState.goToPreviousStep()
    }

    private func handleHealthKitToggle(_ enabled: Bool) {
        Task {
            if enabled {
                onboardingState.updateDraft {
                    $0.healthKitOptIn = true
                }

                guard healthKitService.isHealthDataAvailable else {
                    onboardingState.updateDraft {
                        $0.healthKitOptIn = false
                    }
                    saveErrorMessage = "Apple Health is not available on this device."
                    return
                }

                let granted = await healthKitService.requestPermission()
                onboardingState.updateDraft {
                    $0.healthKitOptIn = granted
                }
                if !granted {
                    saveErrorMessage = healthKitService.lastPermissionErrorMessage ?? "Unable to connect Apple Health right now."
                }
            } else {
                onboardingState.updateDraft {
                    $0.healthKitOptIn = false
                }
            }
        }
    }

    private func handleHealthKitUnavailableTap() {
#if targetEnvironment(simulator)
        saveErrorMessage = "Apple Health access requires a physical iPhone. It is unavailable in the Simulator."
#else
        saveErrorMessage = healthKitService.lastPermissionErrorMessage ?? "Apple Health is not available on this device."
#endif
    }

    private func handleNotificationsToggle(_ enabled: Bool) {
        Task {
            if enabled {
                let granted = await notificationPermissionManager.requestPermission()
                onboardingState.updateDraft {
                    $0.notificationOptIn = granted
                }
            } else {
                onboardingState.updateDraft {
                    $0.notificationOptIn = false
                }
            }
        }
    }

    private func handleLocationToggle(_ enabled: Bool) {
        Task {
            if enabled {
                let status = await locationPermissionManager.requestWhenInUse()
                guard status == .authorizedWhenInUse || status == .authorizedAlways else {
                    onboardingState.updateDraft {
                        $0.locationSummary = .empty
                    }
                    return
                }

                let summary = await locationPermissionManager.fetchLocationSummary() ?? .empty
                onboardingState.updateDraft {
                    $0.locationSummary = summary
                }
            } else {
                onboardingState.updateDraft {
                    $0.locationSummary = .empty
                }
            }
        }
    }

    private var displayedHeightBinding: Binding<Double> {
        Binding {
            switch onboardingState.draft.measurementSystem {
            case .metric:
                return onboardingState.draft.heightCm
            case .imperial:
                return onboardingState.draft.heightCm / 2.54
            }
        } set: { newValue in
            let clamped = max(newValue, 1)
            onboardingState.updateDraft {
                $0.heightCm = $0.measurementSystem == .metric ? clamped : clamped * 2.54
            }
        }
    }

    private var displayedBodyWeightBinding: Binding<Double> {
        Binding {
            switch onboardingState.draft.measurementSystem {
            case .metric:
                return onboardingState.draft.bodyWeightKg
            case .imperial:
                return onboardingState.draft.bodyWeightKg / 0.453592
            }
        } set: { newValue in
            let clamped = max(newValue, 1)
            onboardingState.updateDraft {
                $0.bodyWeightKg = $0.measurementSystem == .metric ? clamped : clamped * 0.453592
            }
        }
    }

    private func completeOnboardingIfPossible() async {
        guard !isSaving else { return }
        guard let user = authVM.user else {
            saveErrorMessage = "Please sign in to continue."
            return
        }

        isSaving = true

        do {
            settingsManager.setMeasurementSystem(onboardingState.draft.measurementSystem)
            settingsManager.setFitnessLevel(onboardingState.draft.fitnessLevel)

            // Ensure the base user document exists before writing the onboarding
            // profile. The auth state listener saves it in a fire-and-forget Task,
            // so it may not have completed yet.
            try await UserDataRepository.shared.saveUserToFirestore(
                userId: user.uid,
                email: user.email,
                firstName: nil,
                lastName: nil,
                displayName: user.displayName
            )

            try await UserDataRepository.shared.upsertOnboardingProfile(userId: user.uid, draft: onboardingState.draft)
            onboardingState.markCompleted()
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }

        isSaving = false
    }
}

private struct OnboardingStepProgressView: View {
    let currentStep: OnboardingStepID

    private var steps: [OnboardingStepID] {
        OnboardingStepID.allCases.filter { $0 != .welcome && $0 != .auth }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(steps, id: \.rawValue) { step in
                Capsule()
                    .fill(step == currentStep ? Color.accent : Color.accent.opacity(0.25))
                    .frame(width: step == currentStep ? 22 : 8, height: 8)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentStep)
    }
}

private struct OnboardingTopBar: View {
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Back")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(
                Capsule()
                    .fill(.secondary.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(.secondary.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Capsule())
            .buttonStyle(.plain)

            Spacer()
        }
    }
}

private struct OnboardingNavigationControls: View {
    let showPrimaryButton: Bool
    let isPrimaryEnabled: Bool
    let isPrimaryLoading: Bool
    let primaryButtonTitle: String
    let onPrimary: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if showPrimaryButton {
                Button {
                    onPrimary()
                } label: {
                    HStack(spacing: 8) {
                        if isPrimaryLoading {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(primaryButtonTitle)
                            .font(.montserratSemiBold(size: 16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 55)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isPrimaryEnabled ? Color.accent : Color.gray)
                    )
                }
                .disabled(!isPrimaryEnabled)
            }
        }
    }
}

private struct OnboardingStepContainer<Content: View>: View {
    let scene: OnboardingMascotScene
    let title: String
    let subtitle: String
    let mascotSize: CGFloat
    let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(
        scene: OnboardingMascotScene,
        title: String,
        subtitle: String,
        mascotSize: CGFloat = 210,
        @ViewBuilder content: () -> Content
    ) {
        self.scene = scene
        self.title = title
        self.subtitle = subtitle
        self.mascotSize = mascotSize
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                OnboardingMascotView(scene: scene, size: mascotSize)
                    .padding(.top, 12)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.montserratBold(size: 24))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .multilineTextAlignment(.center)

                    Text(subtitle)
                        .font(.montserratRegular(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                content
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}

private struct WelcomeOnboardingStepView: View {
    private let copy = WelcomeCopy(
        title: "Welcome to Ascend",
        bodyLineOne: "The easiest way to log stair workouts, track progress, and build consistency.",
        bodyLineTwo: "Built so you keep showing up."
    )

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            WelcomeHeroLogoView(
                gifDataAssetName: "onboarding_get_started_hero_gif",
                preferredAssetNames: [],
                fallbackScene: .welcome,
                fallbackSize: 190
            )
                .frame(maxWidth: .infinity)
                .padding(.top, 18)

            Spacer(minLength: 28)

            VStack(alignment: .leading, spacing: 16) {
                Text(copy.title)
                    .font(.montserratBold(size: 40))
                    .minimumScaleFactor(0.75)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                Text(copy.bodyLineOne)
                    .font(.montserratRegular(size: 17))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)

                Text(copy.bodyLineTwo)
                    .font(.montserratRegular(size: 17))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            Spacer(minLength: 24)
        }
    }
}

private struct WelcomeCopy {
    let title: String
    let bodyLineOne: String
    let bodyLineTwo: String
}

private struct WelcomeHeroLogoView: View {
    let gifDataAssetName: String?
    let preferredAssetNames: [String]
    let fallbackScene: OnboardingMascotScene
    let fallbackSize: CGFloat

    private var gifData: Data? {
        guard let gifDataAssetName else {
            return nil
        }

        return NSDataAsset(name: gifDataAssetName)?.data
    }

    private var selectedAssetName: String? {
        preferredAssetNames.first(where: { UIImage(named: $0) != nil })
    }

    var body: some View {
        Group {
            if let gifData {
                AnimatedGIFView(
                    data: gifData,
                    contentMode: .scaleAspectFit,
                    zoomScale: 1,
                    normalizedCropRect: CGRect(x: 0.12, y: 0.26, width: 0.76, height: 0.52)
                )
                    .frame(width: 270, height: 270)
                    .padding(.horizontal, 24)
                    .clipped()
            } else if let selectedAssetName {
                Image(selectedAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320)
                    .padding(.horizontal, 24)
            } else {
                OnboardingMascotView(scene: fallbackScene, size: fallbackSize)
            }
        }
    }
}

private struct HealthKitOnboardingStepView: View {
    let isHealthDataAvailable: Bool
    let isConnected: Bool
    let onToggle: (Bool) -> Void
    let onUnavailableTap: () -> Void

    var body: some View {
        OnboardingStepContainer(
            scene: .health,
            title: "Connect Apple Health",
            subtitle: "Import stair workouts and read steps, heart rate, and calories."
        ) {
            PermissionToggleCard(
                title: "Enable Health Access",
                subtitle: isHealthDataAvailable ? "We only read workout metrics you allow" : "Health data is not available on this device",
                isOn: isConnected,
                isEnabled: isHealthDataAvailable,
                onToggle: onToggle,
                onDisabledTap: onUnavailableTap
            )
        }
    }
}

private struct MeasurementSystemOnboardingStepView: View {
    @Binding var selection: MeasurementSystem

    var body: some View {
        OnboardingStepContainer(
            scene: .measurement,
            title: "Choose Your Units",
            subtitle: "You can change this anytime in Settings."
        ) {
            VStack(spacing: 12) {
                ForEach(MeasurementSystem.allCases) { system in
                    SelectionCard(
                        title: system.displayName,
                        subtitle: system.description,
                        isSelected: selection == system,
                        action: {
                            selection = system
                        }
                    )
                }
            }
        }
    }
}

private struct FitnessLevelOnboardingStepSelectionView: View {
    @Binding var selection: FitnessLevel

    var body: some View {
        OnboardingStepContainer(
            scene: .fitness,
            title: "Select Your Fitness Level",
            subtitle: "This tunes early progress scoring while we learn from your workouts."
        ) {
            VStack(spacing: 12) {
                ForEach(FitnessLevel.allCases) { level in
                    SelectionCard(
                        title: level.displayName,
                        subtitle: level.description,
                        icon: level.icon,
                        isSelected: selection == level,
                        action: {
                            selection = level
                        }
                    )
                }
            }
        }
    }
}

private struct PersonalDetailsOnboardingStepView: View {
    @Binding var dateOfBirth: Date
    @Binding var gender: UserProfileGender

    var body: some View {
        OnboardingStepContainer(
            scene: .personal,
            title: "Personal Details",
            subtitle: "Used to personalize comparisons and profile context."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Date of Birth")
                        .font(.montserratSemiBold(size: 14))
                        .foregroundStyle(.secondary)

                    DatePicker("Date of Birth", selection: $dateOfBirth, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.secondary.opacity(0.08))
                        )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Gender")
                        .font(.montserratSemiBold(size: 14))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 10) {
                        ForEach(UserProfileGender.allCases) { option in
                            SelectionCard(
                                title: option.displayName,
                                subtitle: "",
                                isSelected: gender == option,
                                action: {
                                    gender = option
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct BodyMetricsOnboardingStepView: View {
    let measurementSystem: MeasurementSystem
    @Binding var heightValue: Double
    @Binding var bodyWeightValue: Double

    var body: some View {
        OnboardingStepContainer(
            scene: .body,
            title: "Body Metrics",
            subtitle: "We use one global bodyweight value across the app."
        ) {
            VStack(spacing: 14) {
                MetricInputCard(
                    title: "Height",
                    value: $heightValue,
                    unitLabel: measurementSystem == .metric ? "cm" : "in"
                )

                MetricInputCard(
                    title: "Bodyweight",
                    value: $bodyWeightValue,
                    unitLabel: measurementSystem == .metric ? "kg" : "lb"
                )
            }
        }
    }
}

private struct LocationOnboardingStepView: View {
    let isEnabled: Bool
    let summary: UserLocationSummary
    let onToggle: (Bool) -> Void

    var body: some View {
        OnboardingStepContainer(
            scene: .location,
            title: "Enable Location?",
            subtitle: "We only store your city, region, and country for local context."
        ) {
            VStack(spacing: 12) {
                PermissionToggleCard(
                    title: "Enable Location Services",
                    subtitle: "Store city, region, and country only",
                    isOn: isEnabled,
                    isEnabled: true,
                    onToggle: onToggle
                )

                if !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Saved location")
                            .font(.montserratSemiBold(size: 13))
                            .foregroundStyle(.secondary)

                        Text([summary.city, summary.region, summary.country]
                            .filter { !$0.isEmpty }
                            .joined(separator: ", "))
                            .font(.montserratRegular(size: 15))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.secondary.opacity(0.08))
                    )
                }
            }
        }
    }
}

private struct NotificationsOnboardingStepView: View {
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        OnboardingStepContainer(
            scene: .notifications,
            title: "Stay on Track",
            subtitle: "Turn on reminders to maintain consistency."
        ) {
            PermissionToggleCard(
                title: "Enable Notifications",
                subtitle: "Prompt appears immediately when enabled",
                isOn: isEnabled,
                isEnabled: true,
                onToggle: onToggle
            )
        }
    }
}

private enum AuthOnboardingPresentation {
    case onboardingSetup
    case welcomeBack

    var title: String {
        switch self {
        case .onboardingSetup:
            return "Save Your Progress"
        case .welcomeBack:
            return "Welcome back"
        }
    }

    var subtitle: String {
        switch self {
        case .onboardingSetup:
            return "Create an account to sync data across devices and never lose progress."
        case .welcomeBack:
            return "Sign in to your account"
        }
    }
}

private struct AuthOnboardingStepView: View {
    let presentation: AuthOnboardingPresentation
    let authState: AuthenticationState
    let isSaving: Bool
    let errorMessage: String?
    let onSignInWithApple: () -> Void
    let onSignInWithGoogle: () -> Void

    private var isAuthenticating: Bool {
        authState == .authenticatingWithApple || authState == .authenticatingWithGoogle
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 14)

            WelcomeHeroLogoView(
                gifDataAssetName: nil,
                preferredAssetNames: [
                    "onboarding_auth_logo",
                    "onboarding_welcome_logo",
                    "app_logo_onboarding",
                    "AscendLogo",
                    "onboarding_mascot_base"
                ],
                fallbackScene: .auth,
                fallbackSize: 190
            )
                .frame(maxWidth: .infinity)
                .padding(.top, 18)

            Spacer(minLength: 26)

            VStack(spacing: 8) {
                Text(presentation.title)
                    .font(.montserratBold(size: 36))
                    .minimumScaleFactor(0.75)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                Text(presentation.subtitle)
                    .font(.montserratRegular(size: 18))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 36)

            VStack(spacing: 14) {
                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    onSignInWithApple()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 20, weight: .medium))

                        Text(authState == .authenticatingWithApple ? "Signing In..." : "Continue with Apple")
                            .font(.montserratSemiBold(size: 16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 28)
                            .fill(.black)
                    )
                }
                .disabled(isAuthenticating || isSaving)

                Button {
                    onSignInWithGoogle()
                } label: {
                    HStack(spacing: 12) {
                        Image("GoogleIcon")
                            .frame(width: 18, height: 18)

                        Text(authState == .authenticatingWithGoogle ? "Signing In..." : "Continue with Google")
                            .font(.montserratSemiBold(size: 16))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 28)
                            .fill(.secondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(.secondary.opacity(0.25), lineWidth: 1)
                    )
                }
                .disabled(isAuthenticating || isSaving)

                if authState == .authenticated {
                    Text("Signed in successfully. Tap Finish Setup below.")
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 22)
        }
    }
}

private struct PermissionToggleCard: View {
    let title: String
    let subtitle: String
    let isOn: Bool
    let isEnabled: Bool
    let onToggle: (Bool) -> Void
    var onDisabledTap: (() -> Void)? = nil

    var body: some View {
        Button {
            if isEnabled {
                onToggle(!isOn)
            } else {
                onDisabledTap?()
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.montserratSemiBold(size: 17))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                PermissionSwitch(isOn: isOn, isEnabled: isEnabled)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.secondary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.78)
    }
}

private struct PermissionSwitch: View {
    let isOn: Bool
    let isEnabled: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isEnabled ? Color.secondary.opacity(0.32) : Color.secondary.opacity(0.2))
                .frame(width: 54, height: 32)

            Circle()
                .fill(.white)
                .frame(width: 26, height: 26)
                .padding(.horizontal, 3)
                .shadow(color: .black.opacity(0.08), radius: 1.5, x: 0, y: 1)
        }
        .overlay {
            Capsule()
                .stroke(isOn ? .accent : .clear, lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.2), value: isOn)
        .opacity(isEnabled ? 1 : 0.65)
    }
}

private struct SelectionCard: View {
    let title: String
    let subtitle: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.accent)
                        .frame(width: 30)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(.primary)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.montserratRegular(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 12)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(isSelected ? .accent : .secondary.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.secondary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? .accent.opacity(0.6) : .clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MetricInputCard: View {
    let title: String
    @Binding var value: Double
    let unitLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField(
                    title,
                    value: $value,
                    format: .number.precision(.fractionLength(0...1))
                )
                .font(.montserratSemiBold(size: 20))
                .keyboardType(.decimalPad)

                Text(unitLabel)
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.secondary.opacity(0.08))
            )
        }
    }
}

private struct FeatureBullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(.accent)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            Text(text)
                .font(.montserratRegular(size: 15))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.secondary.opacity(0.08))
        )
    }
}

#Preview {
    OnboardingV2View()
        .environment(AuthenticationViewModel())
}
