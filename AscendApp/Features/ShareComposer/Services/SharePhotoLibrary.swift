import AVFoundation
import Observation
import Photos
import UIKit

/// Backs the custom Camera Roll grid: authorization, asset fetch, and
/// thumbnail / full-asset loading. Photos access is requested at first use
/// (point of use), never in onboarding.
@MainActor
@Observable
final class SharePhotoLibrary {
    enum AccessState: Equatable {
        case unknown
        case authorized
        case limited
        case denied
    }

    private(set) var accessState: AccessState = .unknown
    private(set) var assets: [PHAsset] = []

    private let imageManager = PHCachingImageManager()

    /// Non-Sendable image ferried across a Photos callback boundary.
    private struct SendableImage: @unchecked Sendable { let image: UIImage? }
    private struct SendableURL: @unchecked Sendable { let url: URL? }

    // MARK: - Authorization + fetch

    func loadIfNeeded() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized:
            accessState = .authorized
            fetchAssets()
        case .limited:
            accessState = .limited
            fetchAssets()
        case .denied, .restricted:
            accessState = .denied
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            switch granted {
            case .authorized: accessState = .authorized; fetchAssets()
            case .limited: accessState = .limited; fetchAssets()
            default: accessState = .denied
            }
        @unknown default:
            accessState = .denied
        }
    }

    private func fetchAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // Images + videos only.
        options.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        let result = PHAsset.fetchAssets(with: options)
        var collected: [PHAsset] = []
        collected.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in collected.append(asset) }
        assets = collected
    }

    // MARK: - Loading

    func thumbnail(for asset: PHAsset, size: CGFloat) async -> UIImage? {
        let target = CGSize(width: size * 2, height: size * 2)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            imageManager.requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: SendableImage(image: image).image)
            }
        }
    }

    func fullImage(for asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let target = CGSize(width: 1242, height: 2208)
        return await withCheckedContinuation { continuation in
            imageManager.requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: SendableImage(image: image).image)
            }
        }
    }

    func videoURL(for asset: PHAsset) async -> URL? {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            imageManager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                let url = (avAsset as? AVURLAsset)?.url
                continuation.resume(returning: SendableURL(url: url).url)
            }
        }
    }
}
