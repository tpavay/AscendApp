import Foundation

/// The server-controlled off switches Ascend ships.
///
/// An iOS binary cannot be rolled back, so the *automatic, bulk* paths that decide the shape of
/// persisted data - what gets written to Firestore or Storage, what gets decoded back into
/// SwiftData, and what rewrites rows en masse - each sit behind one of these. Flipping a flag off in
/// the Firebase console stops that path on every running install without a new submission.
///
/// Single, user-initiated writes are deliberately not here; killing one would break the app rather
/// than protect anything. `docs/remote-config-kill-switches.md` draws that line.
///
/// Each case's raw value is the Remote Config parameter key. Keys are added to the Remote Config
/// template as **Boolean** parameters; anything else the server sends is ignored in favour of
/// ``shippedDefault`` (see ``RemoteFeatureFlagSnapshot``).
enum RemoteFeatureFlag: String, CaseIterable, Sendable {
    /// Uploading workout documents and heart-rate sidecars to the cloud backup.
    case workoutCloudBackupWrites = "workout_cloud_backup_writes_enabled"

    /// Deleting remote workout documents and their heart-rate sidecars. Destructive and
    /// irreversible, so it is separable from the upload path.
    case workoutRemoteDeletes = "workout_remote_deletes_enabled"

    /// Re-opening one automatic attempt for workouts whose retry series has stopped - after a
    /// build change, an operator-bumped recovery epoch, or the climber signing back in, which
    /// re-opens only the series that failing credentials stopped. Reshapes persisted sync state, so
    /// it is separable from the upload path it feeds.
    case workoutSyncRecoveryReopen = "workout_sync_recovery_reopen_enabled"

    /// Decoding cloud backups back into local SwiftData on sign-in and reinstall.
    case workoutCloudRestore = "workout_cloud_restore_enabled"

    /// The background media upload queue, including the sweep that deletes local originals
    /// once they are believed uploaded.
    case workoutMediaUploads = "workout_media_uploads_enabled"

    /// Uploading user-authored routines and routine folders to the cloud backup.
    case routineCloudBackupWrites = "routine_cloud_backup_writes_enabled"

    /// Deleting remote routine and routine folder documents. Destructive and
    /// irreversible, so it is separable from the upload path.
    case routineRemoteDeletes = "routine_remote_deletes_enabled"

    /// Decoding routine backups back into local SwiftData on sign-in and reinstall.
    case routineCloudRestore = "routine_cloud_restore_enabled"

    /// The background pass that reads Apple Health and writes heart rate and calories onto
    /// climbs Ascend recorded. Autonomous and retrying, so a bad read would rewrite rows across
    /// the retry window without anyone asking for it.
    case appleHealthEnrichment = "apple_health_enrichment_enabled"

    /// Uploading a badly-miscounted climb's raw headphone-motion capture to Storage for step
    /// algorithm debugging. Unlike every other switch, a blocked upload has nothing to defer: the
    /// capture only ever lives in memory until calibration, so a climb it blocks is simply not
    /// uploaded - exactly as if the retention trigger had not fired - and is never queued for
    /// later.
    case stepAccuracyRawCaptureUpload = "step_accuracy_raw_capture_upload_enabled"

    /// One-shot local backfills that rewrite existing SwiftData rows in bulk.
    case localDataMigrations = "local_data_migrations_enabled"

    /// Publishing the public profile mirror - identity, stats, and workout summaries.
    case publicProfilePublishing = "public_profile_publishing_enabled"

    /// Every champion surface: crowns on pictures, the board's champion strip, past boards,
    /// and the board-coloured podium. Display only - turning it off writes and deletes
    /// nothing, and the next open after it returns shows the reigning champions again.
    case championRecognition = "champion_recognition_enabled"

    /// Presenting the period recap and writing its `seenAt`, the one client write the recap
    /// adds. Off, unseen recaps stay unseen on the server and show on the first open after
    /// the switch returns.
    case periodRecap = "period_recap_enabled"

    /// Every unlock surface: the carried item drawn on the mountain, the unlock moment after a
    /// climb, and the editor's carry row. Display only - off, nothing is drawn or offered, nothing
    /// is written or deleted, and what was earned is offered and drawn again when it returns.
    case unlocks = "unlocks_enabled"

