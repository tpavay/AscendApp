import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Holds the photo a climber picks on the profile screen until there is an account to upload it to.
///
/// Nothing reaches Storage before sign-in: there is no uid, and `users/{uid}/profile_pictures/` is
/// the only place a profile photo may go. The picture waits here, as a small JPEG in Application
/// Support, and the sign-in hand-off uploads it through the app's existing profile photo path and
/// then removes it. Sign-out and Skip remove it too, so the next account on the phone never inherits it.
///
/// The picture is redrawn at a capped size through ImageIO, which drops the EXIF block - a photo's
/// location never leaves the device with it - and keeps the upload small.
struct OnboardingProfilePhotoStore: Sendable {
    /// The longest side of the stored picture. The avatar is drawn at 42 pt, so this is generous.
    static let maximumPixelSize = 1_024
    private static let compressionQuality = 0.85

    private let directory: URL

    init(directory: URL = .applicationSupportDirectory.appending(path: "OnboardingProfilePhoto", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    /// Draws `data` at the stored size and keeps it under a fresh name. A new name every time is
    /// what makes the avatar redraw when the climber swaps one picture for another.
    ///
    /// - Returns: the file name to keep in the answers, or `nil` when `data` is not a picture.
    func save(_ data: Data) -> String? {
        guard let jpeg = Self.downscaledJPEG(from: data) else { return nil }

        let name = "photo-\(UUID().uuidString).jpg"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try jpeg.write(to: directory.appending(path: name), options: [.atomic, .completeFileProtection])
            return name
        } catch {
            return nil
        }
    }

    /// Where `name` is, if it is still on the device.
    func url(for name: String?) -> URL? {
        guard let name, !name.isEmpty, !name.contains("/") else { return nil }

        let url = directory.appending(path: name)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// The stored picture, or `nil` only when it is not on the device. A picture that is there but
    /// cannot be read throws, because it can still be read later and must not be taken for gone.
    func data(for name: String?) throws -> Data? {
        try url(for: name).map { try Data(contentsOf: $0) }
    }

    /// Removes every stored picture except `kept`, so a picture picked and then walked away from
    /// does not outlive the pass that picked it.
    func remove(keeping kept: String? = nil) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        for name in names where name != kept {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    static func downscaledJPEG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary
        )
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
