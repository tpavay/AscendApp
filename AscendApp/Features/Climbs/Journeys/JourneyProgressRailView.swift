#if DEBUG
import SwiftUI

struct JourneyProgressRailView: View {
    let journey: JourneyPrototype
    let completedClimbIds: Set<String>
    let selectedClimbId: String?
    let onSelectClimb: (Climb) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(journey.steps(in: completedClimbIds)) { step in
                Button {
                    onSelectClimb(step.climb)
                } label: {
                    JourneyStepRow(
                        step: step,
                        accent: journey.accent,
                        isSelected: selectedClimbId == step.climb.id,
                        isLast: step.index == journey.climbs.count - 1
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }
}
#endif