    /// Firestore's memory cache, which keeps LevelDB - and the commit assertion that aborts the
    /// process on a full volume - out of every process. Off gives a process that launches with
    /// at least 200 MiB free a persistent cache bounded to 20 MiB, guarded by the pre-flight that
    /// refuses server reads, defers workout sync and drops the attempt heartbeat once the volume
    /// reaches the floor; that guard cannot reach the Home feed listener, the SDK's own garbage
    /// collection, or the reads that bypass the shared read path. Decides how Firestore persists
    /// at startup, which is why it has a switch (`docs/firestore-disk-full-guard.md`).
    case firestoreMemoryCache = "firestore_memory_cache_enabled"

    /// Writing the sixty-second liveness document `users/{uid}/attempt_heartbeats/{sessionID}`
    /// during every headphone session, and the final write that closes it. Nothing to defer: a
    /// heartbeat is a report about now, so a blocked one is simply not sent and the server's
    /// stall detector sees nothing for that session. The climb itself is untouched.
    case attemptHeartbeats = "attempt_heartbeats_enabled"

    /// Resuming a dead session automatically on the next launch - crediting the gap as wall clock
    /// into the draft and restarting the sensor without a prompt. Off, every recovered draft goes
    /// through the recovery screen instead, which credits nothing until the climber acts, so the
    /// draft is left exactly as the dead process wrote it.
    case headphoneSessionAutoResume = "headphone_session_auto_resume_enabled"

    /// Logging a climb by hand - the Log it entry and the save behind it - and re-deriving a
    /// climb's leaderboard status from its pace when it is restored or its steps or time are
    /// edited. Off, Log it is not offered and every stored status is left exactly as it is.
    case climbLogging = "climb_logging_enabled"

    /// The pre-sign-in onboarding of 1.3.0: selling screens, setup questions and the paywall before
    /// sign-in. Off, a signed-out climber gets the flow that shipped before it, whole. Display and
    /// routing only - it writes nothing, and the answers it collects stay on the device until
    /// ``onboardingAnswersProfileWrite`` lets the post-sign-in hand-off send them. Unlike a kill
    /// switch it ships off, because it is a rollout and not a path that must keep running
    /// (`docs/remote-config-kill-switches.md`).
    case onboardingV3 = "onboarding_v3_enabled"

    /// Scheduling the local weekly-target nudge. Off, nothing new is scheduled and the pending nudge
    /// is cleared; the climber's target and climbs are untouched, and the next reconcile after the
    /// switch returns schedules it again.
    case weeklyTargetReminder = "weekly_target_reminder_enabled"

    /// Scheduling the local reminder two days before a free trial ends. Same behaviour as
    /// ``weeklyTargetReminder``: off schedules and keeps nothing, and the trial itself is untouched.
    case trialEndingReminder = "trial_ending_reminder_enabled"

    /// The server push that announces a new gear event to climbers who opted in to notifications.
    /// Read by `functions/src/gearDropPush.ts`, never by the app. A rollout, so it ships off: existing
    /// climbers opted in to climb alerts only, and no gear push reaches anyone until the captain
    /// decides the consent question (App Store 4.5.4) and turns it on. Off, the sweep sends nothing
    /// and the event stays unannounced, so the first sweep after the switch is turned on sends it if
    /// it is still within its window.
    case gearDropPush = "gear_drop_push_enabled"

    /// Importing stair workouts from Apple Health as climbs: the discovery pass, the automatic
    /// import, the Imports screen's import actions and the observer that wakes the app for a new
    /// workout. Off, every workout already found stays where it is and nothing new is imported or
    /// announced; turning it back on resumes from the same anchor, so no workout is lost.
    case appleHealthImport = "apple_health_import_enabled"

    /// Writing the answers a climber gave before signing in - birthday, gender, height, weight and
    /// city - to their profile right after sign-in. Off, the answers stay on the device exactly as
    /// given and the next launch with the switch on writes them; nothing is dropped.
    case onboardingAnswersProfileWrite = "onboarding_answers_profile_write_enabled"

