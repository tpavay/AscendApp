import Foundation
import Testing

struct SettingsReorganizationContractTests {
    @Test
    func settingsOwnsPreferencesAndKeepsPrivacyAtTheBottomOfTheCustomerSections() throws {
        let source = try source(at: "AscendApp/Features/Account/Views/AccountView.swift")
        let orderedSections = [
            "sectionView(title: \"Profile\"",
            "sectionView(title: \"Notifications\"",
            "sectionView(title: \"Preferences\"",
            "sectionView(title: \"Subscription\"",
            "sectionView(title: \"Support\"",
            "sectionView(title: \"Privacy\""
        ]

        var previousIndex = source.startIndex
        for section in orderedSections {
            let range = try #require(source.range(of: section, range: previousIndex..<source.endIndex))
            previousIndex = range.upperBound
        }

        #expect(source.contains("title: \"Push\""))
        #expect(source.contains("title: \"Email\""))
        #expect(source.contains("destination: EmailPreferencesView()"))
        #expect(source.contains("title: \"Units\""))
        #expect(source.contains("title: \"Integrations\""))
        #expect(source.contains("title: \"Blocked climbers\""))
    }

    @Test
    func settingsEmailRouteUsesTheMergedEmailPreferencesContent() throws {
        let screen = try source(
            at: "AscendApp/Features/Account/Views/EmailPreferencesView.swift"
        )

        #expect(screen.contains("EmailPreferencesContentView(viewModel: viewModel)"))
        #expect(screen.contains("await viewModel.load()"))
        #expect(screen.contains(".navigationTitle(\"Email\")"))
    }

    @Test
    func settingsRowsUseDisclosureOnlyWithoutPreferenceSummaries() throws {
        let source = try source(at: "AscendApp/Features/Account/Views/Components/SettingsRow.swift")

        #expect(source.contains(".disclosureChevronRight"))
        #expect(!source.contains("option.value"))
        #expect(!source.contains("On/Off"))
    }

    @Test
    func editProfileHasExactlyTheSettledGroupedFields() throws {
        let source = try source(at: "AscendApp/Features/Account/Views/EditProfileView.swift")
        let requiredTitles = [
            "First name",
            "Last name",
            "Birthday",
            "Gender",
            "Height",
            "Weight",
            "Location"
        ]

        for title in requiredTitles {
            #expect(source.contains("title: \"\(title)\""), "Missing \(title) drill-in row")
        }

        #expect(source.contains("ProfileSection(title: \"Profile\")"))
        #expect(source.contains("ProfileSection(title: \"Personal Information\")"))
        #expect(source.contains("ProfileSection(title: \"Location\")"))
        #expect(!source.localizedCaseInsensitiveContains("bio"))
        #expect(!source.localizedCaseInsensitiveContains("primary sport"))
        #expect(!source.contains("footer"))
        #expect(!source.contains("MeasurementSystemSelectionView"))
        #expect(!source.contains("IntegrationsView"))
    }

    @Test
    func everyEditProfileValueRowIsAnAccessibleDrillIn() throws {
        let source = try source(
            at: "AscendApp/Features/Account/Views/Components/ProfileValueRow.swift"
        )

        #expect(source.contains("NavigationLink(destination: destination)"))
        #expect(source.contains(".accessibilityLabel(title)"))
        #expect(source.contains(".accessibilityValue(value)"))
        #expect(source.contains(".frame(minHeight: 44)"))
    }

    @Test
    func pushSettingsContainsOnlyTheExistingPushPreference() throws {
        let source = try source(
            at: "AscendApp/Features/Account/Views/NotificationSettingsView.swift"
        )

        #expect(source.contains(".navigationTitle(\"Push\")"))
        #expect(source.contains("Text(\"New climb drops\")"))
        #expect(source.contains("Text(\"iOS permission\")"))
        #expect(!source.localizedCaseInsensitiveContains("ascend emails"))
        #expect(!source.localizedCaseInsensitiveContains("email notifications"))
    }

    @Test
    func onboardingCollectsABirthdayWithoutRenamingTheExistingFunnelStage() throws {
        let flow = try source(
            at: "AscendApp/Features/Onboarding/Views/PostAuthOnboardingFlowView.swift"
        )
        let stage = try source(
            at: "AscendApp/Features/Onboarding/Models/PostAuthOnboardingStage.swift"
        )

        #expect(flow.contains("private struct PostAuthBirthdayScreen"))
        #expect(flow.contains("headline: \"When were you born?\""))
        #expect(flow.contains("DatePicker("))
        // `pickerStyle` configures `Picker`, not `DatePicker`: applying it here
        // silently leaves the compact field inside chrome sized for a wheel.
        #expect(flow.contains(".datePickerStyle(.wheel)"))
        #expect(flow.contains("updateOnboardingBirthday"))
        #expect(!flow.contains("PostAuthAgeWheelPicker"))
        #expect(stage.contains("case age"))
        #expect(stage.contains("case .age:\n            return \"date\""))
    }

    @Test
    func reorganizedViewsAddNoAnimationOrTransition() throws {
        let paths = [
            "AscendApp/Features/Account/Views/AccountView.swift",
            "AscendApp/Features/Account/Views/EditProfileView.swift",
            "AscendApp/Features/Account/Views/NotificationSettingsView.swift",
            "AscendApp/Features/Account/Views/ProfileBirthdayEditorView.swift",
            "AscendApp/Features/Account/Views/ProfileGenderEditorView.swift",
            "AscendApp/Features/Account/Views/ProfileLocationEditorView.swift",
            "AscendApp/Features/Account/Views/ProfileNameEditorView.swift",
            "AscendApp/Features/Account/Views/Components/ProfileValueRow.swift"
        ]

        for path in paths {
            let source = try source(at: path)
            #expect(!source.contains("withAnimation"), "Unexpected animation in \(path)")
            #expect(!source.contains(".animation("), "Unexpected animation in \(path)")
            #expect(!source.contains(".transition("), "Unexpected transition in \(path)")
            #expect(!source.contains("contentTransition"), "Unexpected transition in \(path)")
        }
    }

    private var projectRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(at relativePath: String) throws -> String {
        try String(
            contentsOf: projectRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }
}
