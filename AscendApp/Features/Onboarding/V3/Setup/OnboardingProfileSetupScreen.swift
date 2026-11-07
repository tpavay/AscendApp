import PhotosUI
import SwiftUI

/// 08: set up your profile. A live leaderboard row of the climber's own entry, a name, a photo and
/// four optional facts, on one screen that does not scroll. All of it is skippable.
///
/// Writes only the pre-sign-in answers on the device; the profile write waits for sign-in.
struct OnboardingProfileSetupScreen: View {
    private enum Field: Hashable {
        case firstName, lastName
    }

    private enum Sheet: String, Identifiable {
        case birthday, height, weight

        var id: String { rawValue }
    }

    private static let nameLimit = 40

    let coordinator: OnboardingV3Coordinator

    @State private var draft: ProfileSetupDraft
    @State private var photoURL: URL?
    @State private var pickerItem: PhotosPickerItem?
    @State private var sheet: Sheet?
    @FocusState private var focus: Field?

    private let photos: OnboardingProfilePhotoStore
    private let units: ProfileUnitPreference
    private let birthdayNow: Date

    init(
        coordinator: OnboardingV3Coordinator,
        system: MeasurementSystem? = nil,
        photos: OnboardingProfilePhotoStore = OnboardingProfilePhotoStore(),
        units: ProfileUnitPreference = ProfileUnitPreference(),
        now: Date = .now
    ) {
        self.coordinator = coordinator
        self.photos = photos
        self.units = units
        birthdayNow = now
        _draft = State(initialValue: ProfileSetupDraft(answers: coordinator.answers, system: system ?? units.system))
        _photoURL = State(initialValue: photos.url(for: coordinator.answers.profilePhotoFileName))
    }

    var body: some View {
        OnboardingSetupLayout(
            step: .profileSetup,
            onSkip: { Self.skip(coordinator, photos: photos) },
            horizontalPadding: 20
        ) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    OnboardingHeadline(["Set up your"], accentLines: ["profile."], size: 30)

                    Text("This is how you show up on every leaderboard and live climb.")
                        .font(.custom("Montserrat-Medium", size: 14, relativeTo: .subheadline))
                        .foregroundStyle(OnboardingV3Palette.secondary)
                        .lineSpacing(14 * 0.4)
                }
                .padding(.horizontal, 4)
                .onboardingEntrance(index: 0)

                preview
                    .onboardingEntrance(index: 1)

                identityGroup
                    .onboardingEntrance(index: 2)

