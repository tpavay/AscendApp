import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// Reviewer-facing pixels for the Settings and Edit Profile reorganization.
///
/// `SettingsReorganizationContractTests` holds the shape of the source. This
/// holds what a climber actually sees: the shipping `AccountView`,
/// `EditProfileView`, `NotificationSettingsView`, `EmailPreferencesView`, and
/// every drill-in editor hosted in a real window and photographed, with the
/// rendered pixels read back so the section order, the row set, and the absence
/// of on/off summary text are asserted from the screen rather than from a
/// string in a Swift file.
@MainActor
@Suite(.hostsAWindow, .serialized)
struct SettingsReorganizationEvidenceTests {
    // MARK: - Settings

    @Test
    func settingsShowsPreferencesWhereTheyBelongAndPrivacyLast() async throws {
        let image = try await snapshot(
            NavigationStack {
                AccountView()
                    .environment(signedOutAuthentication(displayName: "Maya Chen"))
            },
            named: "settings-screen",
            height: 1500
        )

        let text = try await recognizedText(in: image)
        let lowercased = text.lowercased()

        // The board's section order, read off the screen top to bottom.
        try expectInOrder(
            ["profile", "notifications", "preferences", "subscription", "support", "privacy"],
            in: lowercased
        )

        // Every row the board keeps, and nothing that used to sit elsewhere.
        for row in [
            "edit profile",
            "push",
            "email",
            "units",
            "integrations",
            "restore purchases",
            "terms of service",
            "privacy policy",
            "contact us",
            "blocked climbers",
        ] {
            #expect(lowercased.contains(row), "Settings is missing the \(row) row")
        }

        // Notifications rows carry a chevron and nothing else: no state summary
        // that would have to be kept in step with the screen behind it.
        let words = Set(
            lowercased
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
        )
        #expect(!words.contains("on"), "A settings row is summarising its state as On")
        #expect(!words.contains("off"), "A settings row is summarising its state as Off")
        #expect(!lowercased.contains("measurement system"))
        #expect(!lowercased.contains("body metrics"))
    }

    // MARK: - Edit Profile

    @Test
    func editProfileReadsAsThreeGroupedCards() async throws {
        let image = try await snapshot(
            NavigationStack {
                EditProfileView()
                    .environment(signedOutAuthentication(displayName: "Maya Chen"))
            },
            named: "edit-profile-screen",
            height: 1000
        )

        let lowercased = try await recognizedText(in: image).lowercased()

        try expectInOrder(["profile", "personal information", "location"], in: lowercased)
        for row in ["first name", "last name", "birthday", "gender", "height", "weight"] {
            #expect(lowercased.contains(row), "Edit Profile is missing the \(row) row")
        }
        // Nothing the board cut may reappear on this screen.
        #expect(!lowercased.contains("bio"))
        #expect(!lowercased.contains("primary sport"))
        #expect(!lowercased.contains("integrations"))
        #expect(!lowercased.contains("measurement"))
        #expect(!lowercased.contains("preferences"))
    }

    /// The same rows with a climber's answers in them, so the formatted value on
    /// the right of each drill-in is visible rather than inferred. The screen
    /// itself reads its answers from Firestore, which a unit test has no session
    /// for, so the shipping `ProfileValueRow` is composed here in the card
    /// chrome `EditProfileView` builds around it.
    @Test
    func everyEditProfileRowCarriesItsFormattedValueOnTheRight() async throws {
        let image = try await snapshot(
            NavigationStack {
                PopulatedEditProfileEvidence()
                    .environment(signedOutAuthentication(displayName: "Maya Chen"))
            },
            named: "edit-profile-populated",
            height: 700
        )

        // Text recognition is inconsistent about the space in "175 cm", so the
        // comparison ignores whitespace rather than pinning an OCR quirk.
        let recognized = try await recognizedText(in: image)
            .lowercased()
            .replacing(" ", with: "")

        for value in ["maya", "chen", "mar14,1994", "woman", "175cm", "64kg", "boulder,co"] {
            #expect(recognized.contains(value), "Missing the \(value) value")
        }
    }

