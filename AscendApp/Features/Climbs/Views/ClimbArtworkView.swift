import SwiftUI
import UIKit

struct ClimbArtworkView: View {
    let climb: Climb
    let variant: ClimbImageVariant
    private let imageRepository: any ClimbImageRepository
    private let cacheKey: String

    @State private var loadedImage: UIImage?
    @State private var loadedImageKey: String?
    @State private var isLoading: Bool

    init(
        climb: Climb,
        variant: ClimbImageVariant,
        imageRepository: any ClimbImageRepository = FirebaseClimbImageRepository.shared
    ) {
        let cacheKey = Self.cacheKey(for: climb, variant: variant)
        let cachedImage = ClimbArtworkMemoryCache.shared.image(for: cacheKey)

        self.climb = climb
        self.variant = variant
        self.imageRepository = imageRepository
        self.cacheKey = cacheKey
        self._loadedImage = State(initialValue: cachedImage)
        self._loadedImageKey = State(initialValue: cachedImage == nil ? nil : cacheKey)
        self._isLoading = State(initialValue: cachedImage == nil)
    }

    var body: some View {
        ZStack {
            if let displayImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                placeholder
            }

            if isLoading, displayImage == nil {
                ProgressView()
                    .tint(.white.opacity(0.85))
                    .scaleEffect(0.9)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: cacheKey) {
            await loadArtwork()
        }
    }

    private var displayImage: UIImage? {
        if loadedImageKey == cacheKey, let loadedImage {
            return loadedImage
        }

        return ClimbArtworkMemoryCache.shared.image(for: cacheKey)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    climb.tier.color.opacity(0.65),
                    Color.night,
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            placeholderContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var placeholderContent: some View {
        if variant == .hero {
            VStack(spacing: 10) {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))

                Text(climb.name)
                    .font(.montserratSemiBold(size: 15))
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }
            .padding(24)
        } else {
            Image(systemName: placeholderSymbol)
                .font(.system(size: variant == .card ? 22 : 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    static func loadImage(
        for climb: Climb,
        variant: ClimbImageVariant,
        imageRepository: any ClimbImageRepository = FirebaseClimbImageRepository.shared
    ) async -> UIImage? {
        let cacheKey = Self.cacheKey(for: climb, variant: variant)

        if let cachedImage = ClimbArtworkMemoryCache.shared.image(for: cacheKey) {
            return cachedImage
        }

        let resolvedURL: URL?
        if let cachedResolution = ClimbArtworkMemoryCache.shared.resolvedURL(for: cacheKey) {
            resolvedURL = cachedResolution.url
        } else {
            let url = await imageRepository.resolveImageURL(for: climb, variant: variant)
            guard !Task.isCancelled else { return nil }
            ClimbArtworkMemoryCache.shared.storeResolvedURL(url, for: cacheKey)
            resolvedURL = url
        }

        guard let resolvedURL else { return nil }

        if let cachedURLImage = ImageCache.shared.image(for: resolvedURL) {
            ClimbArtworkMemoryCache.shared.store(cachedURLImage, for: cacheKey)
            return cachedURLImage
        }

        let image = await ClimbArtworkImageLoader.shared.loadImage(from: resolvedURL)
        guard !Task.isCancelled else { return nil }

        if let image {
            ClimbArtworkMemoryCache.shared.store(image, for: cacheKey)
        }

        return image
    }

    private static func cacheKey(for climb: Climb, variant: ClimbImageVariant) -> String {
        "\(climb.id)-\(variant.rawValue)-v\(climb.imageSetVersion)"
    }

    private var placeholderSymbol: String {
        switch climb.category {
        case "mountain":
            return "mountain.2.fill"
        case "bridge":
            return "point.topleft.down.curvedto.point.bottomright.up.fill"
        case "pyramid":
            return "triangle.fill"
        case "stadium":
            return "sportscourt.fill"
        default:
            return "building.2.fill"
        }
    }

    @MainActor
    private func loadArtwork() async {
        if let cachedImage = ClimbArtworkMemoryCache.shared.image(for: cacheKey) {
            loadedImage = cachedImage
            loadedImageKey = cacheKey
            isLoading = false
            return
        }

        isLoading = true

        let image = await Self.loadImage(
            for: climb,
            variant: variant,
            imageRepository: imageRepository
        )

        guard !Task.isCancelled else { return }

        if let image {
            loadedImage = image
            loadedImageKey = cacheKey
        }

        isLoading = false
    }
}

private struct CachedClimbArtworkURL {
    let url: URL?
}

private final class ClimbArtworkMemoryCache: @unchecked Sendable {
    static let shared = ClimbArtworkMemoryCache()

    private let images = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var resolvedURLs: [String: URL?] = [:]

    private init() {
        images.countLimit = 72
        images.totalCostLimit = 64 * 1024 * 1024
    }

    func image(for key: String) -> UIImage? {
        images.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, for key: String) {
        let pixelWidth = Int(image.size.width * image.scale)
        let pixelHeight = Int(image.size.height * image.scale)
        images.setObject(
            image,
            forKey: key as NSString,
            cost: pixelWidth * pixelHeight * 4
        )
    }

    func resolvedURL(for key: String) -> CachedClimbArtworkURL? {
        lock.lock()
        defer { lock.unlock() }

        guard resolvedURLs.keys.contains(key) else { return nil }
        return CachedClimbArtworkURL(url: resolvedURLs[key] ?? nil)
    }

    func storeResolvedURL(_ url: URL?, for key: String) {
        lock.lock()
        resolvedURLs[key] = url
        lock.unlock()
    }
}

private struct ClimbArtworkImageLoader: Sendable {
    static let shared = ClimbArtworkImageLoader()

    func loadImage(from url: URL) async -> UIImage? {
        if let cachedImage = ImageCache.shared.image(for: url) {
            return cachedImage
        }

        let image: UIImage?
        if url.isFileURL {
            image = loadLocalImage(from: url)
        } else {
            image = await RemoteMediaLoader.shared.loadPhoto(from: url)
        }

        if let image {
            ImageCache.shared.store(image, for: url)
        }

        return image
    }

    private func loadLocalImage(from url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}