                bodyGroup
                    .onboardingEntrance(index: 3)
            }
        } footer: {
            VStack(spacing: 10) {
                Text("All optional. Change any of it in Settings.")
                    .font(.custom("Montserrat-SemiBold", size: 12.5, relativeTo: .footnote))
                    .foregroundStyle(OnboardingV3Palette.footnote)
                    .multilineTextAlignment(.center)

                Button("Continue", action: continueTapped)
                    .buttonStyle(.onboardingPrimary)
            }
        }
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await adoptPhoto(item) }
        }
        .trackOnce(screen: .onboardingProfileSetup)
    }

    // MARK: - Actions

    /// Skip leaves everything unset, clearing an earlier pass's answers and its photo.
    static func skip(
        _ coordinator: OnboardingV3Coordinator,
        photos: OnboardingProfilePhotoStore = OnboardingProfilePhotoStore()
    ) {
        coordinator.update { ProfileSetupDraft.clearAnswers(in: &$0) }
        photos.remove()
        coordinator.advance()
    }

    private func continueTapped() {
        coordinator.update { draft.apply(to: &$0) }
        photos.remove(keeping: draft.photoFileName)
        coordinator.advance()
    }

    private func adoptPhoto(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }

        guard let data = try? await item.loadTransferable(type: Data.self) else { return }

        let photos = photos
        let name = await Task.detached { photos.save(data) }.value
        guard let name, let url = photos.url(for: name) else { return }

        draft.photoFileName = name
        photoURL = url
    }

    // MARK: - Preview

    private var preview: some View {
        ProfileLeaderboardPreview(draft: draft, photoURL: photoURL, pickerItem: $pickerItem, now: birthdayNow)
    }

    // MARK: - Name, gender, birthday

    private var identityGroup: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                nameField("First name", text: $draft.firstName, field: .firstName, contentType: .givenName)
                nameField("Last name", text: $draft.lastName, field: .lastName, contentType: .familyName)
            }

            genderControl

            ProfileSetupRows(rows: [
                .init(title: "Birthday", value: draft.birthdayRowText(on: birthdayNow)) { present(.birthday) }
            ])
        }
    }

    private func nameField(
        _ title: String,
        text: Binding<String>,
        field: Field,
        contentType: UITextContentType
    ) -> some View {
        TextField(
            title,
            text: text,
            prompt: Text(title).foregroundStyle(OnboardingV3Palette.placeholder)
        )
        .font(.custom("Montserrat-Bold", size: 15, relativeTo: .body))
        .foregroundStyle(.white)
        .tint(OnboardingV3Palette.accent)
        .textContentType(contentType)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .submitLabel(field == .firstName ? .next : .done)
        .focused($focus, equals: field)
        .onSubmit { focus = field == .firstName ? .lastName : nil }
        .onChange(of: text.wrappedValue) { _, new in
            if new.count > Self.nameLimit { text.wrappedValue = String(new.prefix(Self.nameLimit)) }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(OnboardingV3Palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OnboardingV3Palette.fieldBorder, lineWidth: 1)
        )
        .accessibilityLabel(title)
    }

    private var genderControl: some View {
        HStack(spacing: 4) {
            ForEach(ProfileSetupDraft.genderChoices, id: \.gender) { choice in
                let isSelected = draft.gender == choice.gender

                Button {
                    HapticsManager.shared.trigger(.selection)
                    draft.gender = isSelected ? nil : choice.gender
                } label: {
                    Text(choice.title)
                        .font(.custom("Montserrat-ExtraBold", size: 15, relativeTo: .body))
                        .foregroundStyle(isSelected ? Color.black : Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(isSelected ? OnboardingV3Palette.accent : .clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(OnboardingV3Palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OnboardingV3Palette.fieldBorder, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: draft.gender)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Gender")
    }

    // MARK: - Height and weight

    private var bodyGroup: some View {
        ProfileSetupRows(rows: [
            .init(title: "Height", value: draft.heightRowText) { present(.height) },
            .init(title: "Weight", value: draft.weightRowText) { present(.weight) }
        ])
    }

    // MARK: - Sheets

    private func present(_ next: Sheet) {
        focus = nil
        HapticsManager.shared.trigger(.selection)
        sheet = next
    }

    @ViewBuilder
    private func sheetContent(_ sheet: Sheet) -> some View {
        switch sheet {
        case .birthday:
            ProfileBirthdaySheet(initial: draft.birthdayDate(), now: birthdayNow) { date in
                draft.setBirthday(from: date)
                self.sheet = nil
            }
        case .height:
            ProfileHeightSheet(
                initialCentimeters: draft.heightCm,
                system: draft.system,
                onUnitChange: rememberUnit
            ) { centimeters in
                draft.heightCm = centimeters
                self.sheet = nil
            }
        case .weight:
            ProfileWeightSheet(
                initialKilograms: draft.weightKg,
                system: draft.system,
                onUnitChange: rememberUnit
            ) { kilograms in
                draft.weightKg = kilograms
                self.sheet = nil
            }
        }
    }

    private func rememberUnit(_ system: MeasurementSystem) {
        units.remember(system)
        draft.system = system
    }
}

#Preview("08 profile") {
    OnboardingV3FlowView(coordinator: OnboardingV3Coordinator(
        store: PreAuthOnboardingStore(userDefaults: UserDefaults(suiteName: "onboarding-v3-preview-profile") ?? .standard),
        startingAt: .profileSetup
    ))
}
