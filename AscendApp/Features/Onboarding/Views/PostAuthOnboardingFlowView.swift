import SwiftUI

struct PostAuthOnboardingFlowView: View {
    let stage: PostAuthOnboardingStage
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        Group {
            switch stage {
            case .displayName:
                PostAuthDisplayNameScreen(
                    stage: stage,
                    onContinue: onContinue
                )
            case .stairStepperBaseline, .exerciseLevel, .goal, .motivation, .plan:
                PostAuthSurveyQuestionStageScreen(
                    stage: stage,
                    onBack: onBack,
                    onContinue: onContinue
                )
            case .features:
                PostAuthFeatureGuideStageScreen(
                    onBack: onBack,
                    onContinue: onContinue
                )
            case .gender:
                PostAuthGenderScreen(
                    stage: stage,
                    onBack: onBack,
                    onContinue: onContinue
                )
            case .age:
                PostAuthBirthdayScreen(
                    stage: stage,
                    onBack: onBack,
                    onContinue: onContinue
                )
            case .weight:
                PostAuthWeightScreen(
                    stage: stage,
                    onBack: onBack,
                    onContinue: onContinue
                )
            case .location:
                PostAuthLocationScreen(
                    stage: stage,
                    onBack: onBack,
                    onContinue: onContinue
                )
            case .notifications:
                PostAuthNotificationScreen(
                    stage: stage,
                    onBack: onBack,
                    onContinue: onContinue
                )
            case .planLoading:
                PostAuthPlanLoadingScreen(
                    stage: stage,
                    onBack: onBack,
                    onContinue: onContinue
                )
            case .firstClimb:
                PostAuthFirstClimbRevealScreen(
                    stage: stage,
                    onBack: onBack,
                    onContinue: onContinue
                )
            }
        }
        .background(PostAuthProfilePalette.background)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .trackOnboardingScreenView(stage.visibleScreenAnalyticsContext)
    }
}

private func trackPostAuthInput(
    stage: PostAuthOnboardingStage,
    properties: [String: TelemetryValue] = [:]
) {
    TelemetryManager.shared.track(
        OnboardingAnalyticsEvent.screenCompleted(
            context: stage.analyticsContext,
            inputType: stage.analyticsInputType,
            properties: properties
        )
    )
}

private struct PostAuthSurveyQuestionStageScreen: View {
    let stage: PostAuthOnboardingStage
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var selectedOptionIDs: Set<String> = []

    private let surveyStore = PreAuthOnboardingSurveyStore()

    var body: some View {
        PreAuthSurveyQuestionScreen(
            question: question,
            selectedOptionIDs: selectedOptionIDs,
            isContinueEnabled: !selectedOptionIDs.isEmpty,
            onSelect: selectAnswer,
            onBack: onBack,
            onContinue: continueFromQuestion
        )
        .onAppear {
            loadSavedAnswerIfNeeded()
        }
    }

    private var question: PreAuthSurveyQuestion {
        guard let question = PreAuthSurveyQuestion.question(for: stage.rawValue) else {
            preconditionFailure("Missing survey question for post-auth onboarding stage: \(stage.rawValue)")
        }

        return question.withProgressFraction(progressFraction)
    }

    private var progressFraction: CGFloat {
        guard PostAuthOnboardingStage.plannedStepCount > 0 else { return 0 }
        return CGFloat(stage.progressIndex + 1) / CGFloat(PostAuthOnboardingStage.plannedStepCount)
    }

    private func loadSavedAnswerIfNeeded() {
        guard selectedOptionIDs.isEmpty else { return }
        selectedOptionIDs = surveyStore.optionIDs(for: question.id)
    }

    private func selectAnswer(_ optionID: String) {
        var optionIDs = selectedOptionIDs

        switch question.selectionMode {
        case .single:
            optionIDs = [optionID]
        case .multiple:
            if optionIDs.contains(optionID) {
                optionIDs.remove(optionID)
            } else {
                optionIDs.insert(optionID)
            }
        }

        selectedOptionIDs = optionIDs
        surveyStore.save(questionID: question.id, optionIDs: optionIDs)
    }

    private func continueFromQuestion() {
        guard !selectedOptionIDs.isEmpty else { return }

        surveyStore.save(questionID: question.id, optionIDs: selectedOptionIDs)
        trackOnboardingSurveyAnswer(
            for: question,
            context: stage.analyticsContext,
            selectedOptionIDs: selectedOptionIDs
        )
        trackPostAuthInput(
            stage: stage,
            properties: ["answer_count": .int(selectedOptionIDs.count)]
        )
        onContinue()
    }
}

private struct PostAuthFeatureGuideStageScreen: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingFeatureGuideFlowScreen(
            segmentID: "post_auth_features",
            onBackFromFirstScreen: onBack
        ) {
            onContinue()
        }
    }
}

private struct PostAuthDisplayNameScreen: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @FocusState private var focusedField: ProfileNameField?

    let stage: PostAuthOnboardingStage
    let onContinue: () -> Void

    @State private var nameInput = PostAuthNameInput()
    @State private var isSaving = false
    @State private var validationMessage: String?

    var body: some View {
        PostAuthProfileQuestionShell(
            stage: stage,
            headline: "What's your\nname?",
            primaryTitle: isSaving ? "SAVING..." : "CONTINUE",
            isContinueEnabled: nameInput.canContinue && !isSaving,
            onBack: handleBack,
            onContinue: saveName
        ) { metrics in
            VStack(alignment: .leading, spacing: metrics.height(12)) {
                nameField(
                    field: .firstName,
                    text: $nameInput.firstName,
                    submitLabel: .next,
                    metrics: metrics
                )

                nameField(
                    field: .lastName,
                    text: $nameInput.lastName,
                    submitLabel: .continue,
                    metrics: metrics
                )

                Text("This is the name climbers see on leaderboards.")
                    .font(.montserratMedium(size: metrics.font(11)))
                    .foregroundStyle(.white.opacity(0.46))
                    .frame(width: metrics.width(334), alignment: .leading)

                if let displayMessage {
                    Text(displayMessage)
                        .font(.montserratMedium(size: metrics.font(11)))
                        .foregroundStyle(.red.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: metrics.width(334), alignment: .topLeading)
            .offset(x: metrics.x(28), y: metrics.y(294))
            .onChange(of: nameInput.firstName) { _, newValue in
                validationMessage = nil
                normalizeNamePart(newValue, field: .firstName)
            }
            .onChange(of: nameInput.lastName) { _, newValue in
                validationMessage = nil
                normalizeNamePart(newValue, field: .lastName)
            }
        }
        .keyboardDoneToolbar {
            focusedField = nil
        }
    }

    private func nameField(
        field: ProfileNameField,
        text: Binding<String>,
        submitLabel: SubmitLabel,
        metrics: PostAuthProfileMetrics
    ) -> some View {
        TextField(
            "",
            text: text,
            prompt: Text(field.rawValue)
                .foregroundStyle(.white.opacity(0.48))
        )
        .font(.montserratMedium(size: metrics.font(12)))
        .foregroundStyle(.white)
        .tint(OnboardingValuePalette.lime)
        .textContentType(field == .firstName ? .givenName : .familyName)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .submitLabel(submitLabel)
        .focused($focusedField, equals: field)
        .padding(.horizontal, metrics.width(14))
        .frame(width: metrics.width(334), height: metrics.height(52), alignment: .leading)
        .background(PostAuthProfilePalette.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius(6), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.radius(6), style: .continuous)
                .stroke(fieldBorderColor, lineWidth: 1)
        }
        .onSubmit {
            if field == .firstName {
                focusedField = .lastName
            } else {
                saveName()
            }
        }
        .accessibilityLabel(field.rawValue)
    }

    private var fieldBorderColor: Color {
        displayMessage == nil ? .white.opacity(0.18) : .red.opacity(0.72)
    }

    private var displayMessage: String? {
        validationMessage ?? authVM.errorMessage
    }

    private func normalizeNamePart(_ value: String, field: ProfileNameField) {
        let normalized = PostAuthNameInput.singleLinePart(value)
        if normalized != value {
            switch field {
            case .firstName:
                nameInput.firstName = normalized
            case .lastName:
                nameInput.lastName = normalized
            }
        }
    }

    private func saveName() {
        guard !isSaving else { return }

        do {
            _ = try DisplayNamePolicy.composedBoardName(
                firstName: nameInput.firstName,
                lastName: nameInput.lastName
            )
        } catch {
            validationMessage = (error as? LocalizedError)?.errorDescription
                ?? "Enter your first and last name to continue."
            return
        }

        Task { @MainActor in
            isSaving = true
            let didSave = await authVM.updateProfileName(
                firstName: nameInput.normalizedFirstName,
                lastName: nameInput.normalizedLastName
            )
            isSaving = false

            if didSave {
                TelemetryManager.shared.setUserProperty("name_inputted", value: "true")
                OnboardingAnalyticsUserProperties.setDisplayNameProvided()
                trackPostAuthInput(
                    stage: stage,
                    properties: ["display_name_provided": .bool(true)]
                )
                onContinue()
            }
        }
    }

    private func handleBack() {
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.backTapped(context: stage.analyticsContext, inputType: "button")
        )
        authVM.signOut()
    }
}