    /// Writing the climber's weekly target (`weekly_target_days`) to their private user record.
    /// Off, a change stays on the device, marked unsynced, and goes up when the switch returns;
    /// the target itself keeps working because the device's copy is the one Home reads.
    case weeklyTargetWrites = "weekly_target_writes_enabled"

    var key: String { rawValue }

    /// The value used when the Remote Config backend has never successfully answered on this
    /// device.
    ///
    /// Every kill switch ships `true`, and the rollouts - ``onboardingV3`` and ``gearDropPush`` - ship `false`. Fetch failure falls back to the app's normal, tested behaviour
    /// rather than to "off". The reasoning is written up in
    /// `docs/remote-config-kill-switches.md`; the short version is that a fetch failure almost
    /// always means "this device is offline", and an offline device that silently stopped backing
    /// up workouts would make the safety mechanism the leading cause of the data loss it exists to
    /// prevent.
    var shippedDefault: Bool {
        switch self {
        case .onboardingV3, .gearDropPush: false
        default: true
        }
    }

    /// Whether this flag gates a rollout instead of a path that must keep running. A rollout is
    /// dark until an operator turns it on, so being off is its healthy state and says nothing about
    /// an incident.
    var isRollout: Bool { shippedDefault == false }

    /// What an operator turns off when they flip this flag. Surfaced in the debug console so the
    /// person reaching for the switch under pressure does not have to guess.
    var summary: String {
        switch self {
        case .workoutCloudBackupWrites:
            return "Uploads workout documents and heart-rate sidecars to cloud backup."
        case .workoutRemoteDeletes:
            return "Deletes remote workout documents and heart-rate sidecars."
        case .workoutSyncRecoveryReopen:
            return "Re-opens one sync attempt for a stopped workout after a build, epoch or sign-in."
        case .workoutCloudRestore:
            return "Restores cloud backups into local storage on sign-in and reinstall."
        case .workoutMediaUploads:
            return "Uploads queued workout photos and videos, and sweeps local originals."
        case .routineCloudBackupWrites:
            return "Uploads user-authored routines and folders to cloud backup."
        case .routineRemoteDeletes:
            return "Deletes remote routine and routine folder documents."
        case .routineCloudRestore:
            return "Restores routine backups into local storage on sign-in and reinstall."
        case .appleHealthEnrichment:
            return "Reads Apple Health and writes heart rate and calories onto recorded climbs."
        case .stepAccuracyRawCaptureUpload:
            return "Uploads raw headphone-motion captures of badly-miscounted climbs for debugging."
        case .localDataMigrations:
            return "Runs one-shot local backfills that rewrite stored workouts."
        case .publicProfilePublishing:
            return "Publishes the public profile mirror, stats, and workout summaries."
        case .championRecognition:
            return "Shows champion crowns, the champion strip, and past boards."
        case .periodRecap:
            return "Shows the period recap after a week or month closes and marks it seen."
        case .unlocks:
            return "Shows unlockable items: drawn on the mountain, the unlock moment, the editor row."
        case .firestoreMemoryCache:
            return "Runs Firestore on a memory cache; off allows a 20 MiB disk cache from the next cold launch."
        case .attemptHeartbeats:
            return "Writes the sixty-second liveness heartbeat for a running climb to Firestore."
        case .headphoneSessionAutoResume:
            return "Resumes a dead session automatically on relaunch instead of asking first."
        case .climbLogging:
            return "Offers Log it and saves typed climbs; re-derives a climb's leaderboard status."
        case .onboardingV3:
            return "Shows the 1.3.0 pre-sign-in onboarding to signed-out climbers. Ships off."
        case .weeklyTargetReminder:
            return "Schedules the local nudge when a climber is short of their weekly target."
        case .trialEndingReminder:
            return "Schedules the local reminder two days before a free trial ends."
        case .gearDropPush:
            return "Lets the server push announce a new gear event. Ships off. Read by the Cloud Function, not the app."
        case .appleHealthImport:
            return "Finds and imports Apple Health stair workouts as climbs; wakes for new ones."
        case .onboardingAnswersProfileWrite:
            return "Writes the answers given before sign-in to the profile right after sign-in."
        case .weeklyTargetWrites:
            return "Writes the weekly target to the climber's user record; off keeps it on the device."
        }
    }
}
