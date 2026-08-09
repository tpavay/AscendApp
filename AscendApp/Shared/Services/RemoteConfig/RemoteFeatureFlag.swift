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

    /// One-shot local backfills that rewrite existing SwiftData rows in bulk.
    case localDataMigrations = "local_data_migrations_enabled"

    /// Publishing the public profile mirror - identity, stats, and workout summaries.
    case publicProfilePublishing = "public_profile_publishing_enabled"

    var key: String { rawValue }

    /// The value used when the Remote Config backend has never successfully answered on this
    /// device.
    ///
    /// Every flag ships `true` - fetch failure falls back to the app's normal, tested behaviour
    /// rather than to "off". The reasoning is written up in
    /// `docs/remote-config-kill-switches.md`; the short version is that a fetch failure almost
    /// always means "this device is offline", and an offline device that silently stopped backing
    /// up workouts would make the safety mechanism the leading cause of the data loss it exists to
    /// prevent.
    var shippedDefault: Bool { true }

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

        case .localDataMigrations:
            return "Runs one-shot local backfills that rewrite stored workouts."
        case .publicProfilePublishing:
            return "Publishes the public profile mirror, stats, and workout summaries."
        }
    }
}