private struct PostAuthGenderScreen: View {
    @Environment(AuthenticationViewModel.self) private var authVM

    let stage: PostAuthOnboardingStage
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var selectedGender: ProfileGender?
    @State private var isSaving = false

    private let options = PostAuthGenderOption.all

    var body: some View {
        PostAuthProfileQuestionShell(
            stage: stage,
            headline: "Choose your division",
            subtitle: "Your sex helps place you in leaderboard context.",
            primaryTitle: isSaving ? "SAVING..." : "CONTINUE",
            isContinueEnabled: selectedGender != nil && !isSaving,
            onBack: onBack,
            onContinue: saveGender
        ) { metrics in
            ZStack(alignment: .topLeading) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    PostAuthProfileOptionRow(
                        title: option.title,
                        isSelected: selectedGender == option.gender,
                        metrics: metrics,
                        action: { selectedGender = option.gender }
                    )
                    .frame(width: metrics.width(334), height: metrics.height(52))
                    .position(
                        x: metrics.x(195),
                        y: metrics.y(347 + CGFloat(index) * 66 + 26)
                    )
                }

                errorMessage(metrics: metrics)
            }
        }
    }

    @ViewBuilder
    private func errorMessage(metrics: PostAuthProfileMetrics) -> some View {
        if let message = authVM.errorMessage {
            Text(message)
                .font(.montserratMedium(size: metrics.font(11)))
                .foregroundStyle(.red.opacity(0.9))
                .frame(width: metrics.width(334), alignment: .leading)
                .offset(x: metrics.x(28), y: metrics.y(620))
        }
    }

    private func saveGender() {
        guard !isSaving, let selectedGender else { return }

        Task { @MainActor in
            isSaving = true
            let didSave = await authVM.updateOnboardingGender(selectedGender)
            isSaving = false

            if didSave {
                TelemetryManager.shared.setUserProperty("division_inputted", value: "true")
                OnboardingAnalyticsUserProperties.setGender(selectedGender)
                trackPostAuthInput(
                    stage: stage,
                    properties: ["profile_gender": .string(selectedGender.rawValue)]
                )
                onContinue()
            }
        }
    }
}

private struct PostAuthBirthdayScreen: View {
    @Environment(AuthenticationViewModel.self) private var authVM

    let stage: PostAuthOnboardingStage
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var selectedBirthday = Calendar.current.date(
        byAdding: .year,
        value: -32,
        to: .now
    ) ?? .now
    @State private var isSaving = false

    var body: some View {
        PostAuthProfileQuestionShell(
            stage: stage,
            headline: "When were you born?",
            subtitle: "Your age keeps leaderboard context honest",
            primaryTitle: isSaving ? "SAVING..." : "CONTINUE",
            isContinueEnabled: !isSaving,
            onBack: onBack,
            onContinue: saveBirthday
        ) { metrics in
            VStack(spacing: metrics.height(12)) {
                PostAuthBirthdayWheelPicker(
                    selectedBirthday: $selectedBirthday,
                    metrics: metrics
                )

                if let message = authVM.errorMessage {
                    Text(message)
                        .font(.montserratMedium(size: metrics.font(11)))
                        .foregroundStyle(.red.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, metrics.height(10))
                }
            }
            .frame(width: metrics.width(334), alignment: .center)
            .position(x: metrics.x(195), y: metrics.y(393))
        }
    }

    private func saveBirthday() {
        guard !isSaving else { return }

        Task { @MainActor in
            let birthday = ProfileBirthday(date: selectedBirthday)
            guard let age = birthday.age(), ProfileBirthday.validAgeRange.contains(age) else {
                authVM.errorMessage = "Choose a birthday for an age from 13 to 120"
                return
            }

            isSaving = true
            let didSave = await authVM.updateOnboardingBirthday(birthday)
            isSaving = false

            if didSave {
                TelemetryManager.shared.setUserProperty("age_inputted", value: "true")
                OnboardingAnalyticsUserProperties.setAgeGroup(age: age)
                trackPostAuthInput(
                    stage: stage,
                    properties: ["profile_age_group": .string(OnboardingAnalyticsUserProperties.ageGroupValue(for: age))]
                )
                onContinue()
            }
        }
    }
}

