import FirebaseCore
import FirebaseFirestore
import Foundation
import Testing
@testable import AscendApp

/// The lab volume as a phone sees it.
///
/// The image is 8 MB and the policy's floor is 200 MiB, so a plain reading of the image is
/// under the floor even when it is empty. This reader keeps the two states a phone has: room
/// (a reading comfortably above the floor) while the image has free blocks, and the raw
/// reading - effectively zero - once it does not. What is under test is the real SDK on a
/// real full volume and the real gate reading that same volume; only the scale is the lab's.
struct LabVolumeReader: VolumeFreeSpaceReading {
    static let roomThresholdBytes: Int64 = 1 << 20

    private let reader: VolumeFreeSpaceReader

    init(mountPoint: String) {
        reader = VolumeFreeSpaceReader(path: mountPoint)
    }

    func availableBytes() -> Int64? {
        guard let raw = reader.availableBytes() else { return nil }
        return raw >= Self.roomThresholdBytes ? raw + FirestoreDiskPolicy.lowDiskFloorBytes : raw
    }

    func availableBytesForImportantUsage() -> Int64? {
        reader.availableBytesForImportantUsage()
    }
}

/// A Firestore whose on-device LevelDB cache lives on a volume the test can fill.
///
/// The simulator shares the Mac's volume and cannot fill it, so the volume Firestore
/// writes to is swapped instead: `scripts/ci/run-ios-test-passes.sh` creates a tiny
/// APFS disk image, attaches it with `-nobrowse`, and hands its mount point to the
/// test host as `ASCEND_DISKFULL_MOUNT`. The lab points a dedicated `FirebaseApp`'s
/// persistence directory (`Library/Application Support/firestore/<app>`) into that
/// image through a symlink, so the real SDK does its real LevelDB writes on a volume
/// that is about to have no free blocks - the state Urjita's phone was in on
/// 2026-10-23 when `LevelDbTransaction::Commit()` aborted her Empire State climb.
enum FirestoreDiskFullLab {
    static let mountEnvironmentKey = "ASCEND_DISKFULL_MOUNT"

    /// The mount point the runner attached, or nil when this host was started without
    /// the image, in which case the suite skips itself and says so.
    static var mountPoint: String? {
        ProcessInfo.processInfo.environment[mountEnvironmentKey]
    }

    struct FillOutcome: CustomStringConvertible {
        let bytesWritten: Int
        let lastError: String

        var description: String { "bytesWritten=\(bytesWritten) lastError=\(lastError)" }
    }

    /// Points the LevelDB directory Firestore will use for `appName` at a directory inside
    /// `mountPoint`. Separate from `makeFirestore` because a directory cannot be created on a
    /// volume that is already full, and a test that wants Firestore *started* on a full volume
    /// has to make room for its directory first.
    static func prepareCacheDirectory(appName: String, mountPoint: String) throws {
        let fileManager = FileManager.default
        let appSupport = try #require(fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        let firestoreRoot = appSupport.appending(path: "firestore")
        try fileManager.createDirectory(at: firestoreRoot, withIntermediateDirectories: true)
        let link = firestoreRoot.appending(path: appName)
        let target = URL(fileURLWithPath: mountPoint).appending(path: appName)
        try? fileManager.removeItem(at: link)
        try? fileManager.removeItem(at: target)
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: target)
    }

    /// A dedicated Firestore instance for `appName`, whose directory `prepareCacheDirectory`
    /// has already pointed into the lab volume.
    ///
    /// `appName` has to be unique per instance for the life of the process: `FirebaseApp`
    /// names cannot be reconfigured, and Firestore names its directory after the app.
    /// `configure` runs before the instance's first operation, which is where its cache
    /// settings have to be applied; the lab then disables the network so nothing is sent.
    @MainActor
    static func makeFirestore(
        appName: String,
        configure: (Firestore) -> Void
    ) async throws -> Firestore {
        // Well-formed but inert options: FirebaseCore validates the shape of the app id and
        // FirebaseInstallations the shape of the key. The network stays disabled, so nothing
        // is ever sent to this project, which does not exist.
        let options = FirebaseOptions(googleAppID: "1:808186881002:ios:4524144d6c8e677357c893", gcmSenderID: "808186881002")
        options.projectID = "disk-full-lab-project"
        options.apiKey = "ADiskFullLabDiskFullLabDiskFullLabDiskF"
        if FirebaseApp.app(name: appName) == nil {
            FirebaseApp.configure(name: appName, options: options)
        }
        let app = try #require(FirebaseApp.app(name: appName))
        let db = Firestore.firestore(app: app)
        configure(db)
        try await db.disableNetwork()
        return db
    }

    /// Removes every filler file, so a test that needs the volume to have room again gets it.
    static func freeVolume(_ mountPoint: String) throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: mountPoint)
        for name in try fileManager.contentsOfDirectory(atPath: mountPoint) where name.hasPrefix("filler-") {
            try fileManager.removeItem(at: root.appending(path: name))
        }
    }

    /// Writes junk into the volume until every write size down to one byte is refused.
    /// Idempotent: a volume that is already full refuses the first write of every size.
    static func fill(_ mountPoint: String) -> FillOutcome {
        var total = 0
        var lastError = "none"
        let path = URL(fileURLWithPath: mountPoint).appending(path: "filler-\(UUID().uuidString).bin")
        FileManager.default.createFile(atPath: path.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: path) else {
            return FillOutcome(bytesWritten: 0, lastError: "open failed")
        }
        defer { try? handle.close() }
        for chunk in [1 << 20, 1 << 16, 4096, 512, 64, 1] {
            let data = Data(repeating: 0x5a, count: chunk)
            while true {
                do {
                    try handle.write(contentsOf: data)
                    try handle.synchronize()
                    total += chunk
                } catch {
                    lastError = "\(error)"
                    break
                }
            }
        }
        return FillOutcome(bytesWritten: total, lastError: lastError)
    }

    /// One listen that resolves on its first (cached, empty) snapshot. A distinct
    /// `whereField` value makes every call a new target, so `LocalStore::AllocateTarget`
    /// has to write - exactly what a live-leaderboard window read does every five seconds.
    @MainActor
    static func listenOnce(_ db: Firestore, marker: String) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            var registration: ListenerRegistration?
            var resumed = false
            registration = db.collection("live_replay_leaderboards")
                .whereField("lab", isEqualTo: marker)
                .addSnapshotListener { snapshot, error in
                    guard !resumed else { return }
                    resumed = true
                    registration?.remove()
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: snapshot == nil ? 0 : 1)
                    }
                }
        }
    }
}
