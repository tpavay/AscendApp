import Foundation

/// Warms the climb-image cache with a climb's progress cut-out ahead of a live climb.
///
/// Called when a climb's detail page appears - the step every climber passes through before
/// Start - and for the featured climb once the catalog names it. Nothing is fetched in bulk: a
/// climb's cut-out is downloaded only once someone looks at that climb. Fire-and-forget at
/// utility priority; a miss here only means the live session fetches it itself.
enum ClimbProgressArtworkPrefetcher {
    static func prefetch(
        for climb: Climb,
        repository: any ClimbProgressImageRepository = StorageClimbProgressImageRepository.shared
    ) {
        guard let artwork = climb.progressArtwork, artwork.isUsable(forClimbID: climb.id) else { return }
        Task(priority: .utility) {
            await repository.prefetch(artwork)
        }
    }
}