private struct PostAuthWeightScreen: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @State private var settingsManager = SettingsManager.shared

    let stage: PostAuthOnboardingStage
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var selectedWeight = SettingsManager.shared.measurementSystem == .imperial ? 185 : 84
    @State private var selectedHeightInches = 70
    @State private var isSaving = false

    var body: some View {
        PostAuthProfileQuestionShell(
            stage: stage,
            headline: "Add your body\nmetrics",
            subtitle: "Used for profile context and future stats",
            primaryTitle: isSaving ? "SAVING..." : "CONTINUE",
            isContinueEnabled: validWeightKilograms != nil && validHeightCentimeters != nil && !isSaving,
            onBack: onBack,
            onContinue: saveBodyMetrics
        ) { metrics in
            VStack(spacing: metrics.height(12)) {
                HStack(alignment: .top, spacing: metrics.width(12)) {
                    PostAuthBodyMetricColumn(title: "HEIGHT", metrics: metrics) {
                        PostAuthHeightWheelPicker(
                            selectedHeightInches: $selectedHeightInches,
                            measurementSystem: settingsManager.measurementSystem,
                            metrics: metrics
                        )
                    }

                    PostAuthBodyMetricColumn(title: "WEIGHT", metrics: metrics) {
                        PostAuthWeightWheelPicker(
                            selectedWeight: $selectedWeight,
                            measurementSystem: settingsManager.measurementSystem,
                            metrics: metrics
                        )
                    }
                }

                Button(action: toggleMeasurementSystem) {
                    Text(settingsManager.measurementSystem == .imperial ? "Use metric" : "Use imperial")
                        .font(.montserratBold(size: metrics.font(8)))
                        .foregroundStyle(.white.opacity(0.54))
                }
                .buttonStyle(.plain)

                if let message = authVM.errorMessage {
                    Text(message)
                        .font(.montserratMedium(size: metrics.font(11)))
                        .foregroundStyle(.red.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, metrics.height(10))
                }
            }
            .frame(width: metrics.width(334), alignment: .center)
            .position(x: metrics.x(195), y: metrics.y(410))
        }
    }

    private var validWeightKilograms: Double? {
        let weightKg = settingsManager.measurementSystem.convertWeight(Double(selectedWeight), to: .metric)
        guard weightKg > 0, weightKg <= 400 else { return nil }
        return weightKg
    }

    private var validHeightCentimeters: Double? {
        let heightCm = MeasurementSystem.imperial.convertHeight(Double(selectedHeightInches), to: .metric)
        guard heightCm >= 90, heightCm <= 240 else { return nil }
        return heightCm
    }

    private func saveBodyMetrics() {
        guard !isSaving,
              let validWeightKilograms,
              let validHeightCentimeters else { return }

        Task { @MainActor in
            isSaving = true
            let didSave = await authVM.updateOnboardingBodyMetrics(
                weightKg: validWeightKilograms,
                heightCm: validHeightCentimeters
            )
            isSaving = false

            if didSave {
                TelemetryManager.shared.setUserProperty("body_metrics_inputted", value: "true")
                OnboardingAnalyticsUserProperties.setWeightGroup(weightKg: validWeightKilograms)
                trackPostAuthInput(
                    stage: stage,
                    properties: [
                        "measurement_system": .string(settingsManager.measurementSystem.rawValue),
                        "profile_height_group": .string(
                            OnboardingAnalyticsUserProperties.heightGroupValue(forHeightCm: validHeightCentimeters)
                        ),
                        "profile_weight_group": .string(
                            OnboardingAnalyticsUserProperties.weightGroupValue(forWeightKg: validWeightKilograms)
                        )
                    ]
                )
                onContinue()
            }
        }
    }

    private func toggleMeasurementSystem() {
        let oldSystem = settingsManager.measurementSystem
        let newSystem: MeasurementSystem = oldSystem == .imperial ? .metric : .imperial
        let convertedValue = oldSystem.convertWeight(Double(selectedWeight), to: newSystem)
        settingsManager.measurementSystem = newSystem
        selectedWeight = PostAuthWeightWheelPicker.clamp(Int(convertedValue.rounded()), to: newSystem)
    }
}

