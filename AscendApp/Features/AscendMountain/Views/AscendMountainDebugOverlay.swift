#if DEBUG
import SwiftUI

/// Developer-only readout for tuning Ascend Mountain on a real stair stepper (spec 41).
/// Compiled into Dev builds only; Staging and Release never contain it.
struct AscendMountainDebugOverlay: View {
    @Bindable var state: MountainDebugState
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isExpanded.toggle()
            } label: {
                Label(isExpanded ? "DEBUG" : "DBG", systemImage: "ladybug.fill")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.accent)
            }
            .buttonStyle(.plain)

            if isExpanded {
                readout
                offsetControls
            }
        }
        .padding(10)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .fixedSize()
    }

    private var readout: some View {
        let metrics = state.metrics
        return VStack(alignment: .leading, spacing: 2) {
            row("FPS", metrics.framesPerSecond.formatted(.number.precision(.fractionLength(0))))
            row("logical", metrics.logicalSteps.formatted())
            row("visual", metrics.visualSteps.formatted(.number.precision(.fractionLength(2))))
            row("lag", (Double(metrics.logicalSteps) - metrics.visualSteps).formatted(.number.precision(.fractionLength(2))))
            row("cadence", metrics.renderCadenceStepsPerMinute.formatted(.number.precision(.fractionLength(0))) + " spm")
            row("anim", metrics.animationPlaybackRate.formatted(.number.precision(.fractionLength(2))) + "x  i " + metrics.animationIntensity.formatted(.number.precision(.fractionLength(2))))
            row("chunks", "\(metrics.activeChunks) active  \(metrics.idleChunkSlots) idle  \(metrics.chunkRecycles) recycled")
            row("chunk", "#\(metrics.chunkIndex) \(metrics.chunkKind)")
            row("altitude", metrics.virtualAltitudeMetres.formatted(.number.precision(.fractionLength(1))) + " m")
            row("origin", metrics.renderOriginDistanceMetres.formatted(.number.precision(.fractionLength(1))) + " m")
            row("biome", metrics.biome)
            row("ghosts", "\(metrics.ghostCount)")
            row("memory", metrics.residentMemoryMegabytes.map { $0.formatted(.number.precision(.fractionLength(0))) + " MB" } ?? "-")
        }
    }

    private var offsetControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("visual offset \(state.visualStepOffset.formatted())")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 6) {
                offsetButton("+1k") { state.visualStepOffset += 1_000 }
                offsetButton("+100k") { state.visualStepOffset += 100_000 }
                offsetButton("1M") { state.visualStepOffset = 1_000_000 }
                offsetButton("0") { state.visualStepOffset = 0 }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 58, alignment: .leading)
            Text(value)
                .foregroundStyle(.white)
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
    }

    private func offsetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(Color.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
#endif
