import SwiftUI

/// Delete sits beside the step control, because it lost its home when the editor card went.
struct RoutineIntervalDeleteButton: View {
    let onDelete: () -> Void

    var body: some View {
        Button {
            onDelete()
            HapticsManager.shared.trigger(.mediumImpact)
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.red.opacity(0.92))
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.red.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.red.opacity(0.28), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(RoutineIntervalVoiceOver.Action.delete)
    }
}

#Preview {
    RoutineIntervalDeleteButton(onDelete: {})
        .padding(20)
        .background(Color.black)
        .preferredColorScheme(.dark)
}
