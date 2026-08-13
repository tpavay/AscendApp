# Analytics Privacy Classification

Adding or renaming any analytics user property or event parameter requires updating this mapping and `AscendApp/PrivacyInfo.xcprivacy` in the same change.

Everything listed here reaches Firebase Analytics and Mixpanel.
Mixpanel receives it after `identify` and Firebase Analytics after `setUserID`, so every data type below is declared **Linked to the user** and **non-tracking**, and every one of them carries the Analytics purpose in the manifest.
`AscendAppTests/PrivacyManifestTests.swift` pins those manifest flags, and it fails on any literally named user property that is not classified in its `analyticsAttributes` list.
Event parameters are not scanned, which is why they are inventoried here.

## User properties

| Data type | Properties |
| --- | --- |
| Health | `profile_weight_group` (band, never the raw weight) |
| Coarse Location | `profile_country` (ISO country code) |
| Fitness | `stair_stepper_exp`, `exercise_level`, `motivation`, `planned_frequency`, `goal_lose_weight`, `goal_build_endurance`, `goal_track_progress`, `goal_exciting_workouts`, `goal_healthier_life`, `goal_answer_count` |
| Other Data Types | `profile_gender`, `profile_age_group` (band, never the birth date), `notifications_choice`, `first_climb_id`, `first_climb_tier`, `first_climb_steps` |
| Product Interaction | `display_name_set`, `profile_location_set`, `onboarding_complete`, `name_inputted`, `division_inputted`, `age_inputted`, `body_metrics_inputted`, `location_inputted`, `notifications_inputted`, `first_climb_selected` |

## Event parameters

| Data type | Parameters | Call sites |
| --- | --- | --- |
| Health | `profile_height_group`, `profile_weight_group`, `body_weight_filter` | Banded body values on the onboarding body-metrics `onboarding_screen_completed`, and the leaderboard body-weight band on every `leaderboard_filter_*` event |
| Coarse Location | `profile_country`, `location_filter` | The onboarding location `onboarding_screen_completed`, and the leaderboard location filter |
| Fitness | `session_type`, `goal_kind`, `stop_reason`, `duration_bucket`, `steps_bucket`, `progress_bucket`, `target_duration_bucket`, `target_steps_bucket`, `correction_count_bucket`, `had_step_corrections`, `tracking_unavailable_bucket`, `interval_count_bucket`, `difficulty_bucket`, `has_default_weights`, `rank_bucket`, `rank_total_bucket`, `climb_steps_bucket` | Banded workout, Live Climb, and routine measurements (`just_climb_*`, `routine_*`, `live_climb_attempt_*`). Continuous values are always bucketed before they are logged |
| Purchase History | `placement`, `paywall_identifier`, `paywall_name`, `presented_by`, `is_free_trial_available`, `presentation_id`, `presentation_source_type`, `primary_product_id`, `product_id`, `transaction_type`, `restore_type`, `error_type`, `dismiss_reason`, `entitlement_id`, `entitlement_active` | `paywall_*` and `revenuecat_*` events built by `PaywallAnalyticsEvent`, plus `onboarding_paywall_reached` |
| Other Data Types | `climb_id`, `climb_name`, `climb_tier`, `climb_category`, `routine_id`, `routine_source`, `template_id`, `age_group`, `profile_gender`, `profile_age_group`, `measurement_system`, `status` | Climb and routine content identifiers, the leaderboard age band, and the onboarding gender, age, and unit answers |
| Product Interaction | `screen_id`, `step_id`, `from_step`, `flow_id`, `flow_version`, `segment_id`, `step_index`, `step_count`, `resume`, `completion_reason`, `action_id`, `input_type`, `selection_type`, `answer_index`, `has_answer`, `viewed`, `completed`, `question_id`, `provider`, `source`, `entry_point`, `surface`, `share_surface`, `card_type`, `home_state`, `action_state`, `can_start`, `blocked_reason`, `selection_method`, `display_name_provided`, `total_climbs_bucket`, `filter_group`, `filter_type`, `metric`, `time_frame`, `active_filter_count`, `has_active_filters`, `session_id`, `session_type`, `root_route`, `auth_state`, `screen_name`, `screen_class` | Navigation, funnel position, interaction shape, and bounded app-session context across every feature. `screen_name` and `screen_class` ride the one `screen_view` event and come from the bounded `TelemetryScreenName` catalog, so they are route labels rather than anything the climber typed |
| Other Diagnostic Data | `app_environment`, `build_config`, `app_version`, `build_number`, `first_open_app_version`, `first_open_build_number` | The `TelemetryEnvelope` the facade attaches to every event and every screen view, plus the build metadata captured at the installation's first open. Build metadata only - it carries no user information |
| Other Diagnostic Data | `reason` on `paywall_skipped` and `onboarding_auth_failed`, `error` on `paywall_error`, `expected_offering_id`, `has_expected_offering`, `missing_product_count` | Superwall's own skip reason and error description, built in `SuperwallPaywallPresenter` and carried by `TelemetryRecord`'s default `destinations: [.analytics]`, plus the RevenueCat catalog audit in `RevenueCatEntitlementService` |

## Parameters whose classification depends on the call site

- `selected_value` on `leaderboard_filter_changed` is **Health** when `filter_type` is `body_weight`, **Other Data Types** when it is `age_group`, and **Coarse Location** when it is `location`.
- `answer_id` and `answer_count` on `onboarding_question_answered` are **Fitness** for the `stair_stepper_baseline`, `exercise_level`, `goal`, `motivation`, and `plan` questions, and **Other Data Types** for the `notifications` and `first_climb` questions.
- `outcome` is **Fitness** on `live_climb_attempt_saved`, and **Purchase History** on every `revenuecat_purchase_*` and `revenuecat_restore_*` terminal event.
- `session_type` is **Fitness** on workout and routine events, and **Product Interaction** on `app_session_started`.
- `entitlement_active` is **Purchase History**, and it is logged only where the entitlement answer was actually resolved: `revenuecat_purchase_completed`, `revenuecat_restore_completed`, and `revenuecat_restore_not_found`. `revenuecat_restore_failed` omits it deliberately - an unresolved restore is not evidence of a lapsed subscription.
- `error_type` on every `revenuecat_purchase_failed`, `revenuecat_restore_failed` and `paywall_transaction_failed` is a **Purchase History** value drawn from the closed `RevenueCatAnalyticsErrorType` set. It is never raw error text, so it stays low-cardinality and carries no vendor or account detail.
- `reason` is **Other Diagnostic Data** on `paywall_skipped` and `onboarding_auth_failed`, where it carries an SDK-authored string rather than a user choice.

## What deliberately does not reach analytics

`AppDiagnosticsRecorder` mirrors `diagnostic:*` events with `destinations: [.crashlytics]` only, so their `error`, `reason`, `diagnostic_id`, and `diagnostic_level` details are Crash Data and Performance Data, not Analytics.
The telemetry console probe in `TelemetryConsoleView` (`probe_id`, `sent_at_unix`) is DEBUG-only and never ships.
Raw user input, email, birth dates, exact body measurements, and exact locations are never logged as a property or a parameter; bucket a continuous value before it becomes either.