    @Test
    func aDrillInRowIsAtLeastATappableFortyFourPoints() throws {
        let row = ProfileValueRow(
            icon: .profileBirthday,
            title: "Birthday",
            value: "Mar 14, 1994",
            destination: EmptyView()
        )
        let height = UIHostingController(rootView: row.frame(width: 350))
            .sizeThatFits(in: CGSize(width: 350, height: CGFloat.greatestFiniteMagnitude))
            .height

        #expect(height >= 44, "Drill-in row is only \(height)pt tall")

        let settingsRowHeight = UIHostingController(
            rootView: SettingsRow(
                option: SettingsOption(icon: .settingsNotifications, title: "Push", action: {})
            )
            .frame(width: 350)
        )
        .sizeThatFits(in: CGSize(width: 350, height: CGFloat.greatestFiniteMagnitude))
        .height

        #expect(settingsRowHeight >= 44, "Settings row is only \(settingsRowHeight)pt tall")
    }

    // MARK: - Where the notification rows land

    @Test
    func pushCarriesOnlyTheExistingPushGranularity() async throws {
        let image = try await snapshot(
            NavigationStack {
                NotificationSettingsView()
            },
            named: "settings-push-screen",
            height: 560
        )

        let lowercased = try await recognizedText(in: image).lowercased()

        #expect(lowercased.contains("new climb drops"))
        #expect(lowercased.contains("ios permission"))
        // Email left this screen for its own row under Notifications.
        #expect(!lowercased.contains("ascend emails"))
        #expect(!lowercased.contains("email"))
    }

    @Test
    func emailRoutesToTheMergedEmailPreferencesScreen() async throws {
        let viewModel = EmailPreferencesViewModel(
            service: EvidenceEmailPreferencesService(storedConsent: LifecycleEmailConsent(isGranted: true))
        )
        await viewModel.load()

        let image = try await snapshot(
            NavigationStack {
                EmailPreferencesView(viewModel: viewModel)
            },
            named: "settings-email-screen",
            height: 560
        )

        let lowercased = try await recognizedText(in: image).lowercased()

        // The screen PR #399 shipped, reached from the new Notifications row.
        #expect(lowercased.contains("ascend emails"))
        #expect(lowercased.contains("when a climb drops"))
    }

    // MARK: - The drill-ins behind the rows

    @Test
    func everyEditProfileRowOpensItsOwnEditor() async throws {
        let authentication = signedOutAuthentication(displayName: "Maya Chen")

        let name = try await snapshot(
            NavigationStack {
                ProfileNameEditorView(field: .firstName, firstName: "Maya", lastName: "Chen")
                    .environment(authentication)
            },
            named: "edit-profile-name-editor",
            height: 420
        )
        #expect(try await recognizedText(in: name).lowercased().contains("maya"))

        let birthday = try await snapshot(
            NavigationStack {
                ProfileBirthdayEditorView(birthday: ProfileBirthday(rawValue: "1994-03-14"))
                    .environment(authentication)
            },
            named: "edit-profile-birthday-editor",
            height: 560
        )
        let birthdayText = try await recognizedText(in: birthday).lowercased()
        #expect(birthdayText.contains("march") || birthdayText.contains("1994"))

        let gender = try await snapshot(
            NavigationStack {
                ProfileGenderEditorView(gender: .woman)
                    .environment(authentication)
            },
            named: "edit-profile-gender-editor",
            height: 520
        )
        let genderText = try await recognizedText(in: gender).lowercased()
        #expect(genderText.contains("woman"))
        #expect(genderText.contains("prefer not to say"))

        let location = try await snapshot(
            NavigationStack {
                ProfileLocationEditorView(city: "Boulder", region: "CO", countryCode: "US")
                    .environment(authentication)
            },
            named: "edit-profile-location-editor",
            height: 520
        )
        #expect(try await recognizedText(in: location).lowercased().contains("boulder"))
    }