private struct PostAuthLocationScreen: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @StateObject private var citySearch = PostAuthCitySearchModel()
    @StateObject private var currentLocation = PostAuthCurrentLocationResolver()
    @FocusState private var isSearchFocused: Bool

    let stage: PostAuthOnboardingStage
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var selectedLocation: PostAuthLocationSelection?
    @State private var selectionMethod: String?
    @State private var isSaving = false

    var body: some View {
        PostAuthProfileQuestionShell(
            stage: stage,
            headline: "Where are you\nclimbing from?",
            subtitle: "Set your city for profile and leaderboard context. You can change this later in profile.",
            primaryTitle: isSaving ? "SAVING..." : "CONTINUE",
            isContinueEnabled: isValidSelection && !isSaving && !citySearch.isResolving && !currentLocation.isResolving,
            onBack: onBack,
            onContinue: saveLocation
        ) { metrics in
            VStack(alignment: .leading, spacing: metrics.height(10)) {
                PostAuthCitySearchField(
                    query: $citySearch.query,
                    isSearching: citySearch.isSearching || citySearch.isResolving,
                    metrics: metrics,
                    focused: $isSearchFocused
                )

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: metrics.height(8)) {
                        if let selectedLocation {
                            PostAuthSelectedCityRow(
                                selection: selectedLocation,
                                metrics: metrics
                            )
                        } else {
                            Button {
                                selectCurrentLocation()
                            } label: {
                                PostAuthCurrentLocationRow(
                                    isResolving: currentLocation.isResolving,
                                    metrics: metrics
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(citySearch.isResolving || currentLocation.isResolving)

                            if !citySearch.suggestions.isEmpty {
                                ForEach(citySearch.suggestions) { suggestion in
                                    Button {
                                        selectSuggestion(suggestion)
                                    } label: {
                                        PostAuthCitySuggestionRow(
                                            suggestion: suggestion,
                                            metrics: metrics
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(citySearch.isResolving || currentLocation.isResolving)
                                }
                            } else if citySearch.query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && !citySearch.isSearching {
                                Text("Search for your city, then choose the matching result.")
                                    .font(.montserratMedium(size: metrics.font(11)))
                                    .foregroundStyle(.white.opacity(0.48))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(width: metrics.width(334), alignment: .leading)
                            }
                        }

                        if let message = citySearch.errorMessage ?? currentLocation.errorMessage ?? authVM.errorMessage {
                            Text(message)
                                .font(.montserratMedium(size: metrics.font(11)))
                                .foregroundStyle(.red.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: metrics.width(334), alignment: .leading)
                        }
                    }
                }
                .frame(width: metrics.width(334), alignment: .top)
                .frame(maxHeight: metrics.height(324), alignment: .top)
                .scrollDismissesKeyboard(.interactively)
            }
            .frame(width: metrics.width(334), alignment: .topLeading)
            .offset(x: metrics.x(28), y: metrics.y(326))
            .onChange(of: citySearch.query) { _, newValue in
                currentLocation.clearError()
                guard let selectedLocation else { return }
                if newValue != selectedLocation.profileDisplayText {
                    self.selectedLocation = nil
                    selectionMethod = nil
                }
            }
        }
        .keyboardDoneToolbar {
            isSearchFocused = false
        }
    }

    private var isValidSelection: Bool {
        guard let selectedLocation else { return false }
        return !selectedLocation.city.isEmpty &&
            selectedLocation.city.count <= 120 &&
            selectedLocation.countryCode.range(of: #"^[A-Z]{2}$"#, options: .regularExpression) != nil &&
            (selectedLocation.region?.count ?? 0) <= 120
    }

    private func saveLocation() {
        guard !isSaving, isValidSelection, let selectedLocation else { return }

        Task { @MainActor in
            isSaving = true
            let didSave = await authVM.updateOnboardingLocation(
                city: selectedLocation.city,
                countryCode: selectedLocation.countryCode,
                region: selectedLocation.region
            )
            isSaving = false

            if didSave {
                TelemetryManager.shared.setUserProperty("location_inputted", value: "true")
                OnboardingAnalyticsUserProperties.setLocationCountry(selectedLocation.countryCode)
                trackPostAuthInput(
                    stage: stage,
                    properties: [
                        "profile_country": .string(selectedLocation.countryCode.uppercased()),
                        "selection_method": .string(selectionMethod ?? "unknown")
                    ]
                )
                onContinue()
            }
        }
    }

    private func selectSuggestion(_ suggestion: PostAuthCitySearchSuggestion) {
        guard !citySearch.isResolving, !currentLocation.isResolving else { return }

        Task { @MainActor in
            guard let location = await citySearch.resolve(suggestion) else { return }
            selectedLocation = location
            selectionMethod = "search"
            isSearchFocused = false
        }
    }

    private func selectCurrentLocation() {
        guard !citySearch.isResolving, !currentLocation.isResolving else { return }

        isSearchFocused = false
        Task { @MainActor in
            guard let location = await currentLocation.resolve() else { return }
            selectedLocation = location
            selectionMethod = "current_location"
            citySearch.setSelectedLocation(location)
        }
    }
}

struct PostAuthNotificationScreen: View {
    let stage: PostAuthOnboardingStage
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var isRequesting = false
    @State private var emailOptIn: OnboardingEmailOptInViewModel

    /// `emailOptIn` is defaulted to the view model this screen has always built,
    /// so every production call site is unchanged. Only tests pass one, to watch
    /// what Skip actually writes when the real control is pressed.
    @MainActor
    init(
        stage: PostAuthOnboardingStage,
        onBack: @escaping () -> Void,
        onContinue: @escaping () -> Void,
        emailOptIn: OnboardingEmailOptInViewModel = OnboardingEmailOptInViewModel()
    ) {
        self.stage = stage
        self.onBack = onBack
        self.onContinue = onContinue
        _emailOptIn = State(initialValue: emailOptIn)
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = PostAuthProfileMetrics(size: geometry.size)

            ZStack(alignment: .topLeading) {
                PostAuthProfilePalette.background
                    .ignoresSafeArea()

                OnboardingBackButton(action: onBack)
                    .position(
                        x: metrics.x(OnboardingChromeMetrics.backButtonLeadingPadding + OnboardingChromeMetrics.backButtonSize / 2),
                        y: metrics.y(OnboardingChromeMetrics.backButtonTopPadding + OnboardingChromeMetrics.backButtonSize / 2)
                    )

                Image("FirstAscentBadgeDetailed")
                    .resizable()
                    .scaledToFit()
                    .frame(width: metrics.width(303), height: metrics.height(303))
                    .position(x: metrics.x(195.5), y: metrics.y(262.5))
                    .accessibilityHidden(true)

                VStack(spacing: metrics.height(16)) {
                    Text("Never miss an\nAscent.")
                        .font(.montserratBold(size: metrics.font(32)))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(0)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Get an Ascend alert when new climbs open. Be ready to claim the First Ascent before anyone else.")
                        .font(.montserratRegular(size: metrics.font(14)))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(metrics.height(3))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: metrics.width(342))
                .offset(x: metrics.x(24), y: metrics.y(470))

                // Email is a separate answer from push. Enabling notifications
                // must never tick this, and unticking it must never stop the
                // iOS prompt: bundling them is what makes consent unspecific.
                Toggle(isOn: emailOptInBinding) {
                    Text("Email me when climbs drop.")
                        .font(.montserratMedium(size: metrics.font(14)))
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(
                    OnboardingCheckboxToggleStyle(
                        boxSize: metrics.width(22),
                        cornerRadius: metrics.radius(6),
                        spacing: metrics.width(12),
                        // The design coordinates scale with the screen; 44pt
                        // does not. A small phone gets the same target.
                        minimumTargetHeight: max(44, metrics.height(44))
                    )
                )
                .disabled(isRequesting)
                .frame(width: metrics.width(334))
                .position(x: metrics.x(195), y: metrics.y(651))

                VStack(spacing: metrics.height(14)) {
                    Button(action: requestNotifications) {
                        Text(isRequesting ? "ENABLING..." : "ENABLE NOTIFICATIONS")
                            .font(.montserratBold(size: metrics.font(15)))
                            .foregroundStyle(.black.opacity(isRequesting ? 0.45 : 0.9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: metrics.radius(12), style: .continuous)
                                    .fill(OnboardingValuePalette.lime.opacity(isRequesting ? 0.45 : 1))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRequesting)
                    .frame(width: metrics.width(334), height: metrics.height(56))

                    Button(action: skipNotifications) {
                        Text("Skip")
                            .font(.montserratBold(size: metrics.font(12)))
                            .foregroundStyle(.white.opacity(isRequesting ? 0.28 : 0.56))
                            .frame(height: metrics.height(24))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRequesting)
                }
                .frame(width: metrics.width(334), alignment: .center)
                .position(x: metrics.x(195), y: metrics.y(744))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .task {
            // A climber who already answered this question keeps their answer,
            // even on a phone that has never seen it. Nothing here waits on the
            // read: the box stays pre-ticked until and unless it returns one.
            await emailOptIn.adoptStoredDecision()
        }
    }

    private var emailOptInBinding: Binding<Bool> {
        Binding(
            get: { emailOptIn.isSelected },
            set: { _ in emailOptIn.toggle() }
        )
    }

    private func requestNotifications() {
        guard !isRequesting else { return }

        Task { @MainActor in
            isRequesting = true
            // The email answer is the climber's either way, so it is written
            // down before the iOS prompt can change what they are looking at.
            emailOptIn.startRecordingDecision()
            let status = await ClimbDropNotificationPermissionController.requestDuringOnboarding()
            isRequesting = false

            let isAllowed = switch status {
            case .authorized, .provisional, .ephemeral: true
            default: false
            }

            TelemetryManager.shared.track(
                OnboardingAnalyticsEvent.notificationPermissionSelected(
                    context: stage.analyticsContext,
                    status: isAllowed ? "allow" : "decline"
                )
            )
            TelemetryManager.shared.setUserProperty("notifications_inputted", value: "true")
            OnboardingAnalyticsUserProperties.setNotificationChoice(isAllowed ? "allow" : "decline")
            trackPostAuthInput(
                stage: stage,
                properties: ["status": .string(isAllowed ? "allow" : "decline")]
            )
            onContinue()
        }
    }

    private func skipNotifications() {
        guard !isRequesting else { return }

        Task { @MainActor in
            isRequesting = true
            // Skip declines push, not email. The tick is a separate answer and
            // it is saved here exactly as it is saved by Enable.
            emailOptIn.startRecordingDecision()
            await ClimbDropNotificationPermissionController.disable()
            isRequesting = false

            TelemetryManager.shared.track(
                OnboardingAnalyticsEvent.notificationPermissionSelected(
                    context: stage.analyticsContext,
                    status: "skip"
                )
            )
            TelemetryManager.shared.setUserProperty("notifications_inputted", value: "true")
            OnboardingAnalyticsUserProperties.setNotificationChoice("skip")
            trackPostAuthInput(
                stage: stage,
                properties: ["status": .string("skip")]
            )
            onContinue()
        }
    }
}

private struct PostAuthPlanLoadingScreen: View {
    let stage: PostAuthOnboardingStage
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var didAdvance = false
    @State private var carouselCards = PostAuthPlanCarouselCard.defaults
    @State private var activeChecklistIndex = -1
    @State private var completedChecklistCount = 0
    @State private var celebratingCheckIndex: Int?
    @State private var carouselIndex = 0

    private let checklistItems = PostAuthPlanChecklistItem.defaults

    var body: some View {
        GeometryReader { geometry in
            let metrics = PostAuthProfileMetrics(size: geometry.size)

            ZStack(alignment: .topLeading) {
                PostAuthProfilePalette.background
                    .ignoresSafeArea()

                OnboardingBackButton(action: onBack)
                    .position(
                        x: metrics.x(OnboardingChromeMetrics.backButtonLeadingPadding + OnboardingChromeMetrics.backButtonSize / 2),
                        y: metrics.y(OnboardingChromeMetrics.backButtonTopPadding + OnboardingChromeMetrics.backButtonSize / 2)
                    )

                PostAuthProfileProgressBar(progress: progressFraction)
                    .frame(width: metrics.width(169), height: metrics.height(5))
                    .position(x: metrics.x(195.5), y: metrics.y(75.5))

                Text("Finding your\nfirst climb")
                    .font(.montserratBold(size: metrics.font(28)))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: metrics.width(334), alignment: .center)
                    .position(x: metrics.x(195), y: metrics.y(168))

                PostAuthPlanLandmarkCarousel(
                    cards: carouselCards,
                    currentIndex: carouselIndex,
                    metrics: metrics
                )
                    .position(x: metrics.x(195), y: metrics.y(392))

                VStack(alignment: .leading, spacing: metrics.height(18)) {
                    ForEach(checklistItems.indices, id: \.self) { index in
                        if shouldShowChecklistItem(at: index) {
                            PostAuthPlanChecklistRow(
                                title: checklistItems[index].title,
                                state: checklistState(for: index),
                                shouldCelebrateCheck: celebratingCheckIndex == index,
                                metrics: metrics
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.86), value: activeChecklistIndex)
                .animation(.spring(response: 0.4, dampingFraction: 0.86), value: completedChecklistCount)
                .frame(width: metrics.width(300), alignment: .leading)
                .position(x: metrics.x(195), y: metrics.y(632))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .task {
            await runLoadingSequence()
        }
    }

    private var progressFraction: CGFloat {
        guard PostAuthOnboardingStage.plannedStepCount > 0 else { return 0 }
        return CGFloat(stage.progressIndex + 1) / CGFloat(PostAuthOnboardingStage.plannedStepCount)
    }

    private func checklistState(for index: Int) -> PostAuthPlanChecklistState {
        if index < completedChecklistCount {
            return .complete
        }
        if index == activeChecklistIndex {
            return .active
        }
        return .pending
    }

    private func shouldShowChecklistItem(at index: Int) -> Bool {
        index <= activeChecklistIndex || index < completedChecklistCount
    }

    @MainActor
    private func runLoadingSequence() async {
        guard !didAdvance else { return }
        didAdvance = true
        let recommendedClimb = PostAuthFirstClimbRecommendationPolicy.recommendedClimb()
        carouselCards = PostAuthPlanCarouselCard.loadingCards(excludingClimbID: recommendedClimb.id)
        carouselIndex = 0
        activeChecklistIndex = -1
        completedChecklistCount = 0
        celebratingCheckIndex = nil

        guard await sleep(milliseconds: 260) else { return }

        for index in checklistItems.indices {
            guard !Task.isCancelled else { return }
            let item = checklistItems[index]

            withAnimation(.easeInOut(duration: 0.24)) {
                activeChecklistIndex = index
            }

            guard await animateLoadingStep(
                durationMilliseconds: item.durationMilliseconds
            ) else {
                return
            }

            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                completedChecklistCount = index + 1
                celebratingCheckIndex = index
            }

            guard await sleep(milliseconds: 420) else { return }

            withAnimation(.easeOut(duration: 0.18)) {
                celebratingCheckIndex = nil
            }
        }

        guard !Task.isCancelled else { return }

        guard await sleep(milliseconds: 700) else { return }
        trackPostAuthInput(stage: stage)
        onContinue()
    }

    @MainActor
    private func animateLoadingStep(durationMilliseconds: Int) async -> Bool {
        let tickMilliseconds = 900
        let ticks = max(1, (durationMilliseconds + tickMilliseconds - 1) / tickMilliseconds)

        for _ in 1...ticks {
            guard await sleep(milliseconds: tickMilliseconds) else { return false }

            withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
                carouselIndex = (carouselIndex + 1) % max(carouselCards.count, 1)
            }
        }

        return true
    }

    @MainActor
    private func sleep(milliseconds: Int) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

private struct PostAuthPlanLandmarkCarousel: View {
    let cards: [PostAuthPlanCarouselCard]
    let currentIndex: Int
    let metrics: PostAuthProfileMetrics

    var body: some View {
        ZStack {
            PostAuthPlanLandmarkCard(
                card: card(offset: -1),
                metrics: metrics,
                isPrimary: false
            )
                .frame(width: metrics.width(172), height: metrics.height(258))
                .offset(x: -metrics.width(152), y: metrics.height(18))
                .opacity(0.52)

            PostAuthPlanLandmarkCard(
                card: card(offset: 1),
                metrics: metrics,
                isPrimary: false
            )
                .frame(width: metrics.width(172), height: metrics.height(258))
                .offset(x: metrics.width(152), y: metrics.height(18))
                .opacity(0.52)

            PostAuthPlanLandmarkCard(
                card: card(offset: 0),
                metrics: metrics,
                isPrimary: true
            )
                .id(card(offset: 0).id)
                .frame(width: metrics.width(210), height: metrics.height(298))
                .shadow(color: .black.opacity(0.42), radius: metrics.width(18), x: 0, y: metrics.height(10))
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        }
        .frame(width: metrics.width(430), height: metrics.height(322))
    }

    private func card(offset: Int) -> PostAuthPlanCarouselCard {
        guard !cards.isEmpty else { return PostAuthPlanCarouselCard.defaults[0] }
        let count = cards.count
        let index = ((currentIndex + offset) % count + count) % count
        return cards[index]
    }
}

private struct PostAuthPlanLandmarkCard: View {
    let card: PostAuthPlanCarouselCard
    let metrics: PostAuthProfileMetrics
    let isPrimary: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(card.imageName)
                .resizable()
                .scaledToFill()

            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(isPrimary ? 0.68 : 0.78)
                ],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: metrics.height(3)) {
                Text(card.name)
                    .font(.montserratBold(size: metrics.font(isPrimary ? 15 : 11)))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.74)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, metrics.width(isPrimary ? 14 : 10))
            .padding(.bottom, metrics.height(isPrimary ? 14 : 10))
        }
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius(10), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.radius(10), style: .continuous)
                .stroke(.white.opacity(isPrimary ? 0.22 : 0.1), lineWidth: 1)
        }
    }
}

