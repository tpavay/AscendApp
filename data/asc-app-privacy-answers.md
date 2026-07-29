# Ascend App Privacy Answers

Last audited: July 28, 2026.
Branch: `fm/ascend-app-review-privacy-compliance`.

This file is deliberately untracked.
It is the captain's working artifact for the App Store Connect App Privacy questionnaire and is not part of the committed repository.

---

## 1. Policy change (put this first in the PR body)

`web/src/pages/privacy.astro`, Analytics section, second paragraph.

**Before** (base commit `b898ca3`):

> When you are signed in, Ascend sends your Ascend account user ID to Firebase Analytics, Mixpanel, Firebase Crashlytics, and Sentry so product usage and diagnostic events can be associated with your account.
> Firebase Analytics also collects an app-specific device identifier for analytics.
> Ascend sends the same account user ID to RevenueCat and Superwall so they can link subscription status and purchase history to your account across sessions and devices.

**After**:

> When you are signed in, Ascend sends your Ascend account user ID to Firebase Analytics, Mixpanel, Firebase Crashlytics, and Sentry so product usage and diagnostic events can be associated with your account.
> Firebase Analytics and Mixpanel collect app-specific device identifiers for analytics.
> Ascend sends the same account user ID to RevenueCat and Superwall so they can link subscription status and purchase history to your account across sessions and devices.
> Superwall also collects an app-specific vendor identifier for paywall analytics.
> Ascend also attaches profile demographics to Firebase Analytics and Mixpanel as account-level user properties: your gender or division (profile_gender), your age group (profile_age_group), your body-weight group (profile_weight_group), and your country (profile_country).
> Your onboarding fitness answers - stair-stepper experience (stair_stepper_exp), exercise level (exercise_level), motivation (motivation), planned weekly frequency (planned_frequency), and your selected goals (goal_*) - are attached as user properties as well.
> Your body-height group (profile_height_group) is sent to the same two providers as a parameter on the onboarding analytics event that records your body metrics, and the age-group and body-weight bands you choose as leaderboard filters (age_group, body_weight_filter) are sent as parameters on leaderboard filter events.

The only other policy edits on this branch are the last-updated date and broadening one sentence to name Mixpanel and Superwall device identifiers.
The HealthKit-synchronization paragraph and the identity-linkage sentence already existed at `b898ca3`; this branch did not introduce them.
No unrelated policy section was reworded.

**Demonstrated call sites**

| Disclosed item | Call site |
|---|---|
| `profile_gender` | `OnboardingAnalyticsUserProperties.swift:29` |
| `profile_age_group` | `OnboardingAnalyticsUserProperties.swift:33` |
| `profile_weight_group` | `OnboardingAnalyticsUserProperties.swift:37` |
| `profile_country` | `OnboardingAnalyticsUserProperties.swift:100` |
| `stair_stepper_exp`, `exercise_level`, `motivation`, `planned_frequency` | `OnboardingAnalyticsUserProperties.swift:14,16,20,22` |
| `goal_*` | `OnboardingAnalyticsUserProperties.swift:119-129` |
| `profile_height_group` | `PostAuthOnboardingFlowView.swift:545` |
| `age_group`, `body_weight_filter` | `LeaderboardAnalyticsEvent.swift:78-79` |

All user properties route through `OnboardingAnalyticsUserProperties.set` to `TelemetryManager.setUserProperty`, which fans out to `FirebaseTelemetrySink.setUserProperty` (`Analytics.setUserProperty`) and `MixpanelTelemetrySink.setUserProperty` (`people.set` plus `registerSuperProperties`).
Event parameters route through `TelemetryManager.track` to `FirebaseTelemetrySink.record` (`Analytics.logEvent`) and `MixpanelTelemetrySink.record` (`instance.track`).

**Hold note.** Firstmate holds this PR for the captain's own review of the policy wording before merge, even after CI is green.

---

