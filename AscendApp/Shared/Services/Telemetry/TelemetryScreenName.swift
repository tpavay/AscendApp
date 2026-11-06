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
/// The onboarding funnel is measured by `onboarding_screen_viewed` with a `screen_id`
/// (see the `ascend-analytics` skill), which is what funnels read. The v3 flow's screens are also
/// catalog screens, so `screen_view` carries them beside every other surface; the older flow
/// reports only the two route boundaries that contain its 21 steps, ``landing`` and
/// ``onboardingFlow``. Entry-point detail is likewise left to the events
/// that already carry it - `live_climb_detail_view` and friends - rather than duplicated
/// onto the screen.
enum TelemetryScreenName: String, CaseIterable, Sendable {

    // MARK: - Root routes

    case appUpdateRequired = "app_update_required"
    case landing
    case signedOutHold = "signed_out_hold"
    case authSigningIn = "auth_signing_in"
    case sessionRestoring = "session_restoring"
    case appAccessResolving = "app_access_resolving"
    case onboardingFlow = "onboarding_flow"
    case appAccessGate = "app_access_gate"
    case accountDataConflict = "account_data_conflict"

    // MARK: - Onboarding v3

    case onboardingWelcome = "onboarding_welcome"
    case onboardingGoHarder = "onboarding_go_harder"
    case onboardingGetBetter = "onboarding_get_better"
    case onboardingSomethingToChase = "onboarding_something_to_chase"
    case onboardingCountMethods = "onboarding_count_methods"
    case onboardingHealthConnect = "onboarding_health_connect"
    case onboardingHealthPermission = "onboarding_health_permission"
    case onboardingHealthHistory = "onboarding_health_history"
    case onboardingUsualClimb = "onboarding_usual_climb"
    case onboardingClimberCard = "onboarding_climber_card"
    case onboardingClaimCity = "onboarding_claim_city"
    case onboardingWeeklyTarget = "onboarding_weekly_target"
    case onboardingThisMonthEvent = "onboarding_this_month_event"
    case onboardingNotificationPrimer = "onboarding_notification_primer"
    case onboardingPaywall = "onboarding_paywall"
    case onboardingExitGift = "onboarding_exit_gift"
    case onboardingAuth = "onboarding_auth"
    case healthConnectLater = "health_connect_later"

    // MARK: - Tabs

    case home
    case routines
    case leaderboard
    case profile

    // MARK: - Champions

    case pastChampions = "past_champions"
    case periodRecap = "period_recap"

    // MARK: - Climbs

    case climbBrowse = "climb_browse"
    case climbDetail = "climb_detail"
    case climbFlyover = "climb_flyover"
    case liveClimbSession = "live_climb_session"
    case liveClimbSummary = "live_climb_summary"
    case climbBrowseHelp = "climb_browse_help"
    case compatibleHeadphonesHelp = "compatible_headphones_help"
    case mountainRace = "mountain_race"
    case mountainRaceFilter = "mountain_race_filter"
    case climbsCollection = "climbs_collection"

    // MARK: - Home

    case homeSheetExpanded = "home_sheet_expanded"
    case homeTodayActivityList = "home_today_activity_list"
    case homeClimbCard = "home_climb_card"
    case homeStartAction = "home_start_action"
    case justClimbSetup = "just_climb_setup"
    case dailyWorkoutDetail = "daily_workout_detail"

    // MARK: - Climb results

    case workoutDetail = "workout_detail"
    case editWorkout = "edit_workout"
    case logClimb = "log_climb"
    case loggedClimbResult = "logged_climb_result"
    case activeHeadphoneWorkoutRecovery = "active_headphone_workout_recovery"
    case headphoneSessionResume = "headphone_session_resume"
    case stepAccuracyCalibration = "step_accuracy_calibration"

    // MARK: - Progress

    case bestEfforts = "best_efforts"
    case bestEffortRecordDetail = "best_effort_record_detail"

    // MARK: - Routines

    case routineDetail = "routine_detail"
    case routineEditor = "routine_editor"
    case activeRoutine = "active_routine"

    // MARK: - Profile and moderation

