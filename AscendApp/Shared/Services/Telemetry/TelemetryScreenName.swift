import Foundation

/// The bounded catalog of surfaces Ascend reports through the one `screen_view` event.
///
/// A screen name is a stable analytics identifier, never a view title and never a value
/// derived from a Swift type at runtime. Both halves of the pair - the reported
/// `screen_name` and the reported `screen_class` - are written here as literals, so
/// renaming `LeaderboardView` is a reviewed decision rather than a silent split of a
/// Mixpanel series that has already accumulated history.
///
/// What earns a case: a root route, a tab root, a surface the climber navigates to, or a
/// modal they read or complete a task in. What does not: a reusable leaf component, a
/// picker or action menu that edits the surface behind it, a transient banner, and
/// DEBUG-only tooling. Adding a case without wiring it to a `trackOnce(screen:)` call site
/// fails `TelemetryScreenCatalogTests`.
///
/// The onboarding funnel is deliberately not measured screen-by-screen here. Its 21 steps
/// each emit `onboarding_screen_viewed` with a `screen_id` (see the `ascend-analytics`
/// skill); this catalog reports only the two route boundaries that contain them,
/// ``landing`` and ``onboardingFlow``. Entry-point detail is likewise left to the events
/// that already carry it - `live_climb_detail_view` and friends - rather than duplicated
/// onto the screen.
enum TelemetryScreenName: String, CaseIterable, Sendable {

    // MARK: - Root routes

    case appUpdateRequired = "app_update_required"
    case landing
    case authSigningIn = "auth_signing_in"
    case sessionRestoring = "session_restoring"
    case appAccessResolving = "app_access_resolving"
    case onboardingFlow = "onboarding_flow"
    case appAccessGate = "app_access_gate"
    case accountDataConflict = "account_data_conflict"

    // MARK: - Tabs

    case home
    case routines
    case leaderboard
    case profile

    // MARK: - Climbs

    case climbBrowse = "climb_browse"
    case climbDetail = "climb_detail"
    case climbFlyover = "climb_flyover"
    case liveClimbSession = "live_climb_session"
    case liveClimbSummary = "live_climb_summary"
    case climbBrowseHelp = "climb_browse_help"
    case compatibleHeadphonesHelp = "compatible_headphones_help"
    case climbsCollection = "climbs_collection"

    // MARK: - Home

    case homeStartAction = "home_start_action"
    case justClimbSetup = "just_climb_setup"
    case dailyWorkoutDetail = "daily_workout_detail"

    // MARK: - Climb results

    case workoutDetail = "workout_detail"
    case editWorkout = "edit_workout"
    case activeHeadphoneWorkoutRecovery = "active_headphone_workout_recovery"

    // MARK: - Progress

    case bestEfforts = "best_efforts"
    case bestEffortRecordDetail = "best_effort_record_detail"

    // MARK: - Routines

    case routineDetail = "routine_detail"
    case routineEditor = "routine_editor"
    case activeRoutine = "active_routine"

    // MARK: - Profile and moderation

    case otherUserProfile = "other_user_profile"
    case achievementHistory = "achievement_history"
    case reportProfile = "report_profile"
    case postBlockReport = "post_block_report"
    case blockedClimbers = "blocked_climbers"

    // MARK: - Account

    case settings
    case editProfile = "edit_profile"
    case profileNameEditor = "profile_name_editor"
    case profileBirthdayEditor = "profile_birthday_editor"
    case profileGenderEditor = "profile_gender_editor"
    case profileLocationEditor = "profile_location_editor"
    case bodyMetricsEditor = "body_metrics_editor"
    case notificationSettings = "notification_settings"
    case emailPreferences = "email_preferences"
    case measurementSystemSettings = "measurement_system_settings"
    case integrations
    case contactUs = "contact_us"
    case contactForm = "contact_form"
    case deleteAccountConfirmation = "delete_account_confirmation"
    case appleHealthManage = "apple_health_manage"
    case heartRateMonitorManage = "heart_rate_monitor_manage"