## 2. Complete analytics inventory

Method: every `setUserProperty` call site in the app target, every `TelemetryEvent` conformer, every inline `TelemetryRecord` construction, and the two analytics sinks were read.
Mixpanel receives everything after `identify(distinctId:usePeople:)`, and Firebase Analytics after `setUserID`, so **every row below is linked to identity**.

### 2a. User properties

All 28 are set through `TelemetryManager.setUserProperty` and reach both Firebase Analytics and Mixpanel.

| Property | Call site | Apple classification | Linked | Note |
|---|---|---|---|---|
| `profile_weight_group` | `OnboardingAnalyticsUserProperties.swift:37` | Health | Yes | Banded body weight |
| `profile_gender` | `OnboardingAnalyticsUserProperties.swift:29` | Other Data Types | Yes | Demographic |
| `profile_age_group` | `OnboardingAnalyticsUserProperties.swift:33` | Other Data Types | Yes | Demographic |
| `profile_country` | `OnboardingAnalyticsUserProperties.swift:100` | Coarse Location | Yes | ISO country code |
| `stair_stepper_exp` | `OnboardingAnalyticsUserProperties.swift:14` | Fitness | Yes | Stair-stepper experience |
| `exercise_level` | `OnboardingAnalyticsUserProperties.swift:16` | Fitness | Yes | Exercise baseline |
| `motivation` | `OnboardingAnalyticsUserProperties.swift:20` | Fitness | Yes | Fitness motivation |
| `planned_frequency` | `OnboardingAnalyticsUserProperties.swift:22` | Fitness | Yes | Planned weekly frequency |
| `goal_lose_weight` | `OnboardingAnalyticsUserProperties.swift:120` | Fitness | Yes | Named via `knownGoalProperties` |
| `goal_build_endurance` | `OnboardingAnalyticsUserProperties.swift:121` | Fitness | Yes | Named via `knownGoalProperties` |
| `goal_track_progress` | `OnboardingAnalyticsUserProperties.swift:122` | Fitness | Yes | Named via `knownGoalProperties` |
| `goal_exciting_workouts` | `OnboardingAnalyticsUserProperties.swift:123` | Fitness | Yes | Named via `knownGoalProperties` |
| `goal_healthier_life` | `OnboardingAnalyticsUserProperties.swift:124` | Fitness | Yes | Named via `knownGoalProperties` |
| `goal_answer_count` | `OnboardingAnalyticsUserProperties.swift:131` | Fitness | Yes | Count of fitness goals chosen |
| `notifications_choice` | `OnboardingAnalyticsUserProperties.swift:105` | Other Data Types | Yes | Notification preference |
| `first_climb_id` | `OnboardingAnalyticsUserProperties.swift:109` | Other Data Types | Yes | Onboarding preference used for personalization |
| `first_climb_tier` | `OnboardingAnalyticsUserProperties.swift:110` | Other Data Types | Yes | Onboarding preference used for personalization |
| `first_climb_steps` | `OnboardingAnalyticsUserProperties.swift:111` | Other Data Types | Yes | Banded climb size |
| `display_name_set` | `OnboardingAnalyticsUserProperties.swift:5` | Product Interaction | Yes | Usage flag, see reason below |
| `profile_location_set` | `OnboardingAnalyticsUserProperties.swift:101` | Product Interaction | Yes | Usage flag |
| `onboarding_complete` | `OnboardingAnalyticsUserProperties.swift:115` | Product Interaction | Yes | Usage flag |
| `name_inputted` | `PostAuthOnboardingFlowView.swift:295` | Product Interaction | Yes | Usage flag |
| `division_inputted` | `PostAuthOnboardingFlowView.swift:376` | Product Interaction | Yes | Usage flag |
| `age_inputted` | `PostAuthOnboardingFlowView.swift:440` | Product Interaction | Yes | Usage flag |
| `body_metrics_inputted` | `PostAuthOnboardingFlowView.swift:539` | Product Interaction | Yes | Usage flag |
| `location_inputted` | `PostAuthOnboardingFlowView.swift:690` | Product Interaction | Yes | Usage flag |
| `notifications_inputted` | `PostAuthOnboardingFlowView.swift:827,848` | Product Interaction | Yes | Usage flag |
| `first_climb_selected` | `PostAuthOnboardingFlowView.swift:1440` | Product Interaction | Yes | Usage flag |

