import Foundation
import Testing
@testable import AscendApp

/// The catalog is an analytics contract, not a list of view names, so the things that would
/// silently break a Mixpanel series are pinned here rather than left to review: the reported
/// values, the shape of those values, and the requirement that every declared screen is
/// actually wired to a call site.
struct TelemetryScreenCatalogTests {

    /// The shipped catalog, name for name and class for class.
    ///
    /// A renamed screen is a new event value in Mixpanel and orphans every saved report built
    /// on the old one, so it may not ride along with a Swift refactor. Changing this table is
    /// the deliberate act; the diff is the review.
    private static let pinnedCatalog: [String: String] = [
        "app_update_required": "AppUpdateRequiredView",
        "landing": "LandingScreen",
        "auth_signing_in": "RootView",
        "session_restoring": "RootView",
        "app_access_resolving": "AppAccessResolvingView",
        "onboarding_flow": "PostAuthOnboardingFlowView",
        "app_access_gate": "AppAccessPaywallPlaceholderView",
        "account_data_conflict": "AccountDataConflictView",
        "home": "HomeView",
        "routines": "RoutinesView",
        "leaderboard": "LeaderboardView",
        "profile": "ProfileView",
        "climb_browse": "ClimbBrowseView",
        "climb_detail": "ClimbDetailView",
        "climb_flyover": "ClimbFlyoverScreen",
        "live_climb_session": "LiveClimbSessionView",
        "live_climb_summary": "LiveClimbCompletionSummaryView",
        "climb_browse_help": "ClimbBrowseHelpSheet",
        "compatible_headphones_help": "CompatibleHeadphonesHelpSheet",
        "climbs_collection": "ClimbsCollectionView",
        "home_start_action": "HomeStartActionSheet",
        "just_climb_setup": "JustClimbSetupSheet",
        "daily_workout_detail": "DailyWorkoutDetailView",
        "workout_detail": "WorkoutDetailView",
        "edit_workout": "EditWorkoutView",
        "active_headphone_workout_recovery": "ActiveHeadphoneWorkoutRecoveryView",
        "best_efforts": "BestEffortsListView",
        "best_effort_record_detail": "BestEffortRecordDetailView",
        "routine_detail": "RoutineDetailView",
        "routine_editor": "RoutineEditorView",
        "active_routine": "ActiveRoutineView",
        "other_user_profile": "OtherUserProfileView",
        "achievement_history": "AchievementHistorySheet",
        "report_profile": "ReportProfileSheet",
        "post_block_report": "PostBlockReportSheet",
        "blocked_climbers": "BlockedClimbersView",
        "settings": "AccountView",
        "edit_profile": "EditProfileView",
        "profile_name_editor": "ProfileNameEditorView",
        "profile_birthday_editor": "ProfileBirthdayEditorView",
        "profile_gender_editor": "ProfileGenderEditorView",
        "profile_location_editor": "ProfileLocationEditorView",
        "body_metrics_editor": "BodyMetricsEditorView",
        "notification_settings": "NotificationSettingsView",
        "email_preferences": "EmailPreferencesView",
        "measurement_system_settings": "MeasurementSystemSelectionView",
        "integrations": "IntegrationsView",
        "contact_us": "ContactUsView",
        "contact_form": "ContactFormView",
        "delete_account_confirmation": "DeleteAccountConfirmationView",
        "apple_health_manage": "AppleHealthManageSheet",
        "heart_rate_monitor_manage": "HeartRateMonitorManageSheet",
        "share_composer": "ShareComposerView",
        "app_update_nudge": "AppUpdateSheet"
    ]

    @Test
    func theCatalogMatchesItsPinnedContract() {
        let shipped = Dictionary(
            uniqueKeysWithValues: TelemetryScreenName.allCases.map { ($0.rawValue, $0.screenClass) }
        )

        #expect(shipped == Self.pinnedCatalog)
    }

    @Test(arguments: TelemetryScreenName.allCases)
    func everyScreenNameIsALowerSnakeCaseIdentifier(screen: TelemetryScreenName) {
        #expect(
            screen.rawValue.range(of: #"^[a-z][a-z0-9]*(_[a-z0-9]+)*$"#, options: .regularExpression) != nil,
            "\(screen.rawValue) is not a lower_snake_case analytics identifier"
        )
    }

    @Test
    func screenNamesAreUnique() {
        #expect(Set(TelemetryScreenName.allCases.map(\.rawValue)).count == TelemetryScreenName.allCases.count)
    }

    @Test
    func buildingAScreenFromTheCatalogCarriesBothReportedValues() {
        let screen = TelemetryScreen(.climbDetail)

        #expect(screen.name == "climb_detail")
        #expect(screen.screenClass == "ClimbDetailView")
        #expect(screen.parameters.isEmpty)
    }

