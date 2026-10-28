import Observation
import Photos
import UIKit

/// The photographs the single-photo background picker offers: the ones taken during the climb
/// first, then earlier ones. Access is requested at the point of use, never earlier.
@MainActor
@Observable
final class PresetPhotoLibrary {
    struct Photo: Identifiable, Equatable, Sendable {
        let id: String
        let creationDate: Date?
    }

    enum Access: Equatable {
        case unknown
        case granted
        case denied
    }

    private(set) var access: Access = .unknown
    private(set) var duringClimb: [Photo] = []
    private(set) var earlier: [Photo] = []
    private(set) var isLoading = false

    /// Earlier photos shown before the climber opens the full picker.
    static let earlierLimit = 24

    private let imageManager = PHCachingImageManager()

    private struct SendableImage: @unchecked Sendable { let image: UIImage? }

    /// `window` is the climb's own time span: its start and its start plus its duration.
    func load(climbWindow window: DateInterval) async {
        isLoading = true
        defer { isLoading = false }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            access = .granted
        case .denied, .restricted:
            access = .denied
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            access = (granted == .authorized || granted == .limited) ? .granted : .denied
        @unknown default:
            access = .denied
        }
        guard access == .granted else { return }

        let fetched = await Self.fetch(window: window, earlierLimit: Self.earlierLimit)
        duringClimb = fetched.during
        earlier = fetched.earlier
    }

    /// Photos only; videos are not backgrounds. The climb's own window comes first, then the
    /// newest photos from before it.
    nonisolated private static func fetch(
        window: DateInterval,
        earlierLimit: Int
    ) async -> (during: [Photo], earlier: [Photo]) {
        let duringOptions = PHFetchOptions()
        duringOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        duringOptions.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
            PHAssetMediaType.image.rawValue,
            window.start as NSDate,
            window.end as NSDate
        )
        let during = photos(from: PHAsset.fetchAssets(with: duringOptions))

        let earlierOptions = PHFetchOptions()
        earlierOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        earlierOptions.fetchLimit = earlierLimit
        earlierOptions.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate < %@",
            PHAssetMediaType.image.rawValue,
            window.start as NSDate
        )
        let earlier = photos(from: PHAsset.fetchAssets(with: earlierOptions))
        return (during, earlier)
    }

    nonisolated private static func photos(from result: PHFetchResult<PHAsset>) -> [Photo] {
        var collected: [Photo] = []
        collected.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            collected.append(Photo(id: asset.localIdentifier, creationDate: asset.creationDate))
        }
        return collected
    }

    // MARK: - Images

    nonisolated func thumbnail(for id: String, side: CGFloat) async -> UIImage? {
        guard let asset = Self.asset(id) else { return nil }
        let target = CGSize(width: side * 2, height: side * 2)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            imageManager.requestImage(for: asset, targetSize: target, contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: SendableImage(image: image).image)
            }
        }
    }

    /// A photograph at the card's export resolution, enough to fill 1080 points square.
    nonisolated func cardImage(for id: String) async -> UIImage? {
        guard let asset = Self.asset(id) else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let target = CGSize(width: 1620, height: 1620)
        return await withCheckedContinuation { continuation in
            imageManager.requestImage(for: asset, targetSize: target, contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: SendableImage(image: image).image)
            }
        }
    }

    nonisolated private static func asset(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }
}