**Documented reason for the ten Product Interaction rows.**
Each of these is written with the literal value `"true"` and records only that the user completed an onboarding step.
None carries the value the user entered; the attribute values themselves are declared separately under Health, Fitness, Other Data Types, and Coarse Location.
That makes them genuine usage flags rather than personal attributes, which is why Usage Data is the correct category.

### 2b. Event parameters carrying body or demographic values

| Parameter | Event | Call site | Apple classification | Linked |
|---|---|---|---|---|
| `profile_height_group` | `onboarding_screen_completed` | `PostAuthOnboardingFlowView.swift:545` | Health | Yes |
| `profile_weight_group` | `onboarding_screen_completed` | `PostAuthOnboardingFlowView.swift:548` | Health | Yes |
| `body_weight_filter` | `leaderboard_filter_changed`, `leaderboard_filters_cleared` | `LeaderboardAnalyticsEvent.swift:79` | Health | Yes |
| `age_group` | `leaderboard_filter_changed`, `leaderboard_filters_cleared` | `LeaderboardAnalyticsEvent.swift:78` | Other Data Types | Yes |
| `selected_value` | `leaderboard_filter_changed` | `LeaderboardAnalyticsEvent.swift:45` | Health when `filter_type` is `body_weight`, Other Data Types when `age_group`, Coarse Location when `location` | Yes |

`age_group` and `body_weight_filter` carry the band the user selected as a leaderboard filter rather than a measured attribute.
They are classified conservatively as demographic and body data because a signed-in user filtering the leaderboard usually selects their own band.

### 2c. All remaining analytics events and parameters

Every one below resolves to **Product Interaction** (Usage Data) or **Purchase History**, both already declared with Analytics and linked, and none carries a body, demographic, or free-text personal value.