private struct PostAuthPlanChecklistRow: View {
    let title: String
    let state: PostAuthPlanChecklistState
    let shouldCelebrateCheck: Bool
    let metrics: PostAuthProfileMetrics

    @State private var activePulse = false

    var body: some View {
        HStack(spacing: metrics.width(10)) {
            ZStack {
                if state == .active {
                    Circle()
                        .stroke(OnboardingValuePalette.lime.opacity(activePulse ? 0.08 : 0.5), lineWidth: 1)
                        .frame(width: metrics.width(18), height: metrics.height(18))
                        .scaleEffect(activePulse ? 1.28 : 0.82)
                }

                Circle()
                    .fill(indicatorFill)
                    .frame(width: metrics.width(13), height: metrics.height(13))
                    .scaleEffect(shouldCelebrateCheck ? 1.18 : 1)

                if state == .complete {
                    Image(systemName: "checkmark")
                        .font(.system(size: metrics.font(7), weight: .black))
                        .foregroundStyle(.black)
                } else if state == .active {
                    Circle()
                        .fill(OnboardingValuePalette.lime)
                        .frame(width: metrics.width(5.5), height: metrics.height(5.5))
                }
            }
            .frame(width: metrics.width(20), height: metrics.height(20))
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: state)
            .animation(.easeInOut(duration: 0.16).repeatCount(2, autoreverses: true), value: shouldCelebrateCheck)
            .accessibilityHidden(true)

            Text(title)
                .font(.montserratSemiBold(size: metrics.font(15)))
                .foregroundStyle(.white.opacity(textOpacity))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 0)
        }
        .task(id: state) {
            guard state == .active else {
                activePulse = false
                return
            }

            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.72)) {
                    activePulse.toggle()
                }

                do {
                    try await Task.sleep(nanoseconds: 720_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private var indicatorFill: Color {
        switch state {
        case .complete:
            OnboardingValuePalette.lime
        case .active:
            OnboardingValuePalette.lime.opacity(0.22)
        case .pending:
            .white.opacity(0.14)
        }
    }

    private var textOpacity: Double {
        switch state {
        case .complete:
            0.92
        case .active:
            0.86
        case .pending:
            0.48
        }
    }
}

private enum PostAuthPlanChecklistState: Equatable {
    case pending
    case active
    case complete
}

private struct PostAuthPlanCarouselCard: Identifiable, Equatable {
    let id: String
    let name: String
    let imageName: String

    static func loadingCards(excludingClimbID climbID: String) -> [PostAuthPlanCarouselCard] {
        let cards = defaults.filter { $0.id != climbID }
        return cards.isEmpty ? defaults : cards
    }

    static func card(for climb: Climb) -> PostAuthPlanCarouselCard? {
        defaults.first { $0.id == climb.id }
    }

    fileprivate static let defaults: [PostAuthPlanCarouselCard] = [
        .init(
            id: "eiffel-tower",
            name: "Eiffel Tower",
            imageName: "OnboardingLandmarkEiffelCard"
        ),
        .init(
            id: "burj-khalifa",
            name: "Burj Khalifa",
            imageName: "OnboardingLandmarkBurjCard"
        ),
        .init(
            id: "machu-picchu",
            name: "Machu Picchu",
            imageName: "OnboardingLandmarkMachuCard"
        ),
        .init(
            id: "statue-of-liberty",
            name: "Statue of Liberty",
            imageName: "OnboardingLandmarkStatueCard"
        ),
        .init(
            id: "mount-everest",
            name: "Mount Everest",
            imageName: "OnboardingLandmarkEverestCard"
        ),
        .init(
            id: "empire-state-building",
            name: "Empire State Building",
            imageName: "OnboardingLandmarkEmpireCard"
        )
    ]
}

private struct PostAuthPlanChecklistItem: Identifiable {
    let id: String
    let title: String
    let durationMilliseconds: Int

    static let defaults: [PostAuthPlanChecklistItem] = [
        .init(
            id: "baseline",
            title: "Reading your baseline",
            durationMilliseconds: 2_300
        ),
        .init(
            id: "first-climb",
            title: "Getting your first climb ready",
            durationMilliseconds: 2_500
        ),
        .init(
            id: "finishing",
            title: "Finishing up",
            durationMilliseconds: 2_200
        )
    ]
}

private enum PostAuthFirstClimbRecommendationPolicy {
    @MainActor
    static func recommendedClimb(
        answers: PreAuthOnboardingSurveyAnswers = PreAuthOnboardingSurveyStore().answers(),
        climbService: ClimbService = .shared
    ) -> Climb {
        let targetClimbID = recommendationID(for: answers)

        if let climb = try? climbService.climb(for: targetClimbID) {
            return climb
        }

        if let climb = try? climbService.climb(for: "leaning-tower-of-pisa") {
            return climb
        }

        if let climb = try? climbService.climb(for: "statue-of-liberty") {
            return climb
        }

        return .preview
    }

    private static func recommendationID(for answers: PreAuthOnboardingSurveyAnswers) -> String {
        switch answers.stairStepperExperience {
        case "never_tried":
            return neverTriedRecommendation(for: answers.exerciseLevel)
        case "tried_a_few_times":
            return triedAFewTimesRecommendation(for: answers.exerciseLevel)
        case "occasionally":
            return "eiffel-tower"
        case "all_the_time":
            return "empire-state-building"
        default:
            return isLowExercise(answers.exerciseLevel) ? "leaning-tower-of-pisa" : "statue-of-liberty"
        }
    }

    private static func neverTriedRecommendation(for exerciseLevel: String?) -> String {
        switch exerciseLevel {
        case "new_to_regular_exercise", nil:
            return "leaning-tower-of-pisa"
        case "one_two_per_week":
            return "statue-of-liberty"
        case "three_four_per_week", "five_plus_per_week":
            return "statue-of-liberty"
        default:
            return "statue-of-liberty"
        }
    }

    private static func triedAFewTimesRecommendation(for exerciseLevel: String?) -> String {
        switch exerciseLevel {
        case "new_to_regular_exercise", nil:
            return "statue-of-liberty"
        case "one_two_per_week":
            return "eiffel-tower"
        case "three_four_per_week", "five_plus_per_week":
            return "empire-state-building"
        default:
            return "eiffel-tower"
        }
    }

    private static func isLowExercise(_ exerciseLevel: String?) -> Bool {
        exerciseLevel == nil || exerciseLevel == "new_to_regular_exercise"
    }
}

private struct PostAuthFirstClimbRevealScreen: View {
    @Environment(AuthenticationViewModel.self) private var authVM

    let stage: PostAuthOnboardingStage
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var isSaving = false

    @MainActor
    private var firstClimb: Climb {
        PostAuthFirstClimbRecommendationPolicy.recommendedClimb()
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = PostAuthProfileMetrics(size: geometry.size)

            ZStack(alignment: .topLeading) {
                PostAuthProfilePalette.background
                    .ignoresSafeArea()

                OnboardingBackButton(action: onBack)
                    .position(
                        x: metrics.x(OnboardingChromeMetrics.backButtonLeadingPadding + OnboardingChromeMetrics.backButtonSize / 2),
                        y: metrics.y(OnboardingChromeMetrics.backButtonTopPadding + OnboardingChromeMetrics.backButtonSize / 2)
                    )

                PostAuthProfileProgressBar(progress: progressFraction)
                    .frame(width: metrics.width(169), height: metrics.height(5))
                    .position(x: metrics.x(195.5), y: metrics.y(75.5))

                Text("Your first climb is\nready")
                    .font(.montserratBold(size: metrics.font(28)))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: metrics.width(334), alignment: .center)
                    .position(x: metrics.x(195), y: metrics.y(160))

                PostAuthFirstClimbCard(climb: firstClimb, metrics: metrics)
                    .frame(width: metrics.width(300), height: metrics.height(400))
                    .position(x: metrics.x(195), y: metrics.y(444))

                if let message = authVM.errorMessage {
                    Text(message)
                        .font(.montserratMedium(size: metrics.font(11)))
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: metrics.width(334), alignment: .center)
                        .position(x: metrics.x(195), y: metrics.y(670))
                }

                Button(action: saveFirstClimb) {
                    Text(isSaving ? "SAVING..." : "VIEW CLIMB")
                        .font(.montserratBold(size: metrics.font(16)))
                        .foregroundStyle(.black.opacity(isSaving ? 0.45 : 0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: metrics.radius(12), style: .continuous)
                                .fill(OnboardingValuePalette.lime.opacity(isSaving ? 0.45 : 1))
                        )
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .frame(width: metrics.width(334), height: metrics.height(56))
                .position(x: metrics.x(195), y: metrics.y(740))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }

    private var progressFraction: CGFloat {
        guard PostAuthOnboardingStage.plannedStepCount > 0 else { return 0 }
        return CGFloat(stage.progressIndex + 1) / CGFloat(PostAuthOnboardingStage.plannedStepCount)
    }

    private func saveFirstClimb() {
        guard !isSaving else { return }

        Task { @MainActor in
            isSaving = true
            let didSave = await authVM.updateOnboardingFirstClimb(firstClimb.id)
            isSaving = false

            if didSave {
                if let userId = authVM.user?.uid {
                    OnboardingFirstClimbHandoffStore().stage(climbId: firstClimb.id, for: userId)
                }
                TelemetryManager.shared.setUserProperty("first_climb_selected", value: "true")
                OnboardingAnalyticsUserProperties.setFirstClimb(firstClimb)
                TelemetryManager.shared.track(
                    OnboardingAnalyticsEvent.firstClimbSelected(
                        context: stage.analyticsContext,
                        climbID: firstClimb.id,
                        climbName: firstClimb.name
                    )
                )
                trackPostAuthInput(
                    stage: stage,
                    properties: [
                        "climb_id": .string(firstClimb.id),
                        "climb_name": .string(firstClimb.name)
                    ]
                )
                onContinue()
            }
        }
    }
}

private struct PostAuthFirstClimbCard: View {
    let climb: Climb
    let metrics: PostAuthProfileMetrics

    var body: some View {
        artwork
            .frame(width: metrics.width(300), height: metrics.height(400))
            .clipShape(RoundedRectangle(cornerRadius: metrics.radius(16), style: .continuous))
            .overlay(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.74)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: metrics.radius(16), style: .continuous))
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: metrics.height(4)) {
                    Text(climb.name)
                        .font(.montserratBold(size: metrics.font(14)))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)

                    Text("\(climb.referenceStepCount.formatted()) steps · \(estimatedTimeText)")
                        .font(.montserratBold(size: metrics.font(10)))
                        .foregroundStyle(OnboardingValuePalette.lime)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .padding(.horizontal, metrics.width(14))
                .padding(.bottom, metrics.height(16))
            }
            .overlay {
                RoundedRectangle(cornerRadius: metrics.radius(16), style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.36), radius: metrics.width(18), x: 0, y: metrics.height(12))
    }

    @ViewBuilder
    private var artwork: some View {
        if let card = PostAuthPlanCarouselCard.card(for: climb) {
            Image(card.imageName)
                .resizable()
                .scaledToFill()
        } else {
            ClimbArtworkView(climb: climb, variant: .card)
        }
    }

    private var estimatedTimeText: String {
        ClimbEstimatedTimeFormatter.estimatedTimeText(
            for: climb.referenceStepCount,
            spm: 65
        )
    }
}

