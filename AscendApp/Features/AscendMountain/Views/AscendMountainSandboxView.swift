#if DEBUG
import SwiftUI

/// Dev-only Ascend Mountain with a simulated climber, reachable from Debug Tools or by launching
/// a Dev build with `-AscendMountainSandbox`. `-AscendMountainSandboxSPM <n>` sets the starting
/// cadence, `-AscendMountainSandboxOffset <n>` the starting visual step offset, and
/// `-AscendMountainDebugOverlayCollapsed 1` folds the readout away for a screenshot.
///
/// The simulator has no headphone motion, so the real session cannot get past its headphone
/// gate there; this drives the identical scene from a step clock instead, for tuning the feel
/// and exercising huge step counts without a stair stepper.
struct AscendMountainSandboxView: View {
    static let launchArgument = "-AscendMountainSandbox"

    /// Your best a few steps ahead at a slightly slower pace, and a pacer slightly faster, so
    /// both ghosts can be seen racing the default 90 SPM climber.
    static let demoGhosts: [MountainGhost] = [
        MountainGhost(id: "best", kind: .personalBest, label: "YOUR BEST") { elapsed in 6 + elapsed * 88 / 60 },
        .pacer(stepsPerMinute: 95)
    ]

    static var isRequestedAtLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    @State private var simulator = MountainStepSimulator(
        stepsPerMinute: UserDefaults.standard.object(forKey: "AscendMountainSandboxSPM") == nil
            ? 90
            : UserDefaults.standard.double(forKey: "AscendMountainSandboxSPM")
    )
    @State private var debugState: MountainDebugState = {
        let state = MountainDebugState()
        state.visualStepOffset = UserDefaults.standard.integer(forKey: "AscendMountainSandboxOffset")
        return state
    }()

    var body: some View {
        let simulator = simulator
        ZStack(alignment: .top) {
            AscendMountainRealityView(
                seed: MountainCourse.ascendMountainSeed,
                stepSource: { simulator.steps },
                debugState: debugState,
                ghostSource: { Self.demoGhosts }
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                AscendMountainDebugOverlay(state: debugState)
                Spacer(minLength: 0)
                controls
            }
            .padding(16)
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: simulator.stepsPerMinute) {
            await simulator.run()
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(simulator.steps.formatted()) STEPS")
                    .font(.montserratBold(size: 22))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Spacer()
                Text("\(Int(simulator.stepsPerMinute)) SPM")
                    .font(.montserratBold(size: 16))
                    .monospacedDigit()
                    .foregroundStyle(Color.accent)
            }

            HStack(spacing: 6) {
                ForEach([0, 60, 90, 120, 150, 180], id: \.self) { spm in
                    Button {
                        simulator.stepsPerMinute = Double(spm)
                    } label: {
                        Text("\(spm)")
                            .font(.montserratBold(size: 13))
                            .foregroundStyle(Int(simulator.stepsPerMinute) == spm ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(
                                Capsule().fill(Int(simulator.stepsPerMinute) == spm ? Color.accent : .white.opacity(0.14))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                simulator.steps += 1
            } label: {
                Text("ONE STEP")
                    .font(.montserratBold(size: 14))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Capsule().fill(Color.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A stand-in step counter that ticks at a chosen cadence with a little human irregularity.
@MainActor
@Observable
final class MountainStepSimulator {
    var steps = 0
    var stepsPerMinute: Double

    init(stepsPerMinute: Double) {
        self.stepsPerMinute = stepsPerMinute
    }

    func run() async {
        while !Task.isCancelled, stepsPerMinute > 0 {
            let interval = 60 / stepsPerMinute * Double.random(in: 0.9...1.1)
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return
            }
            steps += 1
        }
    }
}
#endif