| Source | Events | Parameters |
|---|---|---|
| `OnboardingAnalyticsEvent.swift` | `onboarding_flow_started`, `onboarding_flow_completed`, `onboarding_screen_viewed`, `onboarding_screen_completed`, `onboarding_question_answered`, `onboarding_back_tapped`, `onboarding_auth_started`, `onboarding_auth_completed`, `onboarding_auth_failed`, `onboarding_paywall_reached` | `flow_id`, `flow_version`, `screen_id`, `step_id`, `step_index`, `step_count`, `input_type`, `question_id`, `answer_id`, `answer_index`, `selection_type`, `has_answer`, `from_step`, `provider`, `status`, `reason`, `placement`, `source`, `completed`, `climb_id`, `climb_name` |
| `LiveClimbAnalyticsEvent.swift` | `live_climb_attempt_started`, `live_climb_attempt_completed`, `live_climb_attempt_saved`, `live_climb_attempt_discarded`, `live_climb_browse_open`, `live_climb_browse_climb_open`, `live_climb_browse_preview_show`, `live_climb_browse_help_open`, `live_climb_detail_view`, `live_climb_detail_start_tap`, `live_climb_detail_browse_tap`, `live_climb_home_daily_tap`, `live_climb_home_explore_tap`, `live_climb_headphone_help_open`, `live_climb_share_action_tap`, `live_climb_share_activity_done`, `live_climb_start_blocked`, `live_climb_summary_view`, `live_climb_summary_done_tap`, `live_climb_summary_share_tap` | `climb_id`, `climb_tier`, `climb_category`, `climb_steps_bucket`, `steps_bucket`, `duration_bucket`, `progress_bucket`, `rank_bucket`, `rank_total_bucket`, `total_climbs_bucket`, `outcome`, `entry_point`, `surface`, `share_surface`, `card_type`, `session_gate`, `action_state`, `blocked_reason`, `can_start`, `home_state`, `copy_text`, `completed`, `new_attempt` |
| `LeaderboardAnalyticsEvent.swift` | `leaderboard_filter_changed`, `leaderboard_filters_cleared` | `metric`, `time_frame`, `location_filter`, `active_filter_count`, `filter_group`, `filter_type`, `has_active_filters` (plus the demographic parameters in 2b) |
| `PaywallAnalyticsEvent.swift` | `paywall_shown`, `paywall_dismissed`, `paywall_transaction_started`, `paywall_transaction_completed`, `paywall_transaction_failed`, `paywall_transaction_abandoned`, `paywall_restore_completed`, `revenuecat_purchase_completed`, `revenuecat_restore_completed` | `paywall_identifier`, `paywall_name`, `placement`, `presentation_id`, `presentation_source_type`, `presented_by`, `product_id`, `primary_product_id`, `transaction_type`, `restore_type`, `outcome`, `dismiss_reason`, `error_type`, `is_free_trial_available` (Purchase History) |
| `WorkoutImportAnalyticsEvent.swift` | `workout_import_started`, `workout_import_finished` | `import_mode`, `source_mix`, `outcome`, `candidate_count_bucket`, `imported_count_bucket`, `updated_count_bucket`, `failed_count_bucket`, `updated_existing`. No HealthKit measurement value is emitted, only counts and source mix. |
| `WorkoutSessionAnalyticsEvent.swift` | `just_climb_started`, `just_climb_saved`, `just_climb_discarded`, `routine_started`, `routine_completed`, `routine_saved`, `routine_discarded`, `routine_log_tapped` | `session_type`, `entry_point`, `surface`, `routine_id`, `template_id`, `routine_source`, `goal_kind`, `steps_bucket`, `duration_bucket`, `progress_bucket`, `difficulty_bucket`, `interval_count_bucket`, `target_steps_bucket`, `target_duration_bucket`, `correction_count_bucket`, `tracking_unavailable_bucket`, `had_step_corrections`, `has_default_weights`, `stop_reason` (Fitness for the workout metrics, Product Interaction for the rest) |
| `SuperwallPaywallPresenter.swift:81,95` | `paywall_skipped`, `paywall_error` | `placement`, `reason`, `error` (SDK error descriptions, Other Diagnostic Data) |
| `MonetizationManager.swift:147` | `paywall_reached` | `placement`, `source` |
| `RevenueCatEntitlementService.swift:98` | `monetization_offering_mismatch` | offering audit parameters; destinations `[.analytics, .crashlytics]` |
| `TelemetryManager.swift:202` | all analytics records | `app_environment` is appended to every record and screen |
| `AnalyticsScreenModifier.swift` / `TelemetryScreen` | `screen_view` | `screen_name`, `screen_class`, plus per-screen parameters |
| `AppDiagnosticsRecorder.swift:150` | `diagnostic:*` | `diagnostic_id`, `diagnostic_level`, event details. Destination is `[.crashlytics]` only, so this never reaches Firebase Analytics or Mixpanel. Declared under Crash Data, Performance Data, and Other Diagnostic Data. |

No analytics event carries a name, email address, free-text note, photo, or precise location.

---

## 3. App Store Connect field-by-field checklist

### Data collection and tracking

- [ ] Select **Yes, we collect data from this app**.
- [ ] Do not select any data type as used for tracking.
- [ ] Confirm **Data Used to Track You** is empty.
- [ ] Ascend does not need an ATT prompt for the audited configuration.

### Contact Info