private struct PostAuthProfileQuestionShell<Content: View>: View {
    let stage: PostAuthOnboardingStage
    var eyebrow = "COMPLETE YOUR PROFILE"
    let headline: String
    var subtitle: String?
    let primaryTitle: String
    let isContinueEnabled: Bool
    let onBack: () -> Void
    let onContinue: () -> Void
    @ViewBuilder let content: (PostAuthProfileMetrics) -> Content

    var body: some View {
        GeometryReader { geometry in
            let metrics = PostAuthProfileMetrics(size: geometry.size)

            ZStack(alignment: .topLeading) {
                PostAuthProfilePalette.background
                    .ignoresSafeArea()

                OnboardingBackButton(action: onBack)
                    .position(
                        x: metrics.x(OnboardingChromeMetrics.backButtonLeadingPadding + OnboardingChromeMetrics.backButtonSize / 2),
                        y: metrics.y(OnboardingChromeMetrics.backButtonTopPadding + OnboardingChromeMetrics.backButtonSize / 2)
                    )

                PostAuthProfileProgressBar(progress: progressFraction)
                    .frame(width: metrics.width(169), height: metrics.height(5))
                    .position(x: metrics.x(195.5), y: metrics.y(75.5))

                VStack(alignment: .leading, spacing: metrics.height(5)) {
                    Text(eyebrow)
                        .font(.montserratSemiBold(size: metrics.font(11)))
                        .tracking(metrics.width(1.3))
                        .foregroundStyle(OnboardingValuePalette.lime)
                        .frame(width: metrics.width(334), height: metrics.height(16), alignment: .leading)

                    Text(headline)
                        .font(.montserratBold(size: metrics.font(28)))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(0)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: metrics.width(334), alignment: .topLeading)

                    if let subtitle {
                        Text(subtitle)
                            .font(.montserratMedium(size: metrics.font(11)))
                            .foregroundStyle(.white.opacity(0.52))
                            .multilineTextAlignment(.leading)
                            .lineSpacing(metrics.height(2))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: metrics.width(334), alignment: .topLeading)
                    }
                }
                .frame(width: metrics.width(334), alignment: .topLeading)
                .offset(x: metrics.x(28), y: metrics.y(154))

                content(metrics)

                Button(action: onContinue) {
                    Text(primaryTitle)
                        .font(.montserratBold(size: metrics.font(16)))
                        .foregroundStyle(.black.opacity(isContinueEnabled ? 0.9 : 0.45))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: metrics.radius(12), style: .continuous)
                                .fill(OnboardingValuePalette.lime.opacity(isContinueEnabled ? 1 : 0.45))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isContinueEnabled)
                .frame(width: metrics.width(334), height: metrics.height(56))
                .position(x: metrics.x(195), y: metrics.y(740))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }

    private var progressFraction: CGFloat {
        guard PostAuthOnboardingStage.plannedStepCount > 0 else { return 0 }
        let completedStepCount = min(max(stage.progressIndex + 1, 0), PostAuthOnboardingStage.plannedStepCount)
        return CGFloat(completedStepCount) / CGFloat(PostAuthOnboardingStage.plannedStepCount)
    }
}

