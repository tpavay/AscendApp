import Foundation

/// The order of the work a signed-in session runs on launch and on every foreground.
///
/// The block list is read alongside the head of the chain rather than behind it. Until it has
/// loaded, every other climber's name is masked as "Blocked climber" on purpose (the resolver
/// fails closed), while boards render their cached rows at once - so a block-list read queued
/// behind the RevenueCat refresh and the media-upload sweep showed every climber on Today,
/// Leaderboards and the Mountain as blocked for as long as those took on a cold launch. Neither
/// step is a prerequisite for the read, and neither waits for it.
///
/// Everything after the uploads still starts only once the block list has answered, so the
/// local bootstrap keeps the hydrated session it always had.
@MainActor
struct AuthenticatedSessionWorkChain {
    typealias Step = @MainActor @Sendable () async -> Void

    let hydrateBlockList: Step
    let refreshEntitlements: Step
    let processPendingUploads: Step
    let bootstrapLocalState: Step
    let synchronizePushDevice: Step
    /// Whether the account this chain was scheduled for is still the signed-in one.
    let isCurrentSession: @MainActor @Sendable () -> Bool

    func run() async {
        async let blockListHydration: Void = hydrateBlockList()

        await refreshEntitlements()
        guard isCurrentSession() else { return }

        await processPendingUploads()
        guard isCurrentSession() else { return }

        await blockListHydration
        guard isCurrentSession() else { return }

        await bootstrapLocalState()
        guard isCurrentSession() else { return }

        await synchronizePushDevice()
    }
}
