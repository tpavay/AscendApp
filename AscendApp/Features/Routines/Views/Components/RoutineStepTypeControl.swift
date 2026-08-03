import SwiftUI

/// The only control left below the timeline. Everything else about an interval is authored by
/// dragging it, so this row carries the step type and Delete, both acting on whichever block
/// is selected.
struct RoutineStepTypeControl: View {
    let stepType: RoutineStepTypeOption
    let onSelect: (RoutineStepTypeOption) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Step", selection: stepTypeBinding) {
                    ForEach(RoutineStepTypeOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            } label: {
                RoutineStepTypeRowLabel(stepType: stepType)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Step type")
            .accessibilityValue(stepType.displayName)

            RoutineIntervalDeleteButton(onDelete: onDelete)
        }
    }

    private var stepTypeBinding: Binding<RoutineStepTypeOption> {
        Binding(
            get: { stepType },
            set: { option in
                guard option != stepType else { return }
                onSelect(option)
                HapticsManager.shared.trigger(.lightImpact)
            }
        )
    }
}

#Preview {
    @Previewable @State var stepType: RoutineStepTypeOption = .standard

    RoutineStepTypeControl(
        stepType: stepType,
        onSelect: { stepType = $0 },
        onDelete: {}
    )
    .padding(20)
    .background(Color.black)
    .preferredColorScheme(.dark)
}