private struct PostAuthProfileProgressBar: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.2))

                Capsule(style: .continuous)
                    .fill(OnboardingValuePalette.lime)
                    .frame(width: geometry.size.width * min(max(progress, 0), 1))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Profile onboarding progress")
        .accessibilityValue("\(Int(min(max(progress, 0), 1) * 100)) percent")
    }
}

private struct PostAuthProfileOptionRow: View {
    let title: String
    let isSelected: Bool
    let metrics: PostAuthProfileMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.montserratSemiBold(size: metrics.font(12)))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, metrics.width(18))
                .background(PostAuthProfilePalette.fieldBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: metrics.radius(6), style: .continuous)
                        .stroke(isSelected ? OnboardingValuePalette.lime.opacity(0.72) : .white.opacity(0.16), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: metrics.radius(6), style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct PostAuthBodyMetricColumn<Content: View>: View {
    let title: String
    let metrics: PostAuthProfileMetrics
    let content: Content

    init(
        title: String,
        metrics: PostAuthProfileMetrics,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.metrics = metrics
        self.content = content()
    }

    var body: some View {
        VStack(spacing: metrics.height(8)) {
            Text(title)
                .font(.montserratBold(size: metrics.font(9)))
                .foregroundStyle(.white.opacity(0.54))
                .tracking(1.5)
                .frame(maxWidth: .infinity)

            content
        }
        .frame(width: metrics.width(156), alignment: .top)
    }
}

private struct PostAuthBirthdayWheelPicker: View {
    @Binding var selectedBirthday: Date
    let metrics: PostAuthProfileMetrics

    var body: some View {
        ZStack {
            DatePicker(
                "Birthday",
                selection: $selectedBirthday,
                in: allowedRange,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(width: metrics.width(320), height: metrics.height(200))
            .clipped()
            .colorScheme(.dark)
        }
        .frame(width: metrics.width(320), height: metrics.height(200), alignment: .center)
        .background(PostAuthProfilePalette.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius(8), style: .continuous))
        .accessibilityLabel("Birthday")
        .accessibilityValue(selectedBirthday.formatted(date: .long, time: .omitted))
    }

    private var allowedRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let oldest = calendar.date(byAdding: .year, value: -120, to: today) ?? today
        let youngest = calendar.date(byAdding: .year, value: -13, to: today) ?? today
        return oldest...youngest
    }
}

private struct PostAuthHeightWheelPicker: View {
    @Binding var selectedHeightInches: Int
    let measurementSystem: MeasurementSystem
    let metrics: PostAuthProfileMetrics

    private let heightRange = Array(36...94)

