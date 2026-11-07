import Testing
@testable import AscendApp

/// The one ordering the onboarding hand-off cannot see from its own seams: a restored session asks
/// whether the profile load has finished before Firebase has started it.
@MainActor
struct ProfileLoadGateTests {
    private final class Flag {
        var isSet = false
    }

    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    private func watch(_ gate: ProfileLoadGate) -> (Flag, Task<Void, Never>) {
        let flag = Flag()
        return (flag, Task {
            await gate.settled()
            flag.isSet = true
        })
    }

    @Test
    func aRestoredSessionIsNotSettledBeforeFirebaseHasCalledBackAndStartedTheLoad() async {
        let gate = ProfileLoadGate()
        gate.holdUntilFirstAuthCallback()
        let (settled, waiter) = watch(gate)

        await settle()
        #expect(!settled.isSet, "nothing running yet is not the same as finished")

        let release = AsyncStream<Void>.makeStream()
        gate.track(Task {
            for await _ in release.stream {}
        })
        gate.authCallbackArrived()
        await settle()
        #expect(!settled.isSet, "the callback only started the load")

        release.continuation.finish()
        await waiter.value
        #expect(settled.isSet)
    }

    @Test
    func everyCallerWaitingOnTheHoldIsReleased() async {
        let gate = ProfileLoadGate()
        gate.holdUntilFirstAuthCallback()
        let (first, firstWaiter) = watch(gate)
        let (second, secondWaiter) = watch(gate)

        await settle()
        gate.authCallbackArrived()
        await firstWaiter.value
        await secondWaiter.value

        #expect(first.isSet)
        #expect(second.isSet)
    }

    @Test
    func aCallbackBeforeAnyoneAsksLeavesNothingToWaitFor() async {
        let gate = ProfileLoadGate()
        gate.holdUntilFirstAuthCallback()
        gate.authCallbackArrived()
        gate.authCallbackArrived()

        await gate.settled()
    }

    @Test
    func aSessionWithNothingToRestoreIsAlreadySettled() async {
        await ProfileLoadGate().settled()
    }
}