    /// The one event name, for every screen. One event per screen would make every funnel a
    /// per-screen rewrite and would put screen values in the event catalog itself.
    @Test
    func aCatalogScreenReachesTheSinkAsOneScreenViewCarryingNameAndClass() {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)

        telemetry.track(screen: TelemetryScreen(.leaderboard))

        #expect(sink.screens.count == 1)
        #expect(sink.screens.first?.name == "leaderboard")
        #expect(sink.screens.first?.screenClass == "LeaderboardView")
        #expect(sink.records.isEmpty)
    }

    /// A screen is a property of one event, not a sticky property of the user. Registering it
    /// as a super-property would stamp the last screen onto every later event and turn every
    /// unrelated funnel into a screen-conditioned one.
    @Test
    func trackingAScreenRegistersNoUserProperty() {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)

        for screen in TelemetryScreenName.allCases {
            telemetry.track(screen: TelemetryScreen(screen))
        }

        #expect(sink.screens.count == TelemetryScreenName.allCases.count)
        #expect(sink.userIDs.isEmpty)

        let superPropertyCallSites = Self.appSources
            .filter { $0.path.hasSuffix("View+TrackOnce.swift") || $0.path.hasSuffix("TrackOnceModifier.swift") }
            .map(Self.contents)
        #expect(superPropertyCallSites.isEmpty == false)
        #expect(superPropertyCallSites.allSatisfy { $0.contains("setUserProperty") == false })
    }

    // MARK: - Source contract

    /// Every declared screen has to be attached to something. A catalog entry with no call
    /// site is a name that will never arrive, which reads in Mixpanel as a surface nobody
    /// visits rather than as a surface nobody instrumented.
    @Test
    func everyCatalogScreenIsWiredToATrackingSite() throws {
        let trackedInViews = try Self.screensPassedToTrackOnce()
        let mappedFromRoutes = try Self.screensNamedInRouteMappings()
        let wired = trackedInViews.union(mappedFromRoutes)

        let orphans = Set(TelemetryScreenName.allCases.map(\.caseName)).subtracting(wired)
        #expect(orphans.isEmpty, "Catalog screens with no trackOnce call site: \(orphans.sorted())")
    }

    /// One mechanism, one vocabulary. A product surface that builds its own `TelemetryScreen`
    /// can name it anything, which is exactly the drift the bounded catalog exists to stop.
    @Test
    func noProductSurfaceBuildsAnAdHocScreen() throws {
        let offenders = Self.appSources
            .filter { $0.path.contains("/Shared/Services/Telemetry/") == false }
            .filter { Self.contents($0).contains("TelemetryScreen(name:") }
            .map { $0.lastPathComponent }

        #expect(offenders.isEmpty, "Screens must come from TelemetryScreenName: \(offenders.sorted())")
    }

    /// A `screen_class` that names a type the app no longer has is a stale label nobody can
    /// trace back to a surface.
    @Test
    func everyScreenClassNamesATypeTheAppStillDeclares() throws {
        let declarations = Self.appSources
            .map(Self.contents)
            .joined(separator: "\n")

        for screen in TelemetryScreenName.allCases {
            let declared = declarations.range(
                of: #"struct \#(screen.screenClass)\b"#,
                options: .regularExpression
            ) != nil
            #expect(declared, "\(screen.screenClass) is not declared in the app target")
        }
    }

    // MARK: - Source access

    private static func screensPassedToTrackOnce() throws -> Set<String> {
        var found: Set<String> = []
        let pattern = try NSRegularExpression(pattern: #"trackOnce\(screen: \.([A-Za-z0-9]+)\)"#)

        for source in appSources {
            let text = contents(source)
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                guard let caseRange = Range(match.range(at: 1), in: text) else { continue }
                found.insert(String(text[caseRange]))
            }
        }

        return found
    }

    /// The tab and root-route maps name their screens instead of spelling them at the call
    /// site, which is what makes an uninstrumented route a compile error there.
    private static func screensNamedInRouteMappings() throws -> Set<String> {
        var found: Set<String> = []
        let pattern = try NSRegularExpression(pattern: #":\s*\.([A-Za-z0-9]+)$"#, options: .anchorsMatchLines)
        let mappings = appSources.filter {
            $0.lastPathComponent.hasSuffix("+TelemetryScreenName.swift")
        }
        precondition(mappings.isEmpty == false, "The route mapping files moved or were renamed")

        for source in mappings {
            let text = contents(source)
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                guard let caseRange = Range(match.range(at: 1), in: text) else { continue }
                found.insert(String(text[caseRange]))
            }
        }

        return found
    }

    private static let appSources: [URL] = {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "AscendApp")

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
    }()

    private static func contents(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}

private extension TelemetryScreenName {
    /// The Swift case name, which is what a `trackOnce(screen: .x)` call site spells.
    var caseName: String {
        String(describing: self)
    }
}