    var body: some View {
        ZStack {
            Picker("Height", selection: $selectedHeightInches) {
                ForEach(heightRange, id: \.self) { inches in
                    Text(displayText(for: inches))
                        .font(.montserratBold(size: metrics.font(24)))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .tag(inches)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(width: metrics.width(148), height: metrics.height(150))
            .clipped()
            .colorScheme(.dark)

            RoundedRectangle(cornerRadius: metrics.radius(8), style: .continuous)
                .stroke(OnboardingValuePalette.lime.opacity(0.9), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .frame(width: metrics.width(156), height: metrics.height(156), alignment: .center)
        .background(PostAuthProfilePalette.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius(8), style: .continuous))
        .accessibilityLabel("Height")
        .accessibilityValue(displayText(for: selectedHeightInches))
    }

    private func displayText(for inches: Int) -> String {
        switch measurementSystem {
        case .imperial:
            return "\(inches / 12)'\(inches % 12)\""
        case .metric:
            let centimeters = MeasurementSystem.imperial.convertHeight(Double(inches), to: .metric)
            return "\(Int(centimeters.rounded())) cm"
        }
    }
}

private struct PostAuthWeightWheelPicker: View {
    @Binding var selectedWeight: Int
    let measurementSystem: MeasurementSystem
    let metrics: PostAuthProfileMetrics

    var body: some View {
        ZStack {
            Picker("Weight", selection: $selectedWeight) {
                ForEach(weightRange, id: \.self) { weight in
                    Text(displayText(for: weight))
                        .font(.montserratBold(size: metrics.font(24)))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .tag(weight)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(width: metrics.width(148), height: metrics.height(150))
            .clipped()
            .colorScheme(.dark)

            RoundedRectangle(cornerRadius: metrics.radius(8), style: .continuous)
                .stroke(OnboardingValuePalette.lime.opacity(0.9), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .frame(width: metrics.width(156), height: metrics.height(156), alignment: .center)
        .background(PostAuthProfilePalette.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius(8), style: .continuous))
        .accessibilityLabel("Weight")
        .accessibilityValue(displayText(for: selectedWeight))
    }

    private var weightRange: [Int] { Array(Self.range(for: measurementSystem)) }

    private func displayText(for weight: Int) -> String {
        "\(weight) \(measurementSystem.weightAbbreviation)"
    }

    /// Selectable weight bounds per measurement system, in that system's own unit.
    static func range(for system: MeasurementSystem) -> ClosedRange<Int> {
        switch system {
        case .imperial: return 50...400
        case .metric: return 25...200
        }
    }

    /// Clamps a converted weight into the destination system's selectable range so the
    /// wheel selection always matches an existing row after a unit toggle.
    static func clamp(_ value: Int, to system: MeasurementSystem) -> Int {
        let bounds = range(for: system)
        return min(max(value, bounds.lowerBound), bounds.upperBound)
    }
}

private struct PostAuthCitySearchField: View {
    @Binding var query: String
    let isSearching: Bool
    let metrics: PostAuthProfileMetrics
    let focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: metrics.width(10)) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: metrics.font(14), weight: .semibold))
                .foregroundStyle(.white.opacity(0.46))
                .frame(width: metrics.width(18), height: metrics.height(18))

            TextField(
                "",
                text: $query,
                prompt: Text("Search city")
                    .foregroundStyle(.white.opacity(0.46))
            )
            .font(.montserratBold(size: metrics.font(12)))
            .foregroundStyle(.white.opacity(0.92))
            .tint(OnboardingValuePalette.lime)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused(focused)

            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .tint(OnboardingValuePalette.lime)
                    .frame(width: metrics.width(18), height: metrics.height(18))
            }
        }
        .padding(.horizontal, metrics.width(18))
        .frame(width: metrics.width(334), height: metrics.height(52), alignment: .center)
        .background(PostAuthProfilePalette.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius(6), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.radius(6), style: .continuous)
                .stroke(focused.wrappedValue ? OnboardingValuePalette.lime.opacity(0.9) : .white.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct PostAuthCurrentLocationRow: View {
    let isResolving: Bool
    let metrics: PostAuthProfileMetrics

    var body: some View {
        HStack(spacing: metrics.width(12)) {
            Image(systemName: "location.fill")
                .font(.system(size: metrics.font(15), weight: .semibold))
                .foregroundStyle(OnboardingValuePalette.lime)
                .frame(width: metrics.width(20), height: metrics.height(20))

            Text("Current location")
                .font(.montserratBold(size: metrics.font(12)))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 0)

            if isResolving {
                ProgressView()
                    .controlSize(.small)
                    .tint(OnboardingValuePalette.lime)
                    .frame(width: metrics.width(18), height: metrics.height(18))
            }
        }
        .padding(.horizontal, metrics.width(16))
        .frame(width: metrics.width(334), height: metrics.height(52), alignment: .center)
        .background(PostAuthProfilePalette.fieldBackground.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius(6), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.radius(6), style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current location")
    }
}

private struct PostAuthCitySuggestionRow: View {
    let suggestion: PostAuthCitySearchSuggestion
    let metrics: PostAuthProfileMetrics

    var body: some View {
        HStack(spacing: metrics.width(12)) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: metrics.font(14), weight: .semibold))
                .foregroundStyle(OnboardingValuePalette.lime)
                .frame(width: metrics.width(20), height: metrics.height(20))

            VStack(alignment: .leading, spacing: metrics.height(3)) {
                Text(suggestion.title)
                    .font(.montserratBold(size: metrics.font(11)))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                if !suggestion.subtitle.isEmpty {
                    Text(suggestion.subtitle)
                        .font(.montserratMedium(size: metrics.font(9)))
                        .foregroundStyle(.white.opacity(0.46))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.width(16))
        .frame(width: metrics.width(334), height: metrics.height(52), alignment: .center)
        .background(PostAuthProfilePalette.fieldBackground.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius(6), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.radius(6), style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct PostAuthSelectedCityRow: View {
    let selection: PostAuthLocationSelection
    let metrics: PostAuthProfileMetrics

    var body: some View {
        HStack(spacing: metrics.width(12)) {
            ZStack {
                Circle()
                    .fill(OnboardingValuePalette.lime)
                    .frame(width: metrics.width(16), height: metrics.height(16))

                Image(systemName: "checkmark")
                    .font(.system(size: metrics.font(8), weight: .black))
                    .foregroundStyle(Color.black.opacity(0.88))
            }

            VStack(alignment: .leading, spacing: metrics.height(3)) {
                Text(selection.title)
                    .font(.montserratBold(size: metrics.font(12)))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(selection.subtitle)
                    .font(.montserratMedium(size: metrics.font(9)))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.width(18))
        .frame(width: metrics.width(334), height: metrics.height(58), alignment: .center)
        .background(PostAuthProfilePalette.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius(6), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.radius(6), style: .continuous)
                .stroke(OnboardingValuePalette.lime.opacity(0.9), lineWidth: 1)
        }
    }
}

private struct PostAuthProfileMetrics {
    let size: CGSize

    private var scaleX: CGFloat { size.width / 390 }
    private var scaleY: CGFloat { size.height / 844 }
    private var typeScale: CGFloat { min(scaleX, scaleY) }

    func x(_ value: CGFloat) -> CGFloat { value * scaleX }
    func y(_ value: CGFloat) -> CGFloat { value * scaleY }
    func width(_ value: CGFloat) -> CGFloat { value * scaleX }
    func height(_ value: CGFloat) -> CGFloat { value * scaleY }
    func font(_ value: CGFloat) -> CGFloat { value * typeScale }
    func radius(_ value: CGFloat) -> CGFloat { value * typeScale }
}

private enum PostAuthProfilePalette {
    static let background = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
    static let fieldBackground = Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255).opacity(0.95)
}

private struct PostAuthGenderOption: Identifiable {
    let id: ProfileGender
    let title: String
    let gender: ProfileGender

    static let all: [PostAuthGenderOption] = [
        .init(id: .man, title: "Male", gender: .man),
        .init(id: .woman, title: "Female", gender: .woman),
        .init(id: .nonBinary, title: "Other", gender: .nonBinary),
        .init(id: .preferNotToSay, title: "Prefer not to say", gender: .preferNotToSay)
    ]
}

#Preview("Post-Auth Onboarding") {
    PostAuthOnboardingFlowView(
        stage: .displayName,
        onBack: {},
        onContinue: {}
    )
    .environment(AuthenticationViewModel())
}