    case otherUserProfile = "other_user_profile"
    case athleteEditor = "athlete_editor"
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
    case heartRateVisibility = "heart_rate_visibility"
    case measurementSystemSettings = "measurement_system_settings"
    case unlockEventIntro = "unlock_event_intro"
    case unlockEvent = "unlock_event"
    case unlockItem = "unlock_item"
    case integrations
    case contactUs = "contact_us"
    case contactForm = "contact_form"
    case deleteAccountConfirmation = "delete_account_confirmation"
    case appleHealthManage = "apple_health_manage"
    case appleHealthConnect = "apple_health_connect"
    case appleHealthImportChoice = "apple_health_import_choice"
    case appleHealthImports = "apple_health_imports"
    case importedClimbQuickEdit = "imported_climb_quick_edit"
    case heartRateMonitorManage = "heart_rate_monitor_manage"
    case stravaManage = "strava_manage"

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
        case .signedOutHold: "SignedOutHoldView"
        case .authSigningIn: "RootView"
        case .sessionRestoring: "RootView"
        case .appAccessResolving: "AppAccessResolvingView"
        case .onboardingFlow: "PostAuthOnboardingFlowView"
        case .appAccessGate: "AppAccessPaywallPlaceholderView"
        case .accountDataConflict: "AccountDataConflictView"
        case .onboardingWelcome: "OnboardingWelcomeScreen"
        case .onboardingGoHarder: "OnboardingGoHarderScreen"
        case .onboardingGetBetter: "OnboardingGetBetterScreen"
        case .onboardingSomethingToChase: "OnboardingSomethingToChaseScreen"
        case .onboardingCountMethods: "OnboardingCountMethodsScreen"
        case .onboardingHealthConnect: "OnboardingHealthConnectScreen"
        case .onboardingHealthPermission: "OnboardingHealthPermissionScreen"
        case .onboardingHealthHistory: "OnboardingHealthHistoryScreen"
        case .onboardingUsualClimb: "OnboardingUsualClimbScreen"
        case .onboardingClimberCard: "OnboardingClimberCardScreen"
        case .onboardingClaimCity: "OnboardingClaimCityScreen"
        case .onboardingWeeklyTarget: "OnboardingWeeklyTargetScreen"
        case .onboardingThisMonthEvent: "OnboardingThisMonthEventScreen"
        case .onboardingNotificationPrimer: "OnboardingNotificationPrimerScreen"
        case .onboardingPaywall: "OnboardingPaywallScreen"
        case .onboardingExitGift: "OnboardingExitGiftScreen"
        case .onboardingAuth: "OnboardingAuthScreen"
        case .healthConnectLater: "OnboardingHealthConnectScreen"
        case .home: "HomeView"
        case .routines: "RoutinesView"
        case .leaderboard: "LeaderboardView"
        case .profile: "ProfileView"
        case .pastChampions: "PastChampionsView"
        case .periodRecap: "PeriodRecapView"
        case .climbBrowse: "ClimbBrowseView"
        case .climbDetail: "ClimbDetailView"
        case .climbFlyover: "ClimbFlyoverScreen"
        case .liveClimbSession: "LiveClimbSessionView"
        case .liveClimbSummary: "LiveClimbCompletionSummaryView"
        case .climbBrowseHelp: "ClimbBrowseHelpSheet"
        case .compatibleHeadphonesHelp: "CompatibleHeadphonesHelpSheet"
        case .mountainRace: "AscendMountainRaceSheet"
        case .mountainRaceFilter: "AscendMountainFilterSheet"
        case .climbsCollection: "ClimbsCollectionView"
        case .homeSheetExpanded: "HomeView"
        case .homeTodayActivityList: "HomeTodayActivityListView"
        case .homeClimbCard: "ClimbPreviewCardView"
        case .homeStartAction: "HomeStartActionSheet"
        case .justClimbSetup: "JustClimbSetupSheet"
        case .dailyWorkoutDetail: "DailyWorkoutDetailView"
        case .workoutDetail: "WorkoutDetailView"
        case .editWorkout: "EditWorkoutView"
        case .logClimb: "LogClimbView"
        case .loggedClimbResult: "LoggedClimbResultView"
        case .activeHeadphoneWorkoutRecovery: "ActiveHeadphoneWorkoutRecoveryView"
        case .headphoneSessionResume: "HeadphoneSessionResumeSheet"
        case .stepAccuracyCalibration: "StepAccuracyCalibrationPromptView"
        case .bestEfforts: "BestEffortsListView"
        case .bestEffortRecordDetail: "BestEffortRecordDetailView"
        case .routineDetail: "RoutineDetailView"
        case .routineEditor: "RoutineEditorView"
        case .activeRoutine: "ActiveRoutineView"
        case .otherUserProfile: "OtherUserProfileView"
        case .athleteEditor: "AthleteEditorView"
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
        case .heartRateVisibility: "HeartRateVisibilityView"
        case .measurementSystemSettings: "MeasurementSystemSelectionView"
        case .unlockEventIntro: "UnlockEventIntroView"
        case .unlockEvent: "UnlockEventPage"
        case .unlockItem: "UnlockItemView"
        case .integrations: "IntegrationsView"
        case .contactUs: "ContactUsView"
        case .contactForm: "ContactFormView"
        case .deleteAccountConfirmation: "DeleteAccountConfirmationView"
        case .appleHealthManage: "AppleHealthManageSheet"
        case .appleHealthConnect: "AppleHealthConnectView"
        case .appleHealthImportChoice: "AppleHealthImportChoiceView"
        case .appleHealthImports: "AppleHealthImportsView"
        case .importedClimbQuickEdit: "ImportedClimbQuickEditSheet"
        case .heartRateMonitorManage: "HeartRateMonitorManageSheet"
        case .stravaManage: "StravaManageSheet"
        case .shareComposer: "ShareSheetView"
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