- [ ] **Name** - Collected: Yes | Linked to the user's identity: Yes | Used for tracking: No | Purposes: App Functionality
- [ ] **Email Address** - Collected: Yes | Linked: Yes | Tracking: No | Purposes: App Functionality
- [ ] **Physical Address** - Collected: No
- [ ] **Phone Number** - Collected: No
- [ ] **Other User Contact Info** - Collected: No

### Health and Fitness

- [ ] **Health** - Collected: Yes | Linked: Yes | Tracking: No | Purposes: **Analytics, App Functionality**
- [ ] **Fitness** - Collected: Yes | Linked: Yes | Tracking: No | Purposes: Analytics, Product Personalization, App Functionality

`Health` covers HealthKit reads plus user-entered body metrics.
Banded weight and height both reach Firebase Analytics and Mixpanel, which is why Analytics is declared.
The analytics values are coarse buckets of user-typed onboarding input, not HealthKit-sourced measurements.
`Fitness` covers workout metrics, Live Climb completion and rank state, and the onboarding fitness answers.

### Financial Info

- [ ] **Payment Info** - Collected: No
- [ ] **Credit Info** - Collected: No
- [ ] **Other Financial Info** - Collected: No

Apple processes payment credentials and does not expose card details to Ascend.
Subscription and transaction history are declared under Purchases.

### Location

- [ ] **Coarse Location** - Collected: Yes | Linked: Yes | Tracking: No | Purposes: Analytics, App Functionality
- [ ] **Precise Location** - Collected: No

### Sensitive Info

- [ ] **Sensitive Info** - Collected: No

### Contacts

- [ ] **Contacts** - Collected: No

### User Content

- [ ] **Photos or Videos** - Collected: Yes | Linked: Yes | Tracking: No | Purposes: App Functionality
- [ ] **Customer Support** - Collected: Yes | Linked: Yes | Tracking: No | Purposes: App Functionality
- [ ] **Other User Content** - Collected: Yes | Linked: Yes | Tracking: No | Purposes: App Functionality
- [ ] **Emails or Text Messages** - Collected: No
- [ ] **Audio Data** - Collected: No
- [ ] **Gameplay Content** - Collected: No

`Other User Content` covers workout notes.
`Customer Support` covers feedback and support requests.

### Browsing History

- [ ] **Browsing History** - Collected: No

### Search History

- [ ] **Search History** - Collected: No

### Identifiers

- [ ] **User ID** - Collected: Yes | Linked: Yes | Tracking: No | Purposes: Analytics, App Functionality
- [ ] **Device ID** - Collected: Yes | Linked: Yes | Tracking: No | Purposes: Analytics, App Functionality

`User ID` is the Firebase Auth UID passed to Firebase Analytics, Crashlytics, Mixpanel, Sentry, RevenueCat, and Superwall.
`Device ID` covers APNs and FCM registration tokens plus app-specific analytics identifiers: Firebase App Instance ID, Firebase Installation ID, Mixpanel device distinct ID, and Superwall vendor ID.
It does not represent IDFA use.

### Purchases

- [ ] **Purchase History** - Collected: Yes | Linked: Yes | Tracking: No | Purposes: Analytics, App Functionality

RevenueCat and Superwall receive subscription, product, paywall, and purchase-result data after the app identifies the signed-in user.

### Usage Data

- [ ] **Product Interaction** - Collected: Yes | Linked: Yes | Tracking: No | Purposes: Analytics, App Functionality
- [ ] **Advertising Data** - Collected: No
- [ ] **Other Usage Data** - Collected: No

### Diagnostics

- [ ] **Crash Data** - Collected: Yes | Linked: Yes | Tracking: No | Purposes: App Functionality
- [ ] **Performance Data** - Collected: Yes | Linked: Yes | Tracking: No | Purposes: App Functionality
- [ ] **Other Diagnostic Data** - Collected: Yes | Linked: Yes | Tracking: No | Purposes: App Functionality

