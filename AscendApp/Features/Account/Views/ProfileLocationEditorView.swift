import SwiftUI

struct ProfileLocationEditorView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @StateObject private var citySearch = PostAuthCitySearchModel()
    @StateObject private var currentLocation = PostAuthCurrentLocationResolver()
    @FocusState private var isSearchFocused: Bool

    @State private var selectedLocation: PostAuthLocationSelection?
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    init(city: String?, region: String?, countryCode: String?) {
        let normalizedCity = city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedCountry = countryCode?.uppercased() ?? ""
        let countryName = Locale.current.localizedString(forRegionCode: normalizedCountry) ?? normalizedCountry
        let initialSelection: PostAuthLocationSelection? = normalizedCity.isEmpty || normalizedCountry.isEmpty
            ? nil
            : PostAuthLocationSelection(
                city: normalizedCity,
                region: region,
                countryCode: normalizedCountry,
                countryName: countryName
            )
        _selectedLocation = State(initialValue: initialSelection)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ProfileSection(title: "Location") {
                    ProfileCardSurface {
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.white.opacity(0.55))
                                    .accessibilityHidden(true)

                                TextField("Search for your city", text: $citySearch.query)
                                    .font(.montserratRegular(size: 16))
                                    .foregroundStyle(.white)
                                    .tint(.accent)
                                    .textInputAutocapitalization(.words)
                                    .autocorrectionDisabled()
                                    .focused($isSearchFocused)
                                    .accessibilityLabel("City search")
                            }
                            .padding(.horizontal, 20)
                            .frame(minHeight: 56)

                            ProfileCardDivider()

                            if let selectedLocation {
                                locationRow(
                                    title: selectedLocation.title,
                                    subtitle: selectedLocation.subtitle,
                                    icon: "mappin.and.ellipse"
                                )
                            } else {
                                Button {
                                    resolveCurrentLocation()
                                } label: {
                                    locationRow(
                                        title: currentLocation.isResolving ? "Finding your city..." : "Use Current Location",
                                        subtitle: "Ascend saves only your city, region, and country.",
                                        icon: "location.fill"
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(currentLocation.isResolving || citySearch.isResolving)

                                ForEach(citySearch.suggestions) { suggestion in
                                    ProfileCardDivider()
                                    Button {
                                        resolve(suggestion)
                                    } label: {
                                        locationRow(
                                            title: suggestion.title,
                                            subtitle: suggestion.subtitle,
                                            icon: "mappin"
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(currentLocation.isResolving || citySearch.isResolving)
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
                .disabled(selectedLocation == nil || isSaving)
                .opacity(selectedLocation == nil || isSaving ? 0.45 : 1)

                if let errorMessage = citySearch.errorMessage ?? currentLocation.errorMessage ?? saveErrorMessage {
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
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .keyboardDoneToolbar {
            isSearchFocused = false
        }
        .onAppear {
            if citySearch.query.isEmpty, let selectedLocation {
                citySearch.setSelectedLocation(selectedLocation)
            }
        }
        .onChange(of: citySearch.query) { _, newValue in
            currentLocation.clearError()
            guard let selectedLocation, newValue != selectedLocation.profileDisplayText else { return }
            self.selectedLocation = nil
        }
        .trackOnce(screen: .profileLocationEditor)
    }

    private func locationRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.accent)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func resolve(_ suggestion: PostAuthCitySearchSuggestion) {
        isSearchFocused = false
        Task { @MainActor in
            guard let location = await citySearch.resolve(suggestion) else { return }
            selectedLocation = location
        }
    }

    private func resolveCurrentLocation() {
        isSearchFocused = false
        Task { @MainActor in
            guard let location = await currentLocation.resolve() else { return }
            selectedLocation = location
            citySearch.setSelectedLocation(location)
        }
    }

    private func save() {
        guard !isSaving, let selectedLocation else { return }

        Task { @MainActor in
            isSaving = true
            saveErrorMessage = await authVM.scopedProfileUpdate(
                fallback: "Failed to update location"
            ) {
                await authVM.updateOnboardingLocation(
                    city: selectedLocation.city,
                    countryCode: selectedLocation.countryCode,
                    region: selectedLocation.region
                )
            }
            isSaving = false
            if saveErrorMessage == nil {
                dismiss()
            }
        }
    }
}
