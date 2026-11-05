import SwiftUI

/// 09: claim your city. Location or a typed search picks the city, the server's count says how
/// many climbers it has, and the city goes into the pre-sign-in answers. Skip leaves it unset.
///
/// This is the one onboarding screen with a text field: the "Type my city instead" search that
/// `PostAuthCitySearchModel` already runs. Nothing is typed unless the climber chooses to.
struct OnboardingClaimCityScreen: View {
    let coordinator: OnboardingV3Coordinator

    @State private var model: OnboardingCityClaimModel
    @StateObject private var search = PostAuthCitySearchModel()
    @StateObject private var locationResolver = PostAuthCurrentLocationResolver()
    @FocusState private var isSearchFocused: Bool

    init(coordinator: OnboardingV3Coordinator, model: OnboardingCityClaimModel? = nil) {
        self.coordinator = coordinator
        _model = State(initialValue: model ?? OnboardingCityClaimModel(initialCity: coordinator.answers.city))
    }

    var body: some View {
        let copy = model.copy

        GeometryReader { proxy in
            layout(copy: copy, isCompact: proxy.size.height < 720)
        }
        .animation(.easeInOut(duration: 0.3), value: model.phase)
        .task { await model.refreshCount() }
        .trackOnce(screen: .onboardingClaimCity)
    }

    /// The badge shrinks on the smallest phones so the copy under it is not left behind the
    /// button.
    private func layout(copy: OnboardingCityClaimCopy, isCompact: Bool) -> some View {
        let badgeScale: CGFloat = model.phase == .typing ? 0.5 : (isCompact ? 0.68 : 1)

        return OnboardingSetupLayout(step: .claimCity, onSkip: { Self.skip(coordinator) }) {
            VStack(alignment: .leading, spacing: 14) {
                CityBadge(kicker: OnboardingCityClaimCopy.badgeKicker, place: copy.badgePlace, pill: OnboardingCityClaimCopy.badgePill)
                    .scaleEffect(badgeScale)
                    .frame(height: 292 * badgeScale)
                    .frame(maxWidth: .infinity)
                    .onboardingEntrance(index: 0, style: .pop, duration: 0.55)

                OnboardingHeadline(["Claim your"], accentLines: ["city."], accent: .gold)
                    .onboardingEntrance(index: 1)

                Text(copy.body)
                    .onboardingBody()
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.25), value: copy.body)
                    .onboardingEntrance(index: 2)

                if let selection = model.selection, copy.badgePlace == "YOUR CITY" {
                    cityPill(selection)
                }

                if model.selection != nil {
                    Text("We only use your city, never your exact spot.")
                        .onboardingSecondary()
                }

                if model.phase == .typing {
                    searchSection
                }

                if let message = locationResolver.errorMessage {
                    Text(message)
                        .onboardingSecondary()
                        .foregroundStyle(OnboardingV3Palette.orange)
                }
            }
        } footer: {
            footer
        }
    }

    /// Skip leaves the city unset, clearing one an earlier pass claimed.
    static func skip(_ coordinator: OnboardingV3Coordinator) {
        coordinator.update { $0.city = nil }
        coordinator.advance()
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        switch model.phase {
        case .prompt:
            VStack(spacing: 4) {
                Button {
                    Task { await useMyLocation() }
                } label: {
                    HStack(spacing: 10) {
                        if locationResolver.isResolving {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "location.fill")
                        }
                        Text("Use my location")
                    }
                }
                .buttonStyle(.onboardingPrimary)
                .disabled(locationResolver.isResolving)

                Button("Type my city instead") {
                    locationResolver.clearError()
                    model.startTyping()
                    isSearchFocused = true
                }
                .buttonStyle(.onboardingQuietLink)
            }

        case .typing:
            Button("Use my location instead") {
                isSearchFocused = false
                model.stopTyping()
                Task { await useMyLocation() }
            }
            .buttonStyle(.onboardingQuietLink)

        case .located:
            VStack(spacing: 4) {
                Button("Continue") {
                    if let selection = model.selection {
                        coordinator.update { $0.city = PreAuthOnboardingCity(selection) }
                    }
                    coordinator.advance()
                }
                .buttonStyle(.onboardingPrimary)

                Button("Type a different city") {
                    model.startTyping()
                    isSearchFocused = true
                }
                .buttonStyle(.onboardingQuietLink)
            }
        }
    }

    // MARK: - Search

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(OnboardingV3Palette.secondary)

                TextField("Your city", text: $search.query)
                    .font(.custom("Montserrat-SemiBold", size: 17))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFocused)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .onboardingCard(cornerRadius: 16)

            ForEach(search.suggestions) { suggestion in
                Button {
                    Task { await choose(suggestion) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                            .font(.custom("Montserrat-ExtraBold", size: 16))
                            .foregroundStyle(.white)
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle)
                                .font(.custom("Montserrat-Medium", size: 13))
                                .foregroundStyle(OnboardingV3Palette.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onboardingCard(cornerRadius: 14)
                }
                .buttonStyle(.plain)
            }

            if let message = search.errorMessage {
                Text(message)
                    .onboardingSecondary()
                    .foregroundStyle(OnboardingV3Palette.orange)
            }
        }
    }

    private func cityPill(_ selection: PostAuthLocationSelection) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
            Text(selection.profileDisplayText)
        }
        .font(.custom("Montserrat-ExtraBold", size: 14))
        .foregroundStyle(OnboardingV3Palette.gold)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().strokeBorder(OnboardingV3Palette.gold.opacity(0.6), lineWidth: 1.5))
    }

    // MARK: - Actions

    private func useMyLocation() async {
        locationResolver.clearError()
        guard let selection = await locationResolver.resolve() else { return }
        isSearchFocused = false
        await model.claim(selection)
    }

    private func choose(_ suggestion: PostAuthCitySearchSuggestion) async {
        guard let selection = await search.resolve(suggestion) else { return }
        isSearchFocused = false
        await model.claim(selection)
    }
}

#Preview("09 claim your city") {
    OnboardingV3FlowView(coordinator: OnboardingV3Coordinator(
        store: PreAuthOnboardingStore(userDefaults: UserDefaults(suiteName: "onboarding-v3-preview-city") ?? .standard),
        startingAt: .claimCity
    ))
}