Crashlytics and Sentry receive crash state, nonfatal errors, logs, device and OS context, and the signed-in user ID.
Feedback diagnostics also contain device model, OS version, app version, and build number.

### Surroundings

- [ ] **Environment Scanning** - Collected: No

### Body

- [ ] **Hands** - Collected: No
- [ ] **Head** - Collected: No

### Other Data

- [ ] **Other Data Types** - Collected: Yes | Linked: Yes | Tracking: No | Purposes: Analytics, Product Personalization, App Functionality

`Other Data Types` covers declared gender and age band, notification preference, first-climb preference, and the leaderboard age-group filter.
Body metrics are declared under Health and fitness answers under Fitness, not here.

---

## 4. SDK manifest and signature audit

Established from `SourcePackages/checkouts`, `SourcePackages/artifacts`, `workspace-state.json`, and `codesign -dv --verbose=2`.
Nothing in this section is inferred.

Products linked directly by the app target, read from `project.pbxproj`: FirebaseAnalytics, FirebaseAuth, FirebaseCrashlytics, FirebaseFirestore, FirebaseFunctions, FirebaseMessaging, FirebaseStorage, GoogleSignIn, GoogleSignInSwift, MapboxMaps, Mixpanel, RevenueCat, Sentry, SuperwallKit.

### 4a. Embedded binary artifacts

| Artifact | Pinned version | Signing authority | Team | Bundled manifests |
|---|---|---|---|---:|
| `Sentry.xcframework` (static) | 9.18.0 | Apple Distribution: GetSentry LLC | 97JCY7859U | 10 |
| `FirebaseAnalytics.xcframework` | 11.15.0 | Developer ID Application: Google LLC | EQHXZ8M8AV | 0 |
| `GoogleAppMeasurement.xcframework` | 11.15.0 | Developer ID Application: Google LLC | EQHXZ8M8AV | 0 |
| `GoogleAppMeasurementIdentitySupport.xcframework` | 11.15.0 | Developer ID Application: Google LLC | EQHXZ8M8AV | 0 |
| `GoogleAppMeasurementOnDeviceConversion.xcframework` | 11.15.0 | Developer ID Application: Google LLC | EQHXZ8M8AV | 0 |
| `FirebaseFirestoreInternal.xcframework` | 11.15.0 | signed | - | 6 |
| `GoogleAdsOnDeviceConversion.xcframework` | 2.1.0 | Developer ID Application: Google LLC | EQHXZ8M8AV | 0 |
| `absl.xcframework` | 1.2024072200.0 | Developer ID Application: Google LLC | EQHXZ8M8AV | 6 |
| `grpc.xcframework` | 1.69.0 | Developer ID Application: Google LLC | EQHXZ8M8AV | 6 |
| `grpcpp.xcframework` | 1.69.0 | Developer ID Application: Google LLC | EQHXZ8M8AV | 6 |
| `openssl_grpc.xcframework` | 1.69.0 | Developer ID Application: Google LLC | EQHXZ8M8AV | 6 |
| `MapboxCommon.xcframework` | 24.24.3 | Apple Distribution: Mapbox, Inc. | GJZR2MEM28 | 7 |
| `MapboxCoreMaps.xcframework` | 11.24.3 | Apple Distribution: Mapbox, Inc. | GJZR2MEM28 | 7 |
| `MapboxMaps.xcframework` | 11.24.3 | Apple Distribution: Mapbox, Inc. | GJZR2MEM28 | 4 |
| `Turf.xcframework` | 4.0.0 | Apple Distribution: Mapbox, Inc. | GJZR2MEM28 | 0 |
| `libcel.xcframework` (static `.a`) | 1.0.14 | **not signed at all** | - | 0 |

`libcel` is the one unsigned artifact in the tree.
It arrives transitively through `superscript-ios-next 1.0.14`, a Superwall dependency, ships as static `.a` libraries linked into the app binary rather than embedded, and is not on Apple's commonly-used-SDK list.
Neither a signature nor a manifest is required for it at upload validation.

