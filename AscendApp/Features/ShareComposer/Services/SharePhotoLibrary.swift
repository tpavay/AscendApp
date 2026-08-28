import AVFoundation
import Observation
import Photos
import UIKit

/// Backs the custom Camera Roll grid: authorization, album and asset fetch, the date scope, and
/// thumbnail / full-asset loading. Photos access is requested at first use (point of use), never in
/// onboarding.
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

    /// Albums offered by the All Albums grid and the filter row's shortcuts.
    ///
    /// Empty under `.limited`, where PhotoKit cannot fetch user albums at all, and empty until the
    /// off-actor load lands - the grid draws its own loading state rather than blocking.
    private(set) var albums: [ShareAlbum] = []

    /// A counter rather than a flag: the initial load and a change-observer refresh overlap, and a
    /// bare bool lets whichever finishes first declare both of them done.
    private var albumLoadsInFlight = 0
    var isLoadingAlbums: Bool { albumLoadsInFlight > 0 }

    /// True while an asset fetch is in flight. Without it an empty `assets` means both "still
    /// counting a 30,000-photo library" and "you have no photos", and the grid tells the first
    /// climber the second thing.
    private(set) var isLoadingAssets = false

    /// Stamps every asset fetch, so a slower refresh started against an older scope cannot land on
    /// top of a newer one. Cancellation would not do: a library-change refresh must not be able to
    /// kill the fetch a climber's own tap started.
    private var assetGeneration = 0

    /// What the Camera Roll tab is showing. Mutated only through `select` / `setDateWindow`.
    private(set) var scope = ShareCameraRollScope.recents

    /// Years the roll actually spans, newest first, so a phone whose library starts in 2019 never
    /// offers 2014.
    private(set) var availableYears: [Int] = []

    /// PhotoKit's image manager is thread-safe and its request callbacks fire on
    /// background queues, so the loading methods below are `nonisolated`. The
    /// manager is therefore accessed off the main actor. This is safe because
    /// `PHCachingImageManager` is itself thread-safe.
    private let imageManager = PHCachingImageManager()

    /// Non-Sendable values ferried across a Photos callback or actor boundary.
    private struct SendableImage: @unchecked Sendable { let image: UIImage? }
    private struct SendableURL: @unchecked Sendable { let url: URL? }

    /// Registered for the life of this object. The observer unregisters itself, because a
    /// `@MainActor` class's `deinit` is nonisolated and cannot reach its own stored properties.
    private var changeObserver: ChangeObserver?

    /// The coalescing window for `photoLibraryDidChange`, held so a burst of callbacks reschedules
    /// one refresh instead of stacking several.
    private var pendingChangeTask: Task<Void, Never>?

    // MARK: - Authorization + fetch

    func loadIfNeeded() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized:
            accessState = .authorized
        case .limited:
            accessState = .limited
        case .denied, .restricted:
            accessState = .denied
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            switch granted {
            case .authorized: accessState = .authorized
            case .limited: accessState = .limited
            default: accessState = .denied
            }
        @unknown default:
            accessState = .denied
        }

        guard accessState != .denied else { return }

        startObservingLibrary()
        await refreshAssets()
        await refreshAlbums()
        await refreshAvailableYears()
    }

    // MARK: - Scope

    /// Switch what the grid is showing. Selecting anything but an album clears the browsed album,
    /// so the filter row stops offering a way back into the album grid.
    func select(_ selection: ShareCameraRollSelection, browsedFromAllAlbums: Bool = false) async {
        scope.selection = selection
        scope.browsedAlbum = browsedFromAllAlbums ? selection.album : nil
        await refreshAssets()
    }

    func setDateWindow(_ window: ShareDateWindow?) async {
        scope.dateWindow = window
        await refreshAssets()
    }

    /// How many photos the given date window would leave in the current album.
    ///
    /// The date sheet's primary button reads this live, so it can refuse to apply a combination that
    /// holds nothing. It counts inside the album already selected, or the number would be a promise
    /// the grid breaks.
    func photoCount(forDateWindow window: ShareDateWindow?) async -> Int {
        let collectionID = scope.selection.album?.id
        return await Self.assetCount(collectionID: collectionID, dateWindow: window)
    }

    // MARK: - Assets

    private func refreshAssets() async {
        guard accessState != .denied else { return }

        assetGeneration &+= 1
        let generation = assetGeneration

        // The album browser draws albums, not photos, so it needs no asset fetch at all. The
        // generation still moved, so a fetch already in flight can no longer land behind it.
        guard scope.showsPhotos else {
            isLoadingAssets = false
            return
        }

        isLoadingAssets = true
        let collectionID = scope.selection.album?.id
        let loaded = await Self.loadAssets(collectionID: collectionID, dateWindow: scope.dateWindow)
        guard generation == assetGeneration else { return }

        switch loaded {
        case .some(let fetched):
            assets = fetched
        case .none:
            // The album stopped resolving - deleted since it was remembered. Fall back to Recents
            // silently: an album the climber deleted themselves is not news.
            scope = scope.clearingAlbum()
            let fallback = await Self.loadAssets(collectionID: nil, dateWindow: scope.dateWindow) ?? []
            guard generation == assetGeneration else { return }
            assets = fallback
        }
        isLoadingAssets = false
    }

    /// `nil` means the named collection no longer resolves. An empty array means it resolved and
    /// holds nothing, which is a different state and gets a different screen.
    nonisolated private static func loadAssets(
        collectionID: String?,
        dateWindow: ShareDateWindow?
    ) async -> [PHAsset]? {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = fetchPredicate(dateWindow: dateWindow)

        let result: PHFetchResult<PHAsset>
        if let collectionID {
            guard let collection = PHAssetCollection
                .fetchAssetCollections(withLocalIdentifiers: [collectionID], options: nil)
                .firstObject
            else { return nil }
            result = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            result = PHAsset.fetchAssets(with: options)
        }

        var collected: [PHAsset] = []
        collected.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in collected.append(asset) }
        return collected
    }

    nonisolated private static func assetCount(
        collectionID: String?,
        dateWindow: ShareDateWindow?
    ) async -> Int {
        let options = PHFetchOptions()
        options.predicate = fetchPredicate(dateWindow: dateWindow)

        if let collectionID {
            guard let collection = PHAssetCollection
                .fetchAssetCollections(withLocalIdentifiers: [collectionID], options: nil)
                .firstObject
            else { return 0 }
            return PHAsset.fetchAssets(in: collection, options: options).count
        }
        return PHAsset.fetchAssets(with: options).count
    }

    /// Images and videos, optionally narrowed to a date window.
    ///
    /// Album and date compose into one predicate applied identically to `fetchAssets(with:)` and
    /// `fetchAssets(in:)`, so the two scopes are genuinely independent - no special case, no second
    /// code path.
    nonisolated private static func fetchPredicate(dateWindow: ShareDateWindow?) -> NSPredicate {
        let mediaType = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
        guard let interval = dateWindow?.dateInterval() else { return mediaType }

        // Half-open, so an asset created exactly on the boundary cannot land in two windows.
        let window = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@",
            interval.start as NSDate,
            interval.end as NSDate
        )
        return NSCompoundPredicate(andPredicateWithSubpredicates: [mediaType, window])
    }

    // MARK: - Albums

    private func refreshAlbums() async {
        // PhotoKit cannot fetch user albums under limited access at all, so the call is skipped
        // rather than made and found empty: an empty result there is indistinguishable from a
        // climber who owns no albums, and the two need opposite screens.
        guard accessState == .authorized else {
            albums = []
            return
        }

        albumLoadsInFlight += 1
        defer { albumLoadsInFlight -= 1 }
        albums = await Self.loadAlbums()
    }

    nonisolated private static func loadAlbums() async -> [ShareAlbum] {
        var albums = userAlbums()
        albums.append(contentsOf: smartAlbums())
        return albums
    }

    /// The climber's own albums, in the order the Photos app shows them, recursed one level into
    /// folders so an album inside a folder is not invisible. Folder names are not shown; the album
    /// name alone is what anyone searches for.
    nonisolated private static func userAlbums() -> [ShareAlbum] {
        var albums: [ShareAlbum] = []

        func walk(_ collections: PHFetchResult<PHCollection>, depth: Int) {
            collections.enumerateObjects { collection, _, _ in
                if let assetCollection = collection as? PHAssetCollection {
                    // Shared albums are excluded from v1: their assets are cloud-only, so tapping
                    // one starts a network download inside a picker with no loading state for it,
                    // and limited access cannot see them at all.
                    guard assetCollection.assetCollectionSubtype != .albumCloudShared,
                          assetCollection.assetCollectionSubtype != .albumMyPhotoStream
                    else { return }
                    albums.append(makeAlbum(from: assetCollection, kind: .user))
                } else if let list = collection as? PHCollectionList, depth < 1 {
                    walk(PHCollection.fetchCollections(in: list, options: nil), depth: depth + 1)
                }
            }
        }

        walk(PHCollection.fetchTopLevelUserCollections(with: nil), depth: 0)
        return albums
    }

    /// The curated smart set, in fixed order. Everything else PhotoKit offers is noise here, and
    /// Hidden is excluded permanently - it needs `includeHiddenAssets`, and surfacing it would be a
    /// privacy incident with a tile on it.
    nonisolated private static func smartAlbums() -> [ShareAlbum] {
        let subtypes: [PHAssetCollectionSubtype] = [
            .smartAlbumFavorites,
            .smartAlbumVideos,
            .smartAlbumScreenshots,
            .smartAlbumDepthEffect,
            .smartAlbumSelfPortraits
        ]

        return subtypes.compactMap { subtype in
            guard let collection = PHAssetCollection
                .fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
                .firstObject
            else { return nil }
            return makeAlbum(from: collection, kind: .smart(smartKind(for: subtype)))
        }
    }

    /// The pinned shortcuts key off this rather than off `localizedTitle`, which PhotoKit returns in
    /// the device's language.
    nonisolated private static func smartKind(
        for subtype: PHAssetCollectionSubtype
    ) -> ShareAlbum.Kind.Smart {
        switch subtype {
        case .smartAlbumFavorites: return .favorites
        case .smartAlbumVideos: return .videos
        default: return .other
        }
    }

    nonisolated private static func makeAlbum(
        from collection: PHAssetCollection,
        kind: ShareAlbum.Kind
    ) -> ShareAlbum {
        let options = PHFetchOptions()
        options.predicate = fetchPredicate(dateWindow: nil)

        return ShareAlbum(
            id: collection.localIdentifier,
            title: collection.localizedTitle ?? "Untitled",
            // A real fetched count. `estimatedAssetCount` is documented as an estimate that returns
            // NSNotFound when it cannot answer quickly.
            count: PHAsset.fetchAssets(in: collection, options: options).count,
            newestAssetDate: collection.endDate,
            kind: kind
        )
    }

    // MARK: - Years

    private func refreshAvailableYears() async {
        availableYears = await Self.loadAvailableYears()
    }

    nonisolated private static func loadAvailableYears() async -> [Int] {
        let options = PHFetchOptions()
        options.predicate = fetchPredicate(dateWindow: nil)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.fetchLimit = 1

        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        guard let oldest = PHAsset.fetchAssets(with: options).firstObject?.creationDate else {
            return [currentYear]
        }

        let oldestYear = calendar.component(.year, from: oldest)
        guard oldestYear <= currentYear else { return [currentYear] }
        return Array((oldestYear...currentYear).reversed())
    }

    // MARK: - Library changes

    /// Without this, the limited-access *Add more* button appears to do nothing, and a photo taken
    /// while the composer is open never shows up.
    private func startObservingLibrary() {
        guard changeObserver == nil else { return }

        changeObserver = ChangeObserver { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleLibraryRefresh()
            }
        }
    }

    /// PhotoKit fires its change callback repeatedly through an iCloud sync or a burst import, and
    /// each refresh enumerates the whole library and counts every album, so a burst is collapsed
    /// into one refresh rather than run once per notification.
    private func scheduleLibraryRefresh() {
        pendingChangeTask?.cancel()
        pendingChangeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.libraryDidChange()
        }
    }

    private func libraryDidChange() async {
        // The limited-library picker changes which assets exist for us, so authorization is re-read
        // rather than assumed: a climber can widen access from inside that sheet.
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized: accessState = .authorized
        case .limited: accessState = .limited
        case .denied, .restricted: accessState = .denied
        default: break
        }

        guard accessState != .denied else { return }
        await refreshAssets()
        await refreshAlbums()
        await refreshAvailableYears()
    }

    /// PhotoKit's observer protocol is Objective-C, so it needs an `NSObject`. Keeping it separate
    /// leaves `SharePhotoLibrary` a plain `@Observable` class.
    private final class ChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
        private let onChange: @Sendable () -> Void

        init(onChange: @escaping @Sendable () -> Void) {
            self.onChange = onChange
            super.init()
            PHPhotoLibrary.shared().register(self)
        }

        deinit {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }

        // Called on an arbitrary background queue.
        func photoLibraryDidChange(_ changeInstance: PHChange) {
            onChange()
        }
    }

    // MARK: - Loading
    //
    // These are `nonisolated` so PhotoKit can invoke their result handlers on
    // its own background queues without tripping a main-actor executor
    // assertion (`dispatch_assert_queue`). They take the asset's `localIdentifier`
    // (a `Sendable` String) rather than the non-Sendable `PHAsset`, re-fetching
    // the asset off the main actor.

    nonisolated func thumbnail(forIdentifier id: String, size: CGFloat) async -> UIImage? {
        guard let asset = Self.fetchAsset(id) else { return nil }
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

    /// The newest asset in an album, for its tile in the All Albums grid.
    nonisolated func albumCoverThumbnail(albumID: String, size: CGFloat) async -> UIImage? {
        guard let collection = PHAssetCollection
            .fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil)
            .firstObject
        else { return nil }

        let options = PHFetchOptions()
        options.predicate = Self.fetchPredicate(dateWindow: nil)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1

        guard let asset = PHAsset.fetchAssets(in: collection, options: options).firstObject else {
            return nil
        }
        return await thumbnail(forIdentifier: asset.localIdentifier, size: size)
    }

    nonisolated func fullImage(forIdentifier id: String) async -> UIImage? {
        guard let asset = Self.fetchAsset(id) else { return nil }
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

    nonisolated func videoURL(forIdentifier id: String) async -> URL? {
        guard let asset = Self.fetchAsset(id) else { return nil }
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

    nonisolated private static func fetchAsset(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }
}
