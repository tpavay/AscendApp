import Foundation

/// When a session's name resolution and profile read have finished, for work that must not run
/// beside them.
///
/// A restored session has a user from the moment the app starts, but that work only begins at
/// Firebase's first auth callback, so until then there is nothing to wait on and a caller would
/// read "nothing running" as "finished". The hold covers that gap.
@MainActor
final class ProfileLoadGate {
    private var firstCallback: Task<Void, Never>?
    private var firstCallbackContinuation: AsyncStream<Void>.Continuation?
    private var load: Task<Void, Never>?

    /// For a session restored before Firebase has called back.
    func holdUntilFirstAuthCallback() {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        firstCallbackContinuation = continuation
        firstCallback = Task {
            for await _ in stream {}
        }
    }

    func authCallbackArrived() {
        firstCallbackContinuation?.finish()
        firstCallbackContinuation = nil
    }

    func track(_ load: Task<Void, Never>) {
        self.load = load
    }

    func settled() async {
        await firstCallback?.value
        await load?.value
    }
}