    // MARK: - Helpers

    private func signedOutAuthentication(displayName: String) -> AuthenticationViewModel {
        // The cached name is what the header reads before a session restores, so
        // seeding it renders the header the way a returning climber sees it.
        UserDefaults.standard.set(displayName, forKey: "displayName")
        return AuthenticationViewModel(observesFirebaseAuth: false)
    }

    private func expectInOrder(_ needles: [String], in haystack: String) throws {
        var searchStart = haystack.startIndex
        for needle in needles {
            let range = try #require(
                haystack.range(of: needle, range: searchStart..<haystack.endIndex),
                "\(needle) never appeared on screen, or appeared out of order"
            )
            searchStart = range.upperBound
        }
    }

    @discardableResult
    private func snapshot(
        _ view: some View,
        named name: String,
        height: CGFloat
    ) async throws -> UIImage {
        let size = CGSize(width: 390, height: height)
        let controller = UIHostingController(
            rootView: view
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
        )
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.backgroundColor = .black

        let window = UIWindow(frame: controller.view.frame)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        for _ in 0..<12 {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: "\(name).png")
        try png.write(to: url)

        #expect(png.count > 5_000)
        print("ASCEND_EVIDENCE_FILE: \(url.path())")
        return image
    }

    private func recognizedText(in image: UIImage) async throws -> String {
        let cgImage = try #require(image.cgImage, "UIImage had no CGImage")
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let observations = try await request.perform(on: cgImage)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
    }
}

/// The Edit Profile cards with a climber's answers in them, built from the same
/// `ProfileSection` / `ProfileCardSurface` / `ProfileValueRow` primitives
/// `EditProfileView` composes, in the same order.
private struct PopulatedEditProfileEvidence: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                ProfileSection(title: "Profile") {
                    ProfileCardSurface {
                        VStack(spacing: 0) {
                            row(icon: .settingsEditProfile, title: "First name", value: "Maya")
                            ProfileCardDivider(leadingInset: 60)
                            row(icon: .settingsEditProfile, title: "Last name", value: "Chen")
                        }
                    }
                }

                ProfileSection(title: "Personal Information") {
                    ProfileCardSurface {
                        VStack(spacing: 0) {
                            row(icon: .profileBirthday, title: "Birthday", value: formattedBirthday)
                            ProfileCardDivider(leadingInset: 60)
                            row(icon: .profileGender, title: "Gender", value: ProfileGender.woman.displayName)
                            ProfileCardDivider(leadingInset: 60)
                            row(icon: .settingsMeasurementSystem, title: "Height", value: formattedHeight)
                            ProfileCardDivider(leadingInset: 60)
                            row(icon: .profileWeight, title: "Weight", value: formattedWeight)
                        }
                    }
                }

                ProfileSection(title: "Location") {
                    ProfileCardSurface {
                        row(icon: .mapPin, title: "Location", value: "Boulder, CO")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .themedBackground()
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var formattedBirthday: String {
        guard let date = ProfileBirthday(rawValue: "1994-03-14")?.date() else { return "Not set" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var formattedHeight: String {
        MeasurementSystem.metric.formatHeightCentimeters(175)
    }

    private var formattedWeight: String {
        MeasurementSystem.metric.formatWeight(
            MeasurementSystem.metric.convertWeight(64, to: .metric)
        )
    }

    private func row(icon: AppIconToken, title: String, value: String) -> some View {
        ProfileValueRow(icon: icon, title: title, value: value, destination: EmptyView())
    }
}

private actor EvidenceEmailPreferencesService: EmailPreferencesProviding {
    private var storedConsent: LifecycleEmailConsent

    init(storedConsent: LifecycleEmailConsent) {
        self.storedConsent = storedConsent
    }

    func loadConsent() async throws -> LifecycleEmailConsent {
        storedConsent
    }

    func recordConsent(isGranted: Bool, source: LifecycleEmailConsentSource) async throws {
        storedConsent = LifecycleEmailConsent(isGranted: isGranted)
    }
}