### 4b. Source SPM products that ship a manifest

| Package | Pinned version | Manifest location | Notes |
|---|---:|---|---|
| mixpanel-swift | 6.4.0 | `Sources/Mixpanel/PrivacyInfo.xcprivacy` | Collected-data array intentionally empty and configuration-neutral; declares UserDefaults reason `1C8F.1`. App-level declarations required. |
| purchases-ios | 5.74.0 | `Sources/PrivacyInfo.xcprivacy` | Declares Purchase History and UserDefaults `CA92.1`. App-level linked declaration required. |
| Superwall-iOS | 4.15.3 | `Sources/SuperwallKit/Resources/PrivacyInfo.xcprivacy` | Declares Purchase History and file timestamps `C617.1`. App-level linked declaration required. |
| firebase-ios-sdk | 11.15.0 | 12 module manifests | Core, Crashlytics, Auth, Firestore, Firestore Swift, Messaging, Installations, RemoteConfig, ABTesting, DynamicLinks, Core Internal, Core Extension. |
| GoogleUtilities | 8.1.0 | 9 module manifests | |
| GoogleDataTransport | 10.1.0 | `GoogleDataTransport/Resources/` | |
| GoogleSignIn-iOS | 9.0.0 | 2 manifests | |
| GTMAppAuth | 5.0.0 | `GTMAppAuth/Sources/Resources/` | |
| gtm-session-fetcher | 3.5.0 | 3 manifests | |
| AppAuth-iOS | 2.0.0 | 3 manifests | |
| promises | 2.4.0 | 2 manifests | |
| nanopb | 2.30910.0 | `spm_resources/` | |
| leveldb | 1.22.5 | `Resources/` | |
| swift-protobuf | 1.30.0 | 2 manifests | |

### 4c. Source SPM products with no manifest, and why none is required

| Package | Pinned version | Reason |
|---|---:|---|
| **mixpanel-swift-common** | **1.0.1** | Separately pinned sub-package of the Mixpanel family, compiled from source and statically linked into the app. Its collection surface is declared by mixpanel-swift's manifest, and it is not on Apple's required-SDK list, so it needs no manifest of its own and cannot trip upload validation. |
| app-check | 11.2.0 | Transitive Firebase dependency, source product, not on Apple's list. |
| interop-ios-for-google-sdks | 101.0.0 | Header-only interop shim. |
| json-logic-swift | 1.2.4 | Superwall rule-evaluation dependency, source product, not on Apple's list. |
| superscript-ios-next | 1.0.14 | Wrapper around the `libcel` binary target; see 4a. |
| turf-swift | 4.0.0 | Mapbox geometry helpers; the Mapbox stack's manifests ride in the binaries. |
| mapbox-common-ios | 24.24.3 | Checkout is a thin wrapper; manifest ships inside the signed xcframework. |
| mapbox-core-maps-ios | 11.24.3 | Checkout is a thin wrapper; manifest ships inside the signed xcframework. |
| mapbox-maps-ios-binary | 11.24.3 | Checkout is a thin wrapper; manifest ships inside the signed xcframework. |

Firebase Analytics intentionally ships no `PrivacyInfo.xcprivacy`.
Google documents that it is not on Apple's required-SDK manifest list, while the Firebase source modules that do require manifests, including Crashlytics, include them.
No missing manifest or signature requires an SDK upgrade at these pinned versions.

---

## 5. Required-reason API audit