    // MARK: - Sharing

    case shareComposer = "share_composer"

    // MARK: - App updates

    case appUpdateNudge = "app_update_nudge"

    /// The `screen_class` reported beside the name. A literal, for the same reason the name
    /// is: `String(describing:)` would turn a refactor into a new analytics value.
    ///
    /// The two progress routes report `RootView` because that is the type that renders them;
    /// they have no view of their own to name.
    var screenClass: String {
        switch self {
        case .appUpdateRequired: "AppUpdateRequiredView"
        case .landing: "LandingScreen"
        case .authSigningIn: "RootView"
        case .sessionRestoring: "RootView"
        case .appAccessResolving: "AppAccessResolvingView"
        case .onboardingFlow: "PostAuthOnboardingFlowView"
        case .appAccessGate: "AppAccessPaywallPlaceholderView"
        case .accountDataConflict: "AccountDataConflictView"
        case .home: "HomeView"
        case .routines: "RoutinesView"
        case .leaderboard: "LeaderboardView"
        case .profile: "ProfileView"
        case .climbBrowse: "ClimbBrowseView"
        case .climbDetail: "ClimbDetailView"
        case .climbFlyover: "ClimbFlyoverScreen"
        case .liveClimbSession: "LiveClimbSessionView"
        case .liveClimbSummary: "LiveClimbCompletionSummaryView"
        case .climbBrowseHelp: "ClimbBrowseHelpSheet"
        case .compatibleHeadphonesHelp: "CompatibleHeadphonesHelpSheet"
        case .climbsCollection: "ClimbsCollectionView"
        case .homeStartAction: "HomeStartActionSheet"
        case .justClimbSetup: "JustClimbSetupSheet"
        case .dailyWorkoutDetail: "DailyWorkoutDetailView"
        case .workoutDetail: "WorkoutDetailView"
        case .editWorkout: "EditWorkoutView"
        case .activeHeadphoneWorkoutRecovery: "ActiveHeadphoneWorkoutRecoveryView"
        case .bestEfforts: "BestEffortsListView"
        case .bestEffortRecordDetail: "BestEffortRecordDetailView"
        case .routineDetail: "RoutineDetailView"
        case .routineEditor: "RoutineEditorView"
        case .activeRoutine: "ActiveRoutineView"
        case .otherUserProfile: "OtherUserProfileView"
        case .achievementHistory: "AchievementHistorySheet"
        case .reportProfile: "ReportProfileSheet"
        case .postBlockReport: "PostBlockReportSheet"
        case .blockedClimbers: "BlockedClimbersView"
        case .settings: "AccountView"
        case .editProfile: "EditProfileView"
        case .profileNameEditor: "ProfileNameEditorView"
        case .profileBirthdayEditor: "ProfileBirthdayEditorView"
        case .profileGenderEditor: "ProfileGenderEditorView"
        case .profileLocationEditor: "ProfileLocationEditorView"
        case .bodyMetricsEditor: "BodyMetricsEditorView"
        case .notificationSettings: "NotificationSettingsView"
        case .emailPreferences: "EmailPreferencesView"
        case .measurementSystemSettings: "MeasurementSystemSelectionView"
        case .integrations: "IntegrationsView"
        case .contactUs: "ContactUsView"
        case .contactForm: "ContactFormView"
        case .deleteAccountConfirmation: "DeleteAccountConfirmationView"
        case .appleHealthManage: "AppleHealthManageSheet"
        case .heartRateMonitorManage: "HeartRateMonitorManageSheet"
        case .shareComposer: "ShareComposerView"
        case .appUpdateNudge: "AppUpdateSheet"
        }
    }
}

extension TelemetryScreen {
    /// The only way a product surface should build a screen: from the reviewed catalog, so
    /// no call site can mint a name the analysis does not know about.
    init(_ name: TelemetryScreenName) {
        self.init(name: name.rawValue, screenClass: name.screenClass)
    }
}