| API category | Reason | Evidence | Result |
|---|---|---|---|
| UserDefaults | `CA92.1` | Ascend settings, repositories, and caches access first-party defaults in the app container | Declared in the app manifest |
| UserDefaults | `1C8F.1` | Mixpanel accesses its SDK-owned defaults | Declared in Mixpanel's bundled manifest |
| File Timestamp | `C617.1` | `DiskAssetCache` reads `contentModificationDateKey` for cache eviction; Sentry and Superwall also declare it | Declared in the app manifest |
| Disk Space | `E174.1` | Mapbox Common and Core Maps manage SDK-owned map and tile caches | Declared in the app manifest |
| System Boot Time | `35F9.1` | Mapbox Common and Core Maps, Sentry, and gRPC use elapsed-time APIs | Declared in the app manifest |
| Active Keyboards | None | No app or packaged SDK declaration or direct call was found | Not used |

---

## 6. Regression coverage

`AscendAppTests/PrivacyManifestTests.swift` holds five tests:

1. `collectedDataDeclarationsMatchOffDeviceDataContract` - the 16 declared data types, their linked flags, purposes, and non-tracking status, plus the check that every purpose is one Apple actually accepts.
2. `requiredReasonDeclarationsMatchAccessContract` - the four required-reason categories and their exact reason codes.
3. `classifiedAnalyticsAttributesDeclareAnalyticsPurpose` - every row of the section 2 inventory resolves to a data type that is declared, linked, non-tracking, and carries the Analytics purpose.
4. `userPropertyCallSitesAreFullyClassified` - scans every Swift file under `AscendApp/` for literal `setUserProperty("…")` calls plus the `set("…")` wrapper inside `OnboardingAnalyticsUserProperties`, and requires exact set equality with the classified user properties. A new literal user property anywhere in the app target fails until classified.
5. `indirectlyNamedAttributesAppearInSource` - the goal properties and the body/demographic event parameters still appear in the file that emits them.

Known coverage boundary, stated in the test file itself: test 4 cannot see runtime-assembled names or event parameters, and test 5 detects removal but not addition.
Event parameters beyond the three body/demographic ones are inventoried by hand in section 2c rather than scanned.

---

## 7. Captain and dashboard actions

1. Enter every field in section 3 in App Store Connect.
2. Confirm the App Privacy summary shows all declared data as linked and none as tracking.
3. Deploy the updated `web/src/pages/privacy.astro` build before submission and confirm the live `/privacy` page includes the demographic and fitness disclosure.
4. Re-check in the Firebase production console that Google Ads linking, Google Signals, and advertising personalization remain disabled.
5. Keep Superwall Apple Search Ads attribution disabled unless a future change adds ATT and updates every privacy surface.

The Superwall production application audit found Apple Search Ads configuration disabled.
The checked-in development and staging Firebase configurations have ads collection disabled.
No dashboard action requires a product decision for the current non-tracking posture.

---

## 8. Review-exposure note

Declaring Health as used for Analytics surfaces on the nutrition label that health-category data reaches Firebase Analytics and Mixpanel, which App Review Guideline 5.1.3 scrutinizes.
The exposure is limited: the values are coarse buckets of user-typed onboarding input rather than HealthKit-sourced samples, and the purpose is first-party product analytics rather than data mining.
Workout-import telemetry sends only counts and source mix, never a HealthKit measurement value.
Recorded so the reasoning is on file if a reviewer asks.

---

## 9. Authoritative references

- Apple third-party SDK requirements: <https://developer.apple.com/support/third-party-SDK-requirements/>
- Apple privacy manifest files: <https://developer.apple.com/documentation/bundleresources/privacy-manifest-files>
- Apple data-use declarations: <https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests>
- Apple collected-data purposes: <https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatypepurposes>
- Firebase Apple-platform data collection: <https://firebase.google.com/docs/ios/app-store-data-collection>
- Google Analytics data collection: <https://support.google.com/analytics/answer/11593727>
- Mixpanel App Store privacy details: <https://mixpanel.com/legal/app-store-privacy-details/>
- Superwall privacy nutrition labels: <https://superwall.com/docs/ios/guides/app-privacy-nutrition-labels>
- Superwall identity management: <https://superwall.com/docs/identity-management>
